package main

import (
	"context"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"app-builds/common/ent"
	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"

	"app-builds/common/clients"
	"app-builds/common/dlq"
	"app-builds/common/health"
	"app-builds/common/logging"
	"app-builds/common/telemetry"
	"app-builds/rag-worker/internal/config"
	"app-builds/rag-worker/internal/models"
	"app-builds/rag-worker/internal/models/granite31"
	"app-builds/rag-worker/internal/models/llama3"
	"app-builds/rag-worker/internal/ollama"
	"app-builds/rag-worker/pkg/memory"
	"app-builds/rag-worker/pkg/messaging"
	"app-builds/rag-worker/pkg/pipeline"
	"app-builds/rag-worker/pkg/search"
)

// main is the entry point for the rag-worker service.
func main() {
	cfg := config.LoadConfig()

	healthSrv := health.NewServer()
	if cfg.TLSCert != "" && cfg.TLSKey != "" {
		healthSrv.StartTLS(":8080", cfg.TLSCert, cfg.TLSKey)
	} else {
		healthSrv.Start(":8080")
	}

	shutdownTracer := initTracer()
	if shutdownTracer != nil {
		defer shutdownTracer(context.Background())
	}

	msgClient := initMessaging(cfg)
	defer msgClient.Close()

	registry := initModelRegistry(cfg)
	tagSource, closeTagSource := initSessionTagSource(cfg)
	if closeTagSource != nil {
		defer closeTagSource()
	}

	dlqHandler := initDLQHandler(msgClient)
	defer dlqHandler.Close()

	searcher := initQdrantSearcher(cfg)

	memoryClient := memory.NewMemoryClient(cfg.MemoryControllerURL)

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

	handler := pipeline.NewHandler(cfg, msgClient, registry, searcher, memoryClient, tagSource)

	logging.Info("RAG Worker started", "stages", "multiple")

	runMessageLoop(cfg, consumer, handler, dlqHandler)

	logging.Info("RAG Worker shutdown complete")
}

// initTracer initializes the OpenTelemetry tracer and returns its shutdown
// function. Returns nil when initialization fails.
func initTracer() func(context.Context) error {
	shutdown, err := telemetry.InitTracer("rag-worker")
	if err != nil {
		logging.Warn("failed to initialize tracer", "error", err)
		return nil
	}
	return shutdown
}

// initMessaging creates the Pulsar messaging client with all producers.
func initMessaging(cfg *config.Config) *messaging.Client {
	msgClient, err := messaging.NewClient(cfg)
	if err != nil {
		logging.Fatalf("Could not initialize messaging: %v", err)
	}
	return msgClient
}

// initModelRegistry configures the model registry with available backends,
// prompt types, and the planner/executor model specifications from config.
func initModelRegistry(cfg *config.Config) *models.ModelRegistry {
	registry := models.NewModelRegistry()
	registry.RegisterBackend("ollama", func(endpoint, modelName string) models.ChatClient {
		return ollama.NewClient(endpoint, modelName, cfg.OllamaMaxConcurrency)
	})

	plannerShape := loadModelShape(cfg.ModelDefaultsConfigPath, cfg.PlannerModelConfigPath, cfg.PlannerPromptType)
	executorShape := loadModelShape(cfg.ModelDefaultsConfigPath, cfg.ExecutorModelConfigPath, cfg.ExecutorPromptType)

	registry.RegisterPromptType("llama3",
		func(c models.ChatClient) models.Planner  { return models.NewPlannerWithConfig(c, plannerShape) },
		func(c models.ChatClient) models.Executor { return models.NewExecutorWithConfig(c, plannerShape) },
	)
	registry.RegisterPromptType("granite31",
		func(c models.ChatClient) models.Planner  { return models.NewPlannerWithConfig(c, executorShape) },
		func(c models.ChatClient) models.Executor { return models.NewExecutorWithConfig(c, executorShape) },
	)

	registry.RegisterModel(models.ModelSpec{
		Id:         cfg.PlannerModel,
		Name:       cfg.PlannerModel,
		Endpoint:   cfg.PlannerURL,
		Backend:    "ollama",
		PromptType: cfg.PlannerPromptType,
	})
	registry.RegisterModel(models.ModelSpec{
		Id:         cfg.ExecutorModel,
		Name:       cfg.ExecutorModel,
		Endpoint:   cfg.ExecutorURL,
		Backend:    "ollama",
		PromptType: cfg.ExecutorPromptType,
	})
	// Dedicated CPU embedding model — only GetEmbeddings() is called on this entry.
	// PromptType reuses PlannerPromptType so the registry can construct the wrapper;
	// Plan() and Execute() are never invoked on this model.
	if cfg.EmbeddingModel != "" && cfg.EmbeddingModel != cfg.PlannerModel && cfg.EmbeddingModel != cfg.ExecutorModel {
		registry.RegisterModel(models.ModelSpec{
			Id:         cfg.EmbeddingModel,
			Name:       cfg.EmbeddingModel,
			Endpoint:   cfg.EmbeddingURL,
			Backend:    "ollama",
			PromptType: cfg.PlannerPromptType,
		})
	}

	// Alternate CPU planner — same llama3 PromptType as the GPU planner, different endpoint.
	// Selectable per request via the planner_model field in the Pulsar payload.
	if cfg.AltPlannerModel != "" && cfg.AltPlannerModel != cfg.PlannerModel && cfg.AltPlannerModel != cfg.ExecutorModel {
		registry.RegisterModel(models.ModelSpec{
			Id:         cfg.AltPlannerModel,
			Name:       cfg.AltPlannerModel,
			Endpoint:   cfg.AltPlannerURL,
			Backend:    "ollama",
			PromptType: cfg.PlannerPromptType,
		})
	}

	return registry
}

// loadModelShape loads a ModelConfig from the given YAML paths, falling back
// to the compiled-in config for the named prompt type when no paths are set.
func loadModelShape(defaultsPath, overridePath, promptType string) models.ModelConfig {
	if defaultsPath != "" || overridePath != "" {
		shape, err := models.LoadModelConfig(defaultsPath, overridePath)
		if err != nil {
			logging.Fatalf("failed to load model shape config (type=%s): %v", promptType, err)
		}
		logging.Info("loaded model shape from config files", "prompt_type", promptType,
			"defaults", defaultsPath, "override", overridePath)
		return shape
	}
	// No config paths set — use compiled-in defaults for backward compatibility.
	switch promptType {
	case "granite31":
		return granite31.Config
	case "llama3":
		return llama3.Config
	default:
		logging.Fatalf("unknown prompt type %q and no model config paths configured", promptType)
		return models.ModelConfig{}
	}
}

// initDLQHandler creates the dead-letter-queue handler for poison message routing.
func initDLQHandler(msgClient *messaging.Client) *dlq.Handler {
	dlqHandler, err := dlq.NewHandler(msgClient.PulsarClient(), "rag-worker")
	if err != nil {
		logging.Error("could not create DLQ handler", "error", err)
		os.Exit(1)
	}
	return dlqHandler
}

// initQdrantSearcher creates the Qdrant searcher using HTTP.
func initQdrantSearcher(cfg *config.Config) *search.QdrantSearcher {
	client := clients.NewQdrantHTTPClient(cfg.QdrantAdapterURL)
	return search.NewQdrantSearcher(cfg, client)
}

func initSessionTagSource(cfg *config.Config) (pipeline.TagSource, func()) {
	if strings.TrimSpace(cfg.DBConnString) == "" {
		logging.Warn("DB_CONN_STRING not set; using request tags for retrieval fallback")
		return nil, nil
	}

	client, err := ent.Open("postgres", cfg.DBConnString)
	if err != nil {
		logging.Warn("failed to open DB connection for session tag resolution", "error", err)
		return nil, nil
	}

	return pipeline.NewSessionTagSource(client), func() {
		_ = client.Close()
	}
}

// subscribeToStageTopics creates a shared consumer for the RAG pipeline stage topics.
func subscribeToStageTopics(cfg *config.Config, msgClient *messaging.Client) pulsar.Consumer {
	consumer, err := msgClient.PulsarClient().Subscribe(pulsar.ConsumerOptions{
		Topics: []string{
			cfg.PulsarIngressTopic,
			cfg.PulsarPlanTopic,
			cfg.PulsarSearchTopic,
			cfg.PulsarExecTopic,
		},
		SubscriptionName: cfg.PulsarSubscription,
		Type:             pulsar.Shared,
	})
	if err != nil {
		logging.Error("could not create Pulsar consumer", "error", err)
		os.Exit(1)
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
	case strings.HasSuffix(topic, "search"):
		return "search"
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
		logging.Info("shutdown signal received, stopping message consumption")
		cancel()
	}()

	for {
		msg, err := consumer.Receive(ctx)
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			logging.Error("error receiving message", "error", err)
			continue
		}

		stage := classifyStage(msg.Topic())
		msgCtx := otel.GetTextMapPropagator().Extract(
			context.Background(),
			propagation.MapCarrier(msg.Properties()),
		)
		telemetry.RecordMessage(msgCtx, "rag-worker")

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
	logging.Info("waiting for in-flight tasks to complete")
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		logging.Info("all in-flight tasks completed")
	case <-time.After(timeout):
		logging.Warn("shutdown timeout reached", "timeout", timeout)
	}
}
