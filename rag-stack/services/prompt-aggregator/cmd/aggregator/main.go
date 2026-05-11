package main

import (
	"context"
	"fmt"
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
	"app-builds/common/logging"
)

func SessionTopic(id string) string {
	return fmt.Sprintf("persistent://rag-pipeline/sessions/%s", id)
}

func main() {
	cfg := config.LoadConfig()
	logging.Printf("Starting prompt-aggregator for topic: %s", cfg.PulsarCompletionTopic)

	healthSrv := health.NewServer()

	shutdown, err := telemetry.InitTracer("prompt-aggregator")
	if err != nil {
		logging.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	client, err := pulsarCommon.NewClient(pulsarCommon.Config{URL: cfg.PulsarURL})
	if err != nil {
		logging.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer client.Close()

	// 1. Consumer for Completion Events
	consumer, err := client.NewSharedConsumer(cfg.PulsarCompletionTopic, cfg.PulsarSubscription)
	if err != nil {
		logging.Fatalf("Could not subscribe to completion topic: %v", err)
	}
	defer consumer.Close()

	// 2. Producer for Final Results (sent back to Results topic for db-adapter)
	producer, err := client.NewProducer(cfg.PulsarResultsTopic)
	if err != nil {
		logging.Fatalf("Could not create results producer: %v", err)
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
				logging.Fatalf("Failed to create TLS config: %v", err)
			}
			logging.Printf("Health server listening with TLS on :8080")
			server := &http.Server{
				Addr:      ":8080",
				Handler:   otelHandler,
				TLSConfig: tlsCfg,
			}
			if err := server.ListenAndServeTLS(certFile, keyFile); err != nil && err != http.ErrServerClosed {
				logging.Printf("Health server failed: %v", err)
			}
		} else {
			logging.Printf("Health server listening on :8080")
			if err := http.ListenAndServe(":8080", otelHandler); err != nil {
				logging.Printf("Health server failed: %v", err)
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
				logging.Printf("Error receiving completion event: %v", err)
				continue
			}

			var comp contracts.ResponseCompletion
			if err := protojson.Unmarshal(msg.Payload(), &comp); err != nil {
				logging.Printf("Error unmarshaling completion payload: %v", err)
				consumer.Ack(msg)
				continue
			}

			if comp.Status == "FAILED" {
				logging.Printf("[%s] Completion event status is FAILED, skipping aggregation", comp.Id)
				consumer.Ack(msg)
				continue
			}

	logging.Printf("[%s] Received completion (Status: %s), aggregating chunks from session topic", comp.Id, comp.Status)

	// Aggregate chunks from session topic
	sessionTopic := SessionTopic(comp.Id)
	fullResult, metadata, err := aggregateChunks(ctx, client, sessionTopic, &comp)
	if err != nil {
		logging.Printf("[%s] Aggregation error on %s: %v (Partial result: %d chars)", comp.Id, sessionTopic, err, len(fullResult))
		// We could send partial result or nack
		consumer.Nack(msg)
		continue
	}

	if fullResult == "" {
		logging.Printf("[%s] Warning: Result was empty after aggregation, ignoring", comp.Id)
		consumer.Ack(msg)
		continue
	}

	// Send final result to db-adapter topic
	if err := sendFinalResult(ctx, producer, &comp, fullResult, metadata); err != nil {
		logging.Printf("[%s] Failed to send final result: %v", comp.Id, err)
		consumer.Nack(msg)
		continue
	}

	logging.Printf("[%s] Successfully aggregated and sent result (%d chars)", comp.Id, len(fullResult))
			consumer.Ack(msg)
		}
	}()

	<-sigChan
	logging.Printf("Shutting down...")
}

func aggregateChunks(ctx context.Context, client pulsar.Client, topic string, comp *contracts.ResponseCompletion) (string, *structpb.Struct, error) {
	reader, err := client.CreateReader(pulsar.ReaderOptions{
		Topic:          topic,
		StartMessageID: pulsar.EarliestMessageID(),
	})
	if err != nil {
		return "", nil, fmt.Errorf("create reader for %s: %w", topic, err)
	}
	defer reader.Close()

	var chunks = make(map[int32]*contracts.StreamChunk)
	var lastMetadata *structpb.Struct
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	for {
		msg, err := reader.Next(ctx)
		if err != nil {
			// If we timed out or context cancelled, we might have partial chunks
			if (ctx.Err() != nil) && len(chunks) > 0 {
				logging.Printf("[%s] Context cancelled or timed out, returning partial result (%d chunks)", comp.Id, len(chunks))
				return assemble(chunks), lastMetadata, nil
			}
			return "", nil, fmt.Errorf("reader next: %w", err)
		}

		chunk := &contracts.StreamChunk{}
		if err := protojson.Unmarshal(msg.Payload(), chunk); err != nil {
			continue
		}

		if chunk.Id != comp.Id {
			continue
		}

		if chunk.Metadata != nil {
			lastMetadata = chunk.Metadata
		}

		if chunk.Result != "" {
			chunks[chunk.SequenceNumber] = chunk
		}

		if chunk.IsLast {
			return assemble(chunks), lastMetadata, nil
		}
	}
}

func assemble(chunkMap map[int32]*contracts.StreamChunk) string {
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

func sendFinalResult(ctx context.Context, producer pulsar.Producer, comp *contracts.ResponseCompletion, result string, metadata *structpb.Struct) error {
	msg := &contracts.StreamChunk{
		Id:             comp.Id,
		SessionId:      comp.SessionId,
		Result:         result,
		Model:          comp.Model,
		SequenceNumber: 0,
		IsLast:         true,
		Metadata:       metadata,
	}

	marshaller := protojson.MarshalOptions{
		UseProtoNames: true,
	}
	data, err := marshaller.Marshal(msg)
	if err != nil {
		return fmt.Errorf("failed to marshal final result: %w", err)
	}

	logging.Printf("[%s] Sending final result (snake_case): %s", comp.Id, string(data))

	_, err = producer.Send(ctx, &pulsar.ProducerMessage{
		Payload: data,
	})
	return err
}
