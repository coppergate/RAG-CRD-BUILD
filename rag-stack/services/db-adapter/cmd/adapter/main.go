package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"app-builds/common/dlq"
	"app-builds/common/ent"
	"app-builds/common/ent/prompt"
	"app-builds/common/ent/session"
	"app-builds/common/health"
	"app-builds/common/telemetry"
	"app-builds/common/tlsutil"
	"app-builds/db-adapter/internal/config"
	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/google/uuid"
	_ "github.com/lib/pq"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	"strings"
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

	opts := pulsar.ClientOptions{
		URL: cfg.PulsarURL,
	}
	if certPath := tlsutil.PulsarTLSCertPath(cfg.PulsarURL); certPath != "" {
		opts.TLSTrustCertsFilePath = certPath
	}

	client, err := pulsar.NewClient(opts)
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer client.Close()

	// DLQ handler
	dlqHandler, err := dlq.NewHandler(client, "db-adapter")
	if err != nil {
		log.Fatalf("Could not create DLQ handler: %v", err)
	}
	defer dlqHandler.Close()

	// Consumer for Prompts
	promptConsumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.PromptTopic,
		SubscriptionName: cfg.Subscription,
		Type:             pulsar.Shared,
	})
	if err != nil {
		log.Fatalf("Could not subscribe to prompts: %v", err)
	}
	defer promptConsumer.Close()

	// Consumer for Responses
	responseConsumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.ResponseTopic,
		SubscriptionName: cfg.Subscription,
		Type:             pulsar.Shared,
	})
	if err != nil {
		log.Fatalf("Could not subscribe to responses: %v", err)
	}
	defer responseConsumer.Close()

	// Register readiness checks
	healthSrv.RegisterCheck("database", func() error {
		_, err := entClient.Session.Query().Limit(1).Count(context.Background())
		return err
	})

	log.Printf("DB Adapter started, listening on topics: %s, %s, %s", cfg.PromptTopic, cfg.ResponseTopic, cfg.DBOpsTopic)

	// Consumer for DB Ops (Delete)
	opsConsumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.DBOpsTopic,
		SubscriptionName: cfg.Subscription + "-ops",
		Type:             pulsar.Shared,
	})
	if err != nil {
		log.Printf("Warning: Could not subscribe to DB ops: %v", err)
	} else {
		defer opsConsumer.Close()
		go func() {
			for {
				msg, err := opsConsumer.Receive(ctx)
				if err != nil {
					if ctx.Err() != nil {
						return
					}
					log.Printf("Error receiving DB op: %v", err)
					continue
				}

				dlqHandler.HandleMessage(ctx, msg, opsConsumer, func(mCtx context.Context, m pulsar.Message) (dlq.ProcessResult, error) {
					return handleDBOp(mCtx, m, entClient)
				})
			}
		}()
	}

	// Handle Prompts
	go func() {
		for {
			msg, err := promptConsumer.Receive(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				log.Printf("Error receiving prompt: %v", err)
				continue
			}

			dlqHandler.HandleMessage(ctx, msg, promptConsumer, func(mCtx context.Context, m pulsar.Message) (dlq.ProcessResult, error) {
				return handlePrompt(mCtx, m, entClient)
			})
		}
	}()

	// Handle Responses
	go func() {
		for {
			msg, err := responseConsumer.Receive(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				log.Printf("Error receiving response: %v", err)
				continue
			}

			dlqHandler.HandleMessage(ctx, msg, responseConsumer, func(mCtx context.Context, m pulsar.Message) (dlq.ProcessResult, error) {
				return handleResponse(mCtx, m, entClient)
			})
		}
	}()

	mux := http.NewServeMux()
	healthSrv.RegisterRoutes(mux)

	mux.HandleFunc("/api/db/sessions", func(w http.ResponseWriter, r *http.Request) {
		sessions, err := entClient.Session.Query().All(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(sessions)
	})

	mux.HandleFunc("/api/db/stats", func(w http.ResponseWriter, r *http.Request) {
		sessionCount, _ := entClient.Session.Query().Count(r.Context())
		promptCount, _ := entClient.Prompt.Query().Count(r.Context())
		responseCount, _ := entClient.Response.Query().Count(r.Context())
		json.NewEncoder(w).Encode(map[string]int{
			"sessions":  sessionCount,
			"prompts":   promptCount,
			"responses": responseCount,
		})
	})

	otelHandler := otelhttp.NewHandler(mux, "db-adapter")

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

func handleDBOp(ctx context.Context, msg pulsar.Message, entClient *ent.Client) (dlq.ProcessResult, error) {
	start := time.Now()
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	msgCtx, span := tracer.Start(msgCtx, "HandleDBOp")
	defer span.End()

	attrs := []attribute.KeyValue{attribute.String("op", "delete_session")}
	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		queryLatency.Record(msgCtx, duration, metric.WithAttributes(attrs...))
	}()
	queryCounter.Add(msgCtx, 1, metric.WithAttributes(attrs...))

	var payload struct {
		Op string `json:"op"`
		ID string `json:"id"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal DB op payload: %w", err)
	}

	if payload.Op == "delete_session" {
		sessID, parseErr := uuid.Parse(payload.ID)
		if parseErr != nil {
			errorCounter.Add(msgCtx, 1, metric.WithAttributes(attrs...))
			return dlq.PermanentFailure, fmt.Errorf("invalid UUID in delete_session: %q: %w", payload.ID, parseErr)
		}
		_, err := entClient.Session.Delete().
			Where(session.ID(sessID)).
			Exec(ctx)
		if err != nil {
			errorCounter.Add(msgCtx, 1, metric.WithAttributes(attrs...))
			return dlq.TransientFailure, fmt.Errorf("delete session %s: %w", payload.ID, err)
		}
		log.Printf("Deleted session %s via Pulsar op", payload.ID)
	}

	return dlq.Success, nil
}

func handlePrompt(ctx context.Context, msg pulsar.Message, entClient *ent.Client) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	_, span := tracer.Start(msgCtx, "HandlePrompt")
	defer span.End()

	var payload struct {
		ID        string `json:"id"`
		SessionID string `json:"session_id"`
		Content   string `json:"content"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal prompt payload: %w", err)
	}

	promptID, parseErr := uuid.Parse(payload.ID)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid prompt UUID: %q: %w", payload.ID, parseErr)
	}
	sessID, parseErr := uuid.Parse(payload.SessionID)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid session UUID: %q: %w", payload.SessionID, parseErr)
	}

	_, err := entClient.Prompt.Create().
		SetPromptID(promptID).
		SetSessionID(sessID).
		SetContent(payload.Content).
		Save(ctx)
	if err != nil {
		log.Printf("Failed to insert prompt %s for session %s: %v", payload.ID, payload.SessionID, err)
		return dlq.TransientFailure, fmt.Errorf("insert prompt: %w", err)
	}

	log.Printf("Inserted prompt %s for session %s", payload.ID, payload.SessionID)
	return dlq.Success, nil
}

func handleResponse(ctx context.Context, msg pulsar.Message, entClient *ent.Client) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	_, span := tracer.Start(msgCtx, "HandleResponse")
	defer span.End()

	var payload struct {
		ID             string `json:"id"`
		SessionID      string `json:"session_id"`
		Result         string `json:"result"`
		SequenceNumber int    `json:"sequence_number"`
		Model          string `json:"model"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal response payload: %w", err)
	}

	log.Printf("Processing response: ID=%s, SessionID=%s, Model=%s", payload.ID, payload.SessionID, payload.Model)

	promptUUID, parseErr := uuid.Parse(payload.ID)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid prompt UUID in response: %q: %w", payload.ID, parseErr)
	}

	p, err := entClient.Prompt.Query().
		Where(prompt.PromptID(promptUUID)).
		Order(ent.Desc(prompt.FieldCreatedAt)).
		First(ctx)
	if err != nil {
		return dlq.TransientFailure, fmt.Errorf("find prompt for response (ID %s): %w", payload.ID, err)
	}

	var sessID uuid.UUID
	if payload.SessionID != "" {
		sessID, parseErr = uuid.Parse(payload.SessionID)
		if parseErr != nil {
			log.Printf("Invalid session UUID in response: %q, falling back to prompt session: %v", payload.SessionID, parseErr)
			sessID = p.SessionID
		}
	} else {
		sessID = p.SessionID
	}

	var modelName *string
	if payload.Model != "" {
		modelName = &payload.Model
	}

	_, err = entClient.Response.Create().
		SetPromptID(p.ID).
		SetSessionID(sessID).
		SetContent(payload.Result).
		SetSequenceNumber(payload.SequenceNumber).
		SetNillableModelName(modelName).
		Save(ctx)
	if err != nil {
		return dlq.TransientFailure, fmt.Errorf("insert response for prompt %s: %w", payload.ID, err)
	}

	log.Printf("Inserted response for prompt %s (seq %d)", payload.ID, payload.SequenceNumber)
	return dlq.Success, nil
}

