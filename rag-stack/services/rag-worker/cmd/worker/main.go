package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"

	"app-builds/common/dlq"
	"app-builds/common/health"
	"app-builds/common/telemetry"
	"app-builds/rag-worker/internal/config"
	"app-builds/rag-worker/internal/models"
	"app-builds/rag-worker/internal/models/granite31"
	"app-builds/rag-worker/internal/models/llama3"
	"app-builds/rag-worker/internal/ollama"
	"app-builds/rag-worker/pkg/messaging"
	"app-builds/rag-worker/pkg/pipeline"
	"app-builds/rag-worker/pkg/search"
)

func main() {
	cfg := config.LoadConfig()

	// Health server with deep readiness checks
	healthSrv := health.NewServer()
	healthSrv.Start(":8080")

	shutdown, err := telemetry.InitTracer("rag-worker")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	// Messaging (Pulsar client + producers)
	msgClient, err := messaging.NewClient(cfg)
	if err != nil {
		log.Fatalf("Could not initialize messaging: %v", err)
	}
	defer msgClient.Close()

	// Model Registry setup (config-driven prompt types)
	registry := models.NewModelRegistry()
	registry.RegisterBackend("ollama", func(endpoint, modelName string) models.ChatClient {
		return ollama.NewClient(endpoint, modelName)
	})
	registry.RegisterPromptType("llama3", llama3.NewPlanner, llama3.NewExecutor)
	registry.RegisterPromptType("granite31", granite31.NewPlanner, granite31.NewExecutor)

	registry.RegisterModel(models.ModelSpec{
		ID:         cfg.PlannerModel,
		Name:       cfg.PlannerModel,
		Endpoint:   cfg.PlannerURL,
		Backend:    "ollama",
		PromptType: cfg.PlannerPromptType,
	})
	registry.RegisterModel(models.ModelSpec{
		ID:         cfg.ExecutorModel,
		Name:       cfg.ExecutorModel,
		Endpoint:   cfg.ExecutorURL,
		Backend:    "ollama",
		PromptType: cfg.ExecutorPromptType,
	})

	// DLQ handler
	dlqHandler, err := dlq.NewHandler(msgClient.PulsarClient(), "rag-worker")
	if err != nil {
		log.Fatalf("Could not create DLQ handler: %v", err)
	}
	defer dlqHandler.Close()

	// Qdrant search via Pulsar
	searcher := search.NewQdrantSearcher(cfg, msgClient.Producers.QdrantOps)

	// Subscribe to Qdrant results
	qResultsSub := fmt.Sprintf("rag-worker-q-res-%s", os.Getenv("HOSTNAME"))
	qResConsumer, err := msgClient.PulsarClient().Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.QdrantResultsTopic,
		SubscriptionName: qResultsSub,
		Type:             pulsar.Exclusive,
	})
	if err != nil {
		log.Fatalf("Could not subscribe to Qdrant results: %v", err)
	}
	defer qResConsumer.Close()
	searcher.StartResultConsumer(qResConsumer)

	// Subscribe to RAG stage topics
	consumer, err := msgClient.PulsarClient().Subscribe(pulsar.ConsumerOptions{
		Topics: []string{
			cfg.PulsarIngressTopic,
			cfg.PulsarPlanTopic,
			cfg.PulsarExecTopic,
		},
		SubscriptionName: cfg.PulsarSubscription,
		Type:             pulsar.Shared,
	})
	if err != nil {
		log.Fatalf("Could not create Pulsar consumer: %v", err)
	}
	defer consumer.Close()

	// Register readiness checks
	healthSrv.RegisterCheck("pulsar", func() error {
		// Consumer is connected if we got this far without fatal
		return nil
	})

	// Pipeline handler
	handler := pipeline.NewHandler(cfg, msgClient, registry, searcher)

	log.Printf("RAG Worker started, listening on multiple stages")

	// Graceful shutdown setup
	ctx, cancel := context.WithCancel(context.Background())
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	var wg sync.WaitGroup
	go func() {
		<-stop
		log.Println("Shutdown signal received, stopping message consumption...")
		cancel()
	}()

	// Message consumption loop
	for {
		msg, err := consumer.Receive(ctx)
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			log.Printf("Error receiving message: %v", err)
			continue
		}

		topic := msg.Topic()
		var stage string
		if strings.HasSuffix(topic, "ingress") {
			stage = "ingress"
		} else if strings.HasSuffix(topic, "plan") {
			stage = "plan"
		} else if strings.HasSuffix(topic, "exec") {
			stage = "exec"
		}

		msgCtx := otel.GetTextMapPropagator().Extract(context.Background(), propagation.MapCarrier(msg.Properties()))

		wg.Add(1)
		go func() {
			defer wg.Done()
			dlqHandler.HandleMessage(msgCtx, msg, consumer, func(mCtx context.Context, m pulsar.Message) (dlq.ProcessResult, error) {
				return handler.HandleStageMessage(mCtx, stage, m)
			})
		}()
	}

	// Wait for in-flight goroutines with timeout
	log.Println("Waiting for in-flight tasks to complete...")
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		log.Println("All in-flight tasks completed")
	case <-time.After(cfg.ShutdownTimeout):
		log.Printf("Shutdown timeout (%s) reached, some tasks may not have completed", cfg.ShutdownTimeout)
	}

	log.Println("RAG Worker shutdown complete")
}
