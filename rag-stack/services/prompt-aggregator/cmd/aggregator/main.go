package main

import (
	"context"
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
	"app-builds/common/health"
	pulsarCommon "app-builds/common/pulsar"
	"app-builds/common/telemetry"
	"app-builds/common/tlsutil"
	"app-builds/prompt-aggregator/internal/config"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/types/known/structpb"
)

func SessionTopic(id string) string {
	return fmt.Sprintf("persistent://rag-pipeline/sessions/%s", id)
}

func main() {
	cfg := config.LoadConfig()
	log.Printf("Starting prompt-aggregator for topic: %s", cfg.PulsarCompletionTopic)

	healthSrv := health.NewServer()

	shutdown, err := telemetry.InitTracer("prompt-aggregator")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	client, err := pulsarCommon.NewClient(pulsarCommon.Config{URL: cfg.PulsarURL})
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer client.Close()

	// 1. Consumer for Completion Events
	consumer, err := client.NewSharedConsumer(cfg.PulsarCompletionTopic, cfg.PulsarSubscription)
	if err != nil {
		log.Fatalf("Could not subscribe to completion topic: %v", err)
	}
	defer consumer.Close()

	// 2. Producer for Final Results (sent back to Results topic for db-adapter)
	producer, err := client.NewProducer(cfg.PulsarResultsTopic)
	if err != nil {
		log.Fatalf("Could not create results producer: %v", err)
	}
	defer producer.Close()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 3. Healthz Server
	mux := http.NewServeMux()
	healthSrv.RegisterRoutes(mux)

	otelHandler := otelhttp.NewHandler(mux, "prompt-aggregator")

	go func() {
		certFile := os.Getenv("TLS_CERT")
		keyFile := os.Getenv("TLS_KEY")
		if certFile != "" && keyFile != "" {
			tlsCfg, err := tlsutil.NewTLSConfig()
			if err != nil {
				log.Fatalf("Failed to create TLS config: %v", err)
			}
			log.Printf("Health server listening with TLS on :8080")
			server := &http.Server{
				Addr:      ":8080",
				Handler:   otelHandler,
				TLSConfig: tlsCfg,
			}
			if err := server.ListenAndServeTLS(certFile, keyFile); err != nil && err != http.ErrServerClosed {
				log.Printf("Health server failed: %v", err)
			}
		} else {
			log.Printf("Health server listening on :8080")
			if err := http.ListenAndServe(":8080", otelHandler); err != nil {
				log.Printf("Health server failed: %v", err)
			}
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
			if err := protojson.Unmarshal(msg.Payload(), &comp); err != nil {
				log.Printf("Error unmarshaling completion payload: %v", err)
				consumer.Ack(msg)
				continue
			}

			if comp.Status == "FAILED" {
				log.Printf("[%s] Completion event status is FAILED, skipping aggregation", comp.Id)
				consumer.Ack(msg)
				continue
			}

	log.Printf("[%s] Received completion (Status: %s), aggregating chunks from session topic", comp.Id, comp.Status)

	// Aggregate chunks from session topic
	sessionTopic := SessionTopic(comp.Id)
	fullResult, metadata, err := aggregateChunks(ctx, client, sessionTopic, comp)
	if err != nil {
		log.Printf("[%s] Aggregation error on %s: %v (Partial result: %d chars)", comp.Id, sessionTopic, err, len(fullResult))
		// We could send partial result or nack
		consumer.Nack(msg)
		continue
	}

	if fullResult == "" {
		log.Printf("[%s] Warning: Result was empty after aggregation, ignoring", comp.Id)
		consumer.Ack(msg)
		continue
	}

	// Send final result to db-adapter topic
	if err := sendFinalResult(ctx, producer, comp, fullResult, metadata); err != nil {
		log.Printf("[%s] Failed to send final result: %v", comp.Id, err)
		consumer.Nack(msg)
		continue
	}

	log.Printf("[%s] Successfully aggregated and sent result (%d chars)", comp.Id, len(fullResult))
			consumer.Ack(msg)
		}
	}()

	<-sigChan
	log.Printf("Shutting down...")
}

func aggregateChunks(ctx context.Context, client pulsar.Client, topic string, comp contracts.ResponseCompletion) (string, *structpb.Struct, error) {
	reader, err := client.CreateReader(pulsar.ReaderOptions{
		Topic:          topic,
		StartMessageID: pulsar.EarliestMessageID(),
	})
	if err != nil {
		return "", nil, fmt.Errorf("create reader for %s: %w", topic, err)
	}
	defer reader.Close()

	var chunks = make(map[int32]contracts.StreamChunk)
	var lastMetadata *structpb.Struct
	timeout := time.After(30 * time.Second) // Safety timeout for the scan

	for {
		select {
		case <-timeout:
			return "", nil, fmt.Errorf("timed out scanning for chunks in %s", topic)
		case <-ctx.Done():
			return "", nil, ctx.Err()
		default:
			if !reader.HasNext() {
				// Wait a bit for more chunks
				time.Sleep(100 * time.Millisecond)
				if !reader.HasNext() {
					// Check if we have anything
					if len(chunks) > 0 {
						return assemble(chunks), lastMetadata, nil
					}
					return "", nil, fmt.Errorf("reached end of topic %s without finding chunks", topic)
				}
				continue
			}

			msg, err := reader.Next(ctx)
			if err != nil {
				return "", nil, fmt.Errorf("reader next: %w", err)
			}

			var chunk contracts.StreamChunk
			if err := protojson.Unmarshal(msg.Payload(), &chunk); err != nil {
				continue
			}

			if chunk.Id != comp.Id {
				// Not our prompt, but maybe if we see chunks with much later timestamps we can stop?
				// For now, just continue.
				continue
			}

			if chunk.Metadata != nil {
				lastMetadata = chunk.Metadata
			}

			if chunk.Result != "" {
				// Deduplicate by sequence number
				chunks[chunk.SequenceNumber] = chunk
			}

			if chunk.IsLast {
				return assemble(chunks), lastMetadata, nil
			}
		}
	}
}

func assemble(chunkMap map[int32]contracts.StreamChunk) string {
	// Sort by sequence number
	var keys []int32
	for k := range chunkMap {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })

	var sb strings.Builder
	for _, k := range keys {
		sb.WriteString(chunkMap[k].Result)
	}
	return sb.String()
}

func sendFinalResult(ctx context.Context, producer pulsar.Producer, comp contracts.ResponseCompletion, result string, metadata *structpb.Struct) error {
	msg := &contracts.StreamChunk{
		Id:             comp.Id,
		SessionId:      comp.SessionId,
		Result:         result,
		Model:          comp.Model,
		SequenceNumber: 0,
		IsLast:         true,
		Metadata:       metadata,
	}
	payload, err := protojson.Marshal(msg)
	if err != nil {
		return err
	}

	_, err = producer.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
	})
	return err
}
