package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"app-builds/common/dlq"
	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/tag"
	"app-builds/common/health"
	"app-builds/common/logging"
	pulsarCommon "app-builds/common/pulsar"
	"app-builds/common/telemetry"
	"app-builds/db-adapter/internal/config"
	"app-builds/db-adapter/internal/service"
	"github.com/apache/pulsar-client-go/pulsar"
	"google.golang.org/protobuf/encoding/protojson"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/metric"
	_ "github.com/lib/pq"
)

var (
	meter        = telemetry.Meter("db-adapter")
	queryCounter metric.Int64Counter
	errorCounter metric.Int64Counter
	queryLatency metric.Float64Histogram
)

func init() {
	var err error
	queryCounter, err = meter.Int64Counter("db_queries_total")
	if err != nil {
		logging.Warn("failed to create query counter metric", "error", err)
	}
	errorCounter, err = meter.Int64Counter("db_errors_total")
	if err != nil {
		logging.Warn("failed to create error counter metric", "error", err)
	}
	queryLatency, err = meter.Float64Histogram("db_query_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		logging.Warn("failed to create query latency metric", "error", err)
	}
}

func main() {
	cfg := config.Load()
	healthSrv := health.NewServer()

	shutdown, err := telemetry.InitTracer("db-adapter")
	if err != nil {
		logging.Warn("failed to initialize tracer", "error", err)
	} else {
		defer shutdown(context.Background())
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	entClient, err := ent.Open("postgres", cfg.DBConnString)
	if err != nil {
		logging.Error("failed to connect to DB", "error", err)
		os.Exit(1)
	}
	defer entClient.Close()

	// Run migrations
	if err := entClient.Schema.Create(ctx); err != nil {
		logging.Warn("failed to create schema", "error", err)
	}

	pulsarClient, err := pulsarCommon.NewClient(pulsarCommon.Config{URL: cfg.PulsarURL})
	if err != nil {
		logging.Error("could not instantiate Pulsar client", "error", err)
		os.Exit(1)
	}
	defer pulsarClient.Close()

	dlqHandler, err := dlq.NewHandler(pulsarClient, "db-adapter")
	if err != nil {
		logging.Error("could not create DLQ handler", "error", err)
		os.Exit(1)
	}
	defer dlqHandler.Close()

	qdrantProducer, err := pulsarClient.NewProducer(cfg.QdrantOpsTopic)
	if err != nil {
		logging.Warn("could not create qdrant ops producer", "error", err)
	} else {
		defer qdrantProducer.Close()
	}

	// Initialize Services
	sessSvc := service.NewSessionService(entClient)
	metricsSvc := service.NewMetricsService(entClient)
	storageSvc := service.NewStorageService(entClient)
	maintSvc := service.NewMaintenanceService(entClient, qdrantProducer, cfg.IngestionURL)
	processor := service.NewPulsarProcessor(entClient, queryCounter, errorCounter, queryLatency)

	// Register readiness checks
	healthSrv.RegisterCheck("database", func() error {
		_, err := entClient.Session.Query().Limit(1).Count(context.Background())
		return err
	})
	healthSrv.RegisterCheck("pulsar", pulsarClient.Ping)

	// Setup Pulsar Consumers
	if err := setupConsumers(ctx, pulsarClient, cfg, dlqHandler, processor); err != nil {
		logging.Error("fatal: could not setup pulsar consumers", "error", err)
		os.Exit(1)
	}

	// Setup HTTP Routes
	mux := http.NewServeMux()
	healthSrv.RegisterRoutes(mux)

	// Logging Middleware
	loggingMux := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		logging.L.WithTrace(r.Context()).Info("incoming request", "method", r.Method, "path", r.URL.Path, "remote", r.RemoteAddr)
		mux.ServeHTTP(w, r)
		logging.L.WithTrace(r.Context()).Info("completed request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
	})

	mux.HandleFunc("/sessions/", func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, "/sessions/")
		if path == "" || path == "/" {
			sessSvc.ListSessions(w, r)
			return
		}

		// Handle sub-resources
		if strings.HasSuffix(path, "/messages") {
			sessSvc.GetMessages(w, r, strings.TrimSuffix(path, "/messages"))
			return
		}
		if strings.HasSuffix(path, "/health") {
			metricsSvc.GetHealth(w, r, strings.TrimSuffix(path, "/health"))
			return
		}

		// Handle specific session by ID
		if r.Method == http.MethodDelete {
			sessSvc.DeleteSession(w, r, path)
			return
		}
		
		http.Error(w, "Not found", http.StatusNotFound)
	})

	mux.HandleFunc("/sessions", sessSvc.ListSessions)
	mux.HandleFunc("/sessions/tags", sessSvc.UpdateSessionTags)

	mux.HandleFunc("/metrics/sessions/health", func(w http.ResponseWriter, r *http.Request) {
		sessionIDStr := r.URL.Query().Get("session_id")
		metricsSvc.GetHealth(w, r, sessionIDStr)
	})

	mux.HandleFunc("/audit/retrieval", func(w http.ResponseWriter, r *http.Request) {
		sessionIDStr := r.URL.Query().Get("session_id")
		metricsSvc.GetAudit(w, r, sessionIDStr)
	})

	mux.HandleFunc("/audit/sessions/", func(w http.ResponseWriter, r *http.Request) {
		sessionIDStr := strings.TrimPrefix(r.URL.Path, "/audit/sessions/")
		metricsSvc.GetAudit(w, r, sessionIDStr)
	})

	mux.HandleFunc("/metrics/models", metricsSvc.GetMetricsSummary)

	mux.HandleFunc("/tags", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			tags, err := entClient.Tag.Query().Order(ent.Asc(tag.FieldName)).All(r.Context())
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			if tags == nil {
				tags = []*ent.Tag{}
			}
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(tags)
		case http.MethodPost:
			var payload struct {
				Name string `json:"name"`
			}
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			t, err := entClient.Tag.Create().SetName(payload.Name).Save(r.Context())
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(t)
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})

	mux.HandleFunc("/tags/", func(w http.ResponseWriter, r *http.Request) {
		idStr := strings.TrimPrefix(r.URL.Path, "/tags/")
		if r.Method == http.MethodDelete && idStr != "" {
			tagID, err := strconv.ParseInt(idStr, 10, 64)
			if err != nil {
				http.Error(w, "Invalid tag ID", http.StatusBadRequest)
				return
			}
			if qdrantProducer != nil {
				op := &contracts.QdrantOp{
					Action:     "delete",
					Collection: "vectors",
					Tags:       []int64{tagID},
				}
				p, _ := protojson.Marshal(op)
				qdrantProducer.Send(r.Context(), &pulsar.ProducerMessage{Payload: p})
			}
			err = entClient.Tag.DeleteOneID(tagID).Exec(r.Context())
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}
		http.Error(w, "Not found or method not allowed", http.StatusNotFound)
	})

	mux.HandleFunc("/maintenance/tags/merge", maintSvc.MergeTags)
	mux.HandleFunc("/stats", metricsSvc.GetStats)
	mux.HandleFunc("/metrics/summary", metricsSvc.GetMetricsSummary)
	mux.HandleFunc("/storage/files", storageSvc.GetFiles)
	mux.HandleFunc("/storage/vectors", storageSvc.GetFileVectors)

	otelHandler := otelhttp.NewHandler(loggingMux, "db-adapter")
	server := &http.Server{
		Addr:    ":8080",
		Handler: otelHandler,
	}

	go func() {
		if cfg.TLSCert != "" && cfg.TLSKey != "" {
			logging.Info("starting DB Adapter REST API with TLS", "addr", ":8080")
			if err := server.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey); err != nil && err != http.ErrServerClosed {
				logging.Error("REST server failed", "error", err)
				os.Exit(1)
			}
		} else {
			logging.Info("starting DB Adapter REST API", "addr", ":8080")
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				logging.Error("REST server failed", "error", err)
				os.Exit(1)
			}
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	logging.Info("shutting down DB Adapter")
	cancel()
	time.Sleep(2 * time.Second)
	logging.Info("DB Adapter shutdown complete")
}

func setupConsumers(ctx context.Context, client *pulsarCommon.Client, cfg *config.Config, dlqHandler *dlq.Handler, processor *service.PulsarProcessor) error {
	consumers := []struct {
		topic        string
		subscription string
		handler      func(context.Context, pulsar.Message) (dlq.ProcessResult, error)
	}{
		{cfg.PromptTopic, cfg.Subscription, processor.HandlePrompt},
		{cfg.ResponseTopic, cfg.Subscription, processor.HandleResponse},
		{cfg.CompletionTopic, cfg.Subscription + "-metrics", processor.HandleCompletion},
		{cfg.DBOpsTopic, cfg.Subscription + "-ops", processor.HandleDBOp},
	}

	for _, c := range consumers {
		consumer, err := client.NewSharedConsumer(c.topic, c.subscription)
		if err != nil {
			return fmt.Errorf("failed to create consumer for topic %s: %w", c.topic, err)
		}
		go consumeLoop(ctx, consumer, dlqHandler, c.handler)
	}
	return nil
}

func consumeLoop(ctx context.Context, consumer pulsar.Consumer, dlqHandler *dlq.Handler, handler func(context.Context, pulsar.Message) (dlq.ProcessResult, error)) {
	defer consumer.Close()
	for {
		msg, err := consumer.Receive(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			logging.Error("error receiving message", "error", err)
			continue
		}
		dlqHandler.HandleMessage(ctx, msg, consumer, handler)
	}
}
