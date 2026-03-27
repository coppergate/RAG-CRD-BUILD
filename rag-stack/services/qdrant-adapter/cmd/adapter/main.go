package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"

	"app-builds/common/dlq"
	"app-builds/common/health"
	"app-builds/common/telemetry"
	"app-builds/common/tlsutil"
	"app-builds/qdrant-adapter/internal/config"
	"app-builds/qdrant-adapter/internal/qdrant"
	"encoding/json"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	"net/http"
	"strings"
)

var (
	meter        = telemetry.Meter("qdrant-adapter")
	opCounter    metric.Int64Counter
	errorCounter metric.Int64Counter
	opLatency    metric.Float64Histogram
)

func init() {
	var err error
	opCounter, err = meter.Int64Counter("qdrant_ops_total")
	if err != nil {
		log.Printf("Warning: failed to create op counter metric: %v", err)
	}
	errorCounter, err = meter.Int64Counter("qdrant_errors_total")
	if err != nil {
		log.Printf("Warning: failed to create error counter metric: %v", err)
	}
	opLatency, err = meter.Float64Histogram("qdrant_op_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		log.Printf("Warning: failed to create op latency metric: %v", err)
	}
}

const shutdownTimeout = 30 * time.Second

type Adapter struct {
	cfg        *config.Config
	client     pulsar.Client
	prod       pulsar.Producer
	qdrant     *qdrant.QdrantClient
	wg         sync.WaitGroup
	dlqHandler *dlq.Handler
}

func main() {
	cfg := config.LoadConfig()
	healthSrv := health.NewServer()

	shutdown, err := telemetry.InitTracer("qdrant-adapter")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	opts := pulsar.ClientOptions{
		URL: cfg.PulsarURL,
	}
	if certPath := tlsutil.PulsarTLSCertPath(cfg.PulsarURL); certPath != "" {
		opts.TLSTrustCertsFilePath = certPath
	}

	client, err := pulsar.NewClient(opts)
	if err != nil {
		log.Fatalf("could not create pulsar client: %v", err)
	}
	defer client.Close()

	producer, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.QdrantResultsTopic})
	if err != nil {
		log.Fatalf("could not create results producer: %v", err)
	}
	defer producer.Close()

	dlqHandler, err := dlq.NewHandler(client, "qdrant-adapter")
	if err != nil {
		log.Fatalf("Could not create DLQ handler: %v", err)
	}
	defer dlqHandler.Close()

	adapter := &Adapter{
		cfg:        cfg,
		client:     client,
		prod:       producer,
		qdrant:     qdrant.NewClient(cfg),
		dlqHandler: dlqHandler,
	}

	// subscribe to qdrant ops
	consumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.QdrantOpsTopic,
		SubscriptionName: "qdrant-adapter-sub",
		Type:             pulsar.Shared,
	})
	if err != nil {
		log.Fatalf("could not subscribe to qdrant ops: %v", err)
	}
	defer consumer.Close()

	mux := http.NewServeMux()
	healthSrv.RegisterRoutes(mux)

	mux.HandleFunc("/api/qdrant/collections", func(w http.ResponseWriter, r *http.Request) {
		res, err := adapter.qdrant.ListCollections()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(res)
	})

	mux.HandleFunc("/api/qdrant/collections/", func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, "/api/qdrant/collections/")
		res, err := adapter.qdrant.GetCollection(name)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(res)
	})

	// Register readiness checks
	healthSrv.RegisterCheck("qdrant", func() error {
		_, err := adapter.qdrant.ListCollections()
		return err
	})

	otelHandler := otelhttp.NewHandler(mux, "qdrant-adapter")

	server := &http.Server{
		Addr:    ":8080",
		Handler: otelHandler,
	}

	go func() {
		if cfg.TLSCert != "" && cfg.TLSKey != "" {
			log.Printf("Starting Qdrant Adapter REST API with TLS on :8080")
			if err := server.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey); err != nil && err != http.ErrServerClosed {
				log.Fatalf("REST server failed: %v", err)
			}
		} else {
			log.Printf("Starting Qdrant Adapter REST API on :8080")
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Fatalf("REST server failed: %v", err)
			}
		}
	}()

	log.Printf("Qdrant Adapter started. Listening on %s, publishing to %s", cfg.QdrantOpsTopic, cfg.QdrantResultsTopic)

	// Graceful shutdown setup
	ctx, cancel := context.WithCancel(context.Background())
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

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
			log.Printf("receive error: %v", err)
			continue
		}

		// Extract tracing context from Pulsar message properties
		msgCtx := otel.GetTextMapPropagator().Extract(context.Background(), propagation.MapCarrier(msg.Properties()))

		adapter.wg.Add(1)
		go func() {
			defer adapter.wg.Done()
			adapter.dlqHandler.HandleMessage(msgCtx, msg, consumer, func(mCtx context.Context, m pulsar.Message) (dlq.ProcessResult, error) {
				return adapter.handleWithResult(mCtx, m)
			})
		}()
	}

	// Wait for in-flight ops
	log.Println("Waiting for in-flight Qdrant operations to complete...")
	done := make(chan struct{})
	go func() {
		adapter.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		log.Println("All in-flight operations completed")
	case <-time.After(shutdownTimeout):
		log.Printf("Shutdown timeout (%s) reached", shutdownTimeout)
	}

	log.Println("Qdrant Adapter shutdown complete")
}


func (a *Adapter) handleWithResult(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	start := time.Now()

	tracer := otel.Tracer("qdrant-adapter")
	ctx, span := tracer.Start(ctx, "HandleOp")
	defer span.End()

	var data map[string]interface{}
	if err := json.Unmarshal(msg.Payload(), &data); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("bad payload: %w", err)
	}

	opID, _ := data["id"].(string)
	action, _ := data["action"].(string)
	collection, _ := data["collection"].(string)
	vs := 0
	if s, ok := data["vector_size"].(float64); ok {
		vs = int(s)
	}

	attrs := []attribute.KeyValue{
		attribute.String("action", action),
		attribute.String("collection", collection),
		attribute.Int("vector_size", vs),
	}
	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		opLatency.Record(ctx, duration, metric.WithAttributes(attrs...))
	}()
	opCounter.Add(ctx, 1, metric.WithAttributes(attrs...))

	var (
		result interface{}
		opErr  error
	)

	switch action {
	case "search":
		vector := toFloat32Slice(data["vector"])
		limit := 5
		if l, ok := data["limit"].(float64); ok {
			limit = int(l)
		}
		tags := toStringSlice(data["tags"])
		result, opErr = a.qdrant.Search(collection, vs, vector, limit, tags)
	case "upsert":
		points, _ := data["points"].([]interface{})
		opErr = a.qdrant.Upsert(collection, vs, points)
		if opErr == nil {
			result = map[string]any{"ok": true, "count": len(points)}
		}
	case "create_collection":
		opErr = a.qdrant.CreateCollection(collection, vs)
		if opErr == nil {
			result = map[string]any{"ok": true}
		}
	default:
		return dlq.PermanentFailure, fmt.Errorf("unsupported action: %s", action)
	}

	// Always publish the result (success or error) to the results topic
	resp := map[string]any{
		"id":         opID,
		"action":     action,
		"collection": collection,
		"timestamp":  time.Now().Format(time.RFC3339),
	}
	if opErr != nil {
		resp["error"] = opErr.Error()
		log.Printf("[%s] Qdrant action '%s' failed on collection '%s': %v", opID, action, collection, opErr)
	} else {
		resp["result"] = result
	}

	payload, err := json.Marshal(resp)
	if err != nil {
		return dlq.PermanentFailure, fmt.Errorf("marshal Qdrant result: %w", err)
	}

	msgOut := &pulsar.ProducerMessage{
		Payload: payload,
	}
	if msgOut.Properties == nil {
		msgOut.Properties = make(map[string]string)
	}
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msgOut.Properties))

	_, perr := a.prod.Send(ctx, msgOut)
	if perr != nil {
		return dlq.TransientFailure, fmt.Errorf("publish result: %w", perr)
	}

	if opErr != nil {
		return dlq.TransientFailure, opErr
	}
	return dlq.Success, nil
}

func toFloat32Slice(v any) []float32 {
	arr, ok := v.([]interface{})
	if !ok {
		return nil
	}
	res := make([]float32, 0, len(arr))
	for _, it := range arr {
		if f, ok := it.(float64); ok {
			res = append(res, float32(f))
		}
	}
	return res
}

func toStringSlice(v any) []string {
	arr, ok := v.([]interface{})
	if !ok {
		return nil
	}
	res := make([]string, 0, len(arr))
	for _, it := range arr {
		if s, ok := it.(string); ok {
			res = append(res, s)
		}
	}
	return res
}
