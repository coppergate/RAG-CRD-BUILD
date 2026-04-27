package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"app-builds/common/dlq"
	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/tag"
	"app-builds/common/health"
	pulsarCommon "app-builds/common/pulsar"
	"app-builds/common/telemetry"
	"app-builds/db-adapter/internal/config"
	"app-builds/db-adapter/internal/service"
	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/google/uuid"
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
		log.Printf("Warning: failed to create query counter metric: %v", err)
	}
	errorCounter, err = meter.Int64Counter("db_errors_total")
	if err != nil {
		log.Printf("Warning: failed to create error counter metric: %v", err)
	}
	queryLatency, err = meter.Float64Histogram("db_query_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		log.Printf("Warning: failed to create query latency metric: %v", err)
	}
}

func main() {
	cfg := config.Load()
	healthSrv := health.NewServer()

	shutdown, err := telemetry.InitTracer("db-adapter")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	entClient, err := ent.Open("postgres", cfg.DBConnString)
	if err != nil {
		log.Fatalf("Failed to connect to DB: %v", err)
	}
	defer entClient.Close()

	pulsarClient, err := pulsarCommon.NewClient(pulsarCommon.Config{URL: cfg.PulsarURL})
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer pulsarClient.Close()

	dlqHandler, err := dlq.NewHandler(pulsarClient, "db-adapter")
	if err != nil {
		log.Fatalf("Could not create DLQ handler: %v", err)
	}
	defer dlqHandler.Close()

	qdrantProducer, err := pulsarClient.NewProducer(cfg.QdrantOpsTopic)
	if err != nil {
		log.Printf("Warning: Could not create qdrant ops producer: %v", err)
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

	// Setup Pulsar Consumers
	setupConsumers(ctx, pulsarClient, cfg, dlqHandler, processor)

	// Setup HTTP Routes
	mux := http.NewServeMux()
	healthSrv.RegisterRoutes(mux)

	// Logging Middleware
	loggingMux := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		log.Printf("Incoming request: %s %s from %s", r.Method, r.URL.Path, r.RemoteAddr)
		mux.ServeHTTP(w, r)
		log.Printf("Completed request: %s %s in %v", r.Method, r.URL.Path, time.Since(start))
	})

	mux.HandleFunc("/sessions/", func(w http.ResponseWriter, r *http.Request) {
		idStr := strings.TrimPrefix(r.URL.Path, "/sessions/")
		if strings.HasSuffix(idStr, "/messages") {
			sessSvc.GetMessages(w, r, strings.TrimSuffix(idStr, "/messages"))
			return
		}
		if strings.HasSuffix(idStr, "/health") {
			metricsSvc.GetHealth(w, r, strings.TrimSuffix(idStr, "/health"))
			return
		}
		if idStr == "" {
			sessSvc.ListSessions(w, r)
			return
		}
		http.Error(w, "Not found", http.StatusNotFound)
	})

	mux.HandleFunc("/sessions", sessSvc.ListSessions)

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
			tagID, err := uuid.Parse(idStr)
			if err != nil {
				http.Error(w, "Invalid tag ID", http.StatusBadRequest)
				return
			}
			if qdrantProducer != nil {
				op := &contracts.QdrantOp{
					Id:         uuid.New().String(),
					Action:     "delete",
					Collection: "vectors",
					Tags:       []string{idStr},
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

	otelHandler := otelhttp.NewHandler(loggingMux, "db-adapter")
	server := &http.Server{
		Addr:    ":8080",
		Handler: otelHandler,
	}

	go func() {
		if cfg.TLSCert != "" && cfg.TLSKey != "" {
			log.Printf("Starting DB Adapter REST API with TLS on :8080")
			if err := server.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey); err != nil && err != http.ErrServerClosed {
				log.Fatalf("REST server failed: %v", err)
			}
		} else {
			log.Printf("Starting DB Adapter REST API on :8080")
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Fatalf("REST server failed: %v", err)
			}
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Println("Shutting down DB Adapter...")
	cancel()
	time.Sleep(2 * time.Second)
	log.Println("DB Adapter shutdown complete")
}

func setupConsumers(ctx context.Context, client *pulsarCommon.Client, cfg *config.Config, dlqHandler *dlq.Handler, processor *service.PulsarProcessor) {
	// Prompts
	pc, err := client.NewSharedConsumer(cfg.PromptTopic, cfg.Subscription)
	if err == nil {
		go consumeLoop(ctx, pc, dlqHandler, processor.HandlePrompt)
	}

	// Responses
	rc, err := client.NewSharedConsumer(cfg.ResponseTopic, cfg.Subscription)
	if err == nil {
		go consumeLoop(ctx, rc, dlqHandler, processor.HandleResponse)
	}

	// Metrics
	cc, err := client.NewSharedConsumer(cfg.CompletionTopic, cfg.Subscription+"-metrics")
	if err == nil {
		go consumeLoop(ctx, cc, dlqHandler, processor.HandleCompletion)
	}

	// Ops
	oc, err := client.NewSharedConsumer(cfg.DBOpsTopic, cfg.Subscription+"-ops")
	if err == nil {
		go consumeLoop(ctx, oc, dlqHandler, processor.HandleDBOp)
	}
}

func consumeLoop(ctx context.Context, consumer pulsar.Consumer, dlqHandler *dlq.Handler, handler func(context.Context, pulsar.Message) (dlq.ProcessResult, error)) {
	defer consumer.Close()
	for {
		msg, err := consumer.Receive(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			log.Printf("Error receiving message: %v", err)
			continue
		}
		dlqHandler.HandleMessage(ctx, msg, consumer, handler)
	}
}
