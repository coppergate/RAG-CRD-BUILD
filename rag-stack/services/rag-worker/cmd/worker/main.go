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

	healthSrv := health.NewServer()
	healthSrv.Start(":8080")

	shutdownTracer := initTracer()
	if shutdownTracer != nil {
		defer shutdownTracer(context.Background())
	}

	msgClient := initMessaging(cfg)
	defer msgClient.Close()

	registry := initModelRegistry(cfg)

	dlqHandler := initDLQHandler(msgClient)
	defer dlqHandler.Close()

	searcher := initQdrantSearcher(cfg, msgClient)

	consumer := subscribeToStageTopics(cfg, msgClient)
	defer consumer.Close()

	healthSrv.RegisterCheck("pulsar", func() error {
		return msgClient.Ping()
	})

	healthSrv.RegisterCheck("ollama-planner", func() error {
		client, err := registry.GetClient(cfg.PlannerModel)
		if err != nil {
			return err
		}
		// If it's an OllamaClient, we can ping it
		if oc, ok := client.(*ollama.OllamaClient); ok {
			return oc.Ping()
		}
		return nil
	})

	healthSrv.RegisterCheck("ollama-executor", func() error {
		client, err := registry.GetClient(cfg.ExecutorModel)
		if err != nil {
			return err
		}
		if oc, ok := client.(*ollama.OllamaClient); ok {
			return oc.Ping()
		}
		return nil
	})

	handler := pipeline.NewHandler(cfg, msgClient, registry, searcher)

	log.Printf("RAG Worker started, listening on multiple stages")

	runMessageLoop(cfg, consumer, handler, dlqHandler)

	log.Println("RAG Worker shutdown complete")
}

// initTracer initializes the OpenTelemetry tracer and returns its shutdown
// function. Returns nil when initialization fails.
func initTracer() func(context.Context) error {
	shutdown, err := telemetry.InitTracer("rag-worker")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
		return nil
	}
	return shutdown
}

// initMessaging creates the Pulsar messaging client with all producers.
func initMessaging(cfg *config.Config) *messaging.Client {
	msgClient, err := messaging.NewClient(cfg)
	if err != nil {
		log.Fatalf("Could not initialize messaging: %v", err)
	}
	return msgClient
}

// initModelRegistry configures the model registry with available backends,
// prompt types, and the planner/executor model specifications from config.
func initModelRegistry(cfg *config.Config) *models.ModelRegistry {
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

	return registry
}

// initDLQHandler creates the dead-letter-queue handler for poison message routing.
func initDLQHandler(msgClient *messaging.Client) *dlq.Handler {
	dlqHandler, err := dlq.NewHandler(msgClient.PulsarClient(), "rag-worker")
	if err != nil {
		log.Fatalf("Could not create DLQ handler: %v", err)
	}
	return dlqHandler
}

// initQdrantSearcher creates the Qdrant searcher and starts its result consumer.
func initQdrantSearcher(cfg *config.Config, msgClient *messaging.Client) *search.QdrantSearcher {
	searcher := search.NewQdrantSearcher(cfg, msgClient.Producers.QdrantOps)

	qResultsSub := fmt.Sprintf("rag-worker-q-res-%s", os.Getenv("HOSTNAME"))
	qResConsumer, err := msgClient.PulsarClient().Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.QdrantResultsTopic,
		SubscriptionName: qResultsSub,
		Type:             pulsar.Exclusive,
	})
	if err != nil {
		log.Fatalf("Could not subscribe to Qdrant results: %v", err)
	}
	searcher.StartResultConsumer(qResConsumer)

	return searcher
}

// subscribeToStageTopics creates a shared consumer for the RAG pipeline stage topics.
func subscribeToStageTopics(cfg *config.Config, msgClient *messaging.Client) pulsar.Consumer {
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
	return consumer
}

// classifyStage determines the pipeline stage from the Pulsar topic name.
func classifyStage(topic string) string {
	switch {
	case strings.HasSuffix(topic, "ingress"):
		return "ingress"
	case strings.HasSuffix(topic, "plan"):
		return "plan"
	case strings.HasSuffix(topic, "exec"):
		return "exec"
	default:
		return ""
	}
}

// runMessageLoop handles the main receive-dispatch-shutdown cycle.
func runMessageLoop(cfg *config.Config, consumer pulsar.Consumer, handler *pipeline.Handler, dlqHandler *dlq.Handler) {
	ctx, cancel := context.WithCancel(context.Background())
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	var wg sync.WaitGroup
	go func() {
		<-stop
		log.Println("Shutdown signal received, stopping message consumption...")
		cancel()
	}()

	for {
		msg, err := consumer.Receive(ctx)
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			log.Printf("Error receiving message: %v", err)
			continue
		}

		stage := classifyStage(msg.Topic())
		msgCtx := otel.GetTextMapPropagator().Extract(
			context.Background(),
			propagation.MapCarrier(msg.Properties()),
		)

		wg.Add(1)
		go func() {
			defer wg.Done()
			dlqHandler.HandleMessage(msgCtx, msg, consumer, func(mCtx context.Context, m pulsar.Message) (dlq.ProcessResult, error) {
				return handler.HandleStageMessage(mCtx, stage, m)
			})
		}()
	}

	awaitInFlight(&wg, cfg.ShutdownTimeout)
}

// awaitInFlight waits for all in-flight goroutines to finish, with a timeout.
func awaitInFlight(wg *sync.WaitGroup, timeout time.Duration) {
	log.Println("Waiting for in-flight tasks to complete...")
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		log.Println("All in-flight tasks completed")
	case <-time.After(timeout):
		log.Printf("Shutdown timeout (%s) reached, some tasks may not have completed", timeout)
	}
}
