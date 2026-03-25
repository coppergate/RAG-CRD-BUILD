package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"app-builds/db-adapter/internal/config"
	"app-builds/common/ent"
	"app-builds/common/ent/prompt"
	"app-builds/common/ent/session"
	"app-builds/common/telemetry"
	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/google/uuid"
	_ "github.com/lib/pq"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
)

var (
	meter          = telemetry.Meter("db-adapter")
	queryCounter, _ = meter.Int64Counter("db_queries_total")
	errorCounter, _ = meter.Int64Counter("db_errors_total")
	queryLatency, _ = meter.Float64Histogram("db_query_duration_ms", metric.WithUnit("ms"))
)

func main() {
	cfg := config.Load()
	startHealthServer(":8080")

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

	client, err := pulsar.NewClient(pulsar.ClientOptions{
		URL: cfg.PulsarURL,
	})
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer client.Close()

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

				start := time.Now()
				// Extract tracing context from Pulsar message properties
				msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
				tracer := otel.Tracer("db-adapter")
				msgCtx, span := tracer.Start(msgCtx, "HandleDBOp")

				attrs := []attribute.KeyValue{attribute.String("op", "delete_session")}
				defer func() {
					duration := float64(time.Since(start).Milliseconds())
					queryLatency.Record(msgCtx, duration, metric.WithAttributes(attrs...))
				}()
				queryCounter.Add(msgCtx, 1, metric.WithAttributes(attrs...))

				var payload struct {
					Op string `json:"op"` // "delete_session"
					ID string `json:"id"` // session_id
				}
				if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
					log.Printf("Error unmarshaling DB op payload: %v. Raw: %s", err, string(msg.Payload()))
				} else {
					if payload.Op == "delete_session" {
						_, err := entClient.Session.Delete().
							Where(session.ID(uuid.MustParse(payload.ID))).
							Exec(ctx)
						if err != nil {
							log.Printf("Failed to delete session %s: %v", payload.ID, err)
						} else {
							log.Printf("Deleted session %s via Pulsar op", payload.ID)
						}
					}
				}
				span.End()
				opsConsumer.Ack(msg)
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

			// Extract tracing context from Pulsar message properties
			msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
			tracer := otel.Tracer("db-adapter")
			_, span := tracer.Start(msgCtx, "HandlePrompt")

			var payload struct {
				ID        string `json:"id"`
				SessionID string `json:"session_id"`
				Content   string `json:"content"`
			}
			if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
				log.Printf("Error unmarshaling prompt payload: %v. Raw: %s", err, string(msg.Payload()))
			} else {
				_, err := entClient.Prompt.Create().
					SetPromptID(uuid.MustParse(payload.ID)).
					SetSessionID(uuid.MustParse(payload.SessionID)).
					SetContent(payload.Content).
					Save(ctx)
				if err != nil {
					log.Printf("Failed to insert prompt %s for session %s: %v", payload.ID, payload.SessionID, err)
				} else {
					log.Printf("Inserted prompt %s for session %s", payload.ID, payload.SessionID)
				}
			}
			span.End()
			promptConsumer.Ack(msg)
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

			// Extract tracing context from Pulsar message properties
			msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
			tracer := otel.Tracer("db-adapter")
			_, span := tracer.Start(msgCtx, "HandleResponse")

			var payload struct {
				ID             string `json:"id"` // This is the prompt_id (UUID)
				SessionID      string `json:"session_id"`
				Result         string `json:"result"`
				SequenceNumber int    `json:"sequence_number"`
				Model          string `json:"model"`
			}
			if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
				log.Printf("Error unmarshaling response payload: %v. Raw: %s", err, string(msg.Payload()))
			} else {
				log.Printf("Processing response: ID=%s, SessionID=%s, Model=%s", payload.ID, payload.SessionID, payload.Model)

				p, err := entClient.Prompt.Query().
					Where(prompt.PromptID(uuid.MustParse(payload.ID))).
					Order(ent.Desc(prompt.FieldCreatedAt)).
					First(ctx)
				if err != nil {
					log.Printf("Failed to find prompt for response (ID %s): %v", payload.ID, err)
				} else {
					var sessID uuid.UUID
					if payload.SessionID != "" {
						sessID = uuid.MustParse(payload.SessionID)
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
						log.Printf("Failed to insert response for prompt %s (session %v): %v", payload.ID, sessID, err)
					} else {
						log.Printf("Inserted response for prompt %s (seq %d)", payload.ID, payload.SequenceNumber)
					}
				}
			}
			span.End()
			responseConsumer.Ack(msg)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Println("Shutting down DB Adapter...")
}

func startHealthServer(addr string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK"))
	})

	go func() {
		if err := http.ListenAndServe(addr, mux); err != nil {
			log.Printf("Health server stopped: %v", err)
		}
	}()
}
