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
	"google.golang.org/protobuf/encoding/protojson"

	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/common/health"
	pulsarCommon "app-builds/common/pulsar"
	"app-builds/common/telemetry"
	"app-builds/qdrant-adapter/internal/config"
	"app-builds/qdrant-adapter/internal/qdrant"
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

	client, err := pulsarCommon.NewClient(pulsarCommon.Config{URL: cfg.PulsarURL})
	if err != nil {
		log.Fatalf("could not create pulsar client: %v", err)
	}
	defer client.Close()

	producer, err := client.NewProducer(cfg.QdrantResultsTopic)
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
	consumer, err := client.NewSharedConsumer(cfg.QdrantOpsTopic, cfg.PulsarSubscription)
	if err != nil {
		log.Fatalf("could not subscribe to qdrant ops: %v", err)
	}
	defer consumer.Close()

	mux := http.NewServeMux()
	healthSrv.RegisterRoutes(mux)

	mux.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		res, err := adapter.qdrant.ListCollections()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	})

	mux.HandleFunc("/collections", func(w http.ResponseWriter, r *http.Request) {
		res, err := adapter.qdrant.ListCollections()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(res)
	})

	mux.HandleFunc("/collections/", func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, "/collections/")
		if strings.HasSuffix(name, "/stats") {
			collName := strings.TrimSuffix(name, "/stats")
			res, err := adapter.qdrant.GetStats(collName)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(res)
			return
		}
		res, err := adapter.qdrant.GetCollection(name)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
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

	var data contracts.QdrantOp
	if err := protojson.Unmarshal(msg.Payload(), &data); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("bad payload: %w", err)
	}

	opID := data.Id
	action := data.Action
	collection := data.Collection
	vs := int(data.VectorSize)

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
		res, err := a.qdrant.Search(collection, vs, data.Vector, int(data.Limit), data.Tags, data.SessionId)
		if err == nil {
			log.Printf("[%s] Qdrant search returned %d results", opID, len(res))
		}
		result, opErr = res, err
	case "delete":
		log.Printf("[%s] Deleting points from collection %s with tags %v, paths %v", opID, collection, data.Tags, data.Paths)
		opErr = a.qdrant.DeleteByFilter(collection, vs, data.Tags, data.Paths)
	case "upsert":
		log.Printf("[%s] Upserting %d points into collection %s", opID, len(data.Points), collection)
		opErr = a.qdrant.UpsertProto(collection, vs, data.Points)
	case "create_collection":
		opErr = a.qdrant.CreateCollection(collection, vs)
	case "merge_tags":
		opErr = a.qdrant.MergeTags(collection, vs, data.SourceTag, data.TargetTag)
	default:
		return dlq.PermanentFailure, fmt.Errorf("unsupported action: %s", action)
	}

	// Always publish the result (success or error) to the results topic
	resp := &contracts.QdrantResponse{
		Id:         opID,
		Action:     action,
		Collection: collection,
		Timestamp:  time.Now().Format(time.RFC3339),
	}
	if opErr != nil {
		resp.Error = opErr.Error()
		log.Printf("[%s] Qdrant action '%s' failed on collection '%s': %v", opID, action, collection, opErr)
	} else {
		resp.Result = contracts.ToValue(result)
	}

	marshaller := protojson.MarshalOptions{
		UseProtoNames: true,
	}
	payload, err := marshaller.Marshal(resp)
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
