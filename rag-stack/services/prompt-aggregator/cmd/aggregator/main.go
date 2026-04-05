package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"

	"app-builds/common/contracts"
	"app-builds/common/tlsutil"
	"app-builds/prompt-aggregator/internal/config"
)

func main() {
	cfg := config.LoadConfig()
	log.Printf("Starting prompt-aggregator for topic: %s", cfg.PulsarCompletionTopic)

	opts := pulsar.ClientOptions{URL: cfg.PulsarURL}
	if certPath := tlsutil.PulsarTLSCertPath(cfg.PulsarURL); certPath != "" {
		opts.TLSTrustCertsFilePath = certPath
	}

	client, err := pulsar.NewClient(opts)
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer client.Close()

	// 1. Consumer for Completion Events
	consumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.PulsarCompletionTopic,
		SubscriptionName: cfg.PulsarSubscription,
		Type:             pulsar.Shared,
	})
	if err != nil {
		log.Fatalf("Could not subscribe to completion topic: %v", err)
	}
	defer consumer.Close()

	// 2. Producer for Final Results (sent back to Results topic for db-adapter)
	producer, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.PulsarResultsTopic,
	})
	if err != nil {
		log.Fatalf("Could not create results producer: %v", err)
	}
	defer producer.Close()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 3. Healthz Server
	go func() {
		http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		})
		http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		})
		log.Printf("Health server listening on :8080")
		if err := http.ListenAndServe(":8080", nil); err != nil {
			log.Printf("Health server failed: %v", err)
		}
	}()

	go func() {
		for {
			msg, err := consumer.Receive(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				log.Printf("Error receiving completion event: %v", err)
				continue
			}

			var comp contracts.ResponseCompletion
			if err := json.Unmarshal(msg.Payload(), &comp); err != nil {
				log.Printf("Error unmarshaling completion payload: %v", err)
				consumer.Ack(msg)
				continue
			}

			if comp.Status == "FAILED" {
				log.Printf("[%s] Completion event status is FAILED, skipping aggregation", comp.ID)
				consumer.Ack(msg)
				continue
			}

	log.Printf("[%s] Received completion (Status: %s), aggregating chunks starting from %s", comp.ID, comp.Status, comp.StartTimestamp)

	// Aggregate chunks
	fullResult, err := aggregateChunks(ctx, client, cfg.PulsarResultsTopic, comp)
	if err != nil {
		log.Printf("[%s] Aggregation error: %v (Partial result: %d chars)", comp.ID, err, len(fullResult))
		// We could send partial result or nack
		consumer.Nack(msg)
		continue
	}

	if fullResult == "" {
		log.Printf("[%s] Warning: Result was empty after aggregation, ignoring", comp.ID)
		consumer.Ack(msg)
		continue
	}

	// Send final result to db-adapter topic
	if err := sendFinalResult(ctx, producer, comp, fullResult); err != nil {
		log.Printf("[%s] Failed to send final result: %v", comp.ID, err)
		consumer.Nack(msg)
		continue
	}

			log.Printf("[%s] Successfully aggregated and sent result (%d chars)", comp.ID, len(fullResult))
			consumer.Ack(msg)
		}
	}()

	<-sigChan
	log.Printf("Shutting down...")
}

func aggregateChunks(ctx context.Context, client pulsar.Client, topic string, comp contracts.ResponseCompletion) (string, error) {
	reader, err := client.CreateReader(pulsar.ReaderOptions{
		Topic:          topic,
		StartMessageID: pulsar.EarliestMessageID,
	})
	if err != nil {
		return "", fmt.Errorf("create reader: %w", err)
	}
	defer reader.Close()

	startTS, err := time.Parse(time.RFC3339, comp.StartTimestamp)
	if err != nil {
		return "", fmt.Errorf("parse timestamp: %w", err)
	}

	// Seek back to start of sequence (with a bit of buffer)
	if err := reader.SeekByTime(startTS.Add(-5 * time.Second)); err != nil {
		return "", fmt.Errorf("seek by time: %w", err)
	}

	var chunks = make(map[int]contracts.StreamChunk)
	timeout := time.After(30 * time.Second) // Safety timeout for the scan

	for {
		select {
		case <-timeout:
			return "", fmt.Errorf("timed out scanning for chunks")
		case <-ctx.Done():
			return "", ctx.Err()
		default:
			if !reader.HasNext() {
				// We reached the end of the topic but didn't find the 'is_last' chunk?
				// Maybe wait a bit or return what we have?
				time.Sleep(100 * time.Millisecond)
				if !reader.HasNext() {
					// Check if we have anything
					if len(chunks) > 0 {
						return assemble(chunks), nil
					}
					return "", fmt.Errorf("reached end of topic without finding chunks")
				}
				continue
			}

			msg, err := reader.Next(ctx)
			if err != nil {
				return "", fmt.Errorf("reader next: %w", err)
			}

			var chunk contracts.StreamChunk
			if err := json.Unmarshal(msg.Payload(), &chunk); err != nil {
				continue
			}

			if chunk.ID != comp.ID {
				// Not our prompt, but maybe if we see chunks with much later timestamps we can stop?
				// For now, just continue.
				continue
			}

			if chunk.Chunk != "" {
				// Deduplicate by sequence number
				chunks[chunk.Sequence] = chunk
			}

			if chunk.IsLast {
				return assemble(chunks), nil
			}
		}
	}
}

func assemble(chunkMap map[int]contracts.StreamChunk) string {
	// Sort by sequence number
	var keys []int
	for k := range chunkMap {
		keys = append(keys, k)
	}
	sort.Ints(keys)

	var sb strings.Builder
	for _, k := range keys {
		sb.WriteString(chunkMap[k].Chunk)
	}
	return sb.String()
}

func sendFinalResult(ctx context.Context, producer pulsar.Producer, comp contracts.ResponseCompletion, result string) error {
	payload, err := json.Marshal(map[string]interface{}{
		"id":         comp.ID,
		"session_id": comp.SessionID,
		"result":     result,
		"model":      comp.Model,
		"timestamp":  time.Now().UTC().Format(time.RFC3339),
	})
	if err != nil {
		return err
	}

	_, err = producer.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
	})
	return err
}
