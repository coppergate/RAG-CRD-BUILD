package main

import (
	"context"
	"encoding/json"
	"fmt"
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
	"app-builds/common/logging"
	pulsarCommon "app-builds/common/pulsar"
	"app-builds/common/telemetry"
	"app-builds/qdrant-adapter/internal/config"
	"app-builds/qdrant-adapter/internal/qdrant"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	"io"
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
		logging.Warn("failed to create op counter metric", "error", err)
	}
	errorCounter, err = meter.Int64Counter("qdrant_errors_total")
	if err != nil {
		logging.Warn("failed to create error counter metric", "error", err)
	}
	opLatency, err = meter.Float64Histogram("qdrant_op_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		logging.Warn("failed to create op latency metric", "error", err)
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
		logging.Warn("failed to initialize tracer", "error", err)
	} else {
		defer shutdown(context.Background())
	}

	client, err := pulsarCommon.NewClient(pulsarCommon.Config{URL: cfg.PulsarURL})
	if err != nil {
		logging.Error("could not create pulsar client", "error", err)
		os.Exit(1)
	}
	defer client.Close()

	producer, err := client.NewProducer(cfg.QdrantResultsTopic)
	if err != nil {
		logging.Error("could not create results producer", "error", err)
		os.Exit(1)
	}
	defer producer.Close()

	dlqHandler, err := dlq.NewHandler(client, "qdrant-adapter")
	if err != nil {
		logging.Error("Could not create DLQ handler", "error", err)
		os.Exit(1)
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
		logging.Error("could not subscribe to qdrant ops", "error", err)
		os.Exit(1)
	}
	defer consumer.Close()

	mux := http.NewServeMux()
	healthSrv.RegisterRoutes(mux)

	mux.HandleFunc("/search", adapter.HandleSearch)
	mux.HandleFunc("/upsert", adapter.HandleUpsert)
	mux.HandleFunc("/delete", adapter.HandleDelete)

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
		Addr:    cfg.HTTPAddr,
		Handler: otelHandler,
	}

	go func() {
		if cfg.TLSCert != "" && cfg.TLSKey != "" {
			logging.Info("starting Qdrant Adapter REST API with TLS", "addr", cfg.HTTPAddr)
			if err := server.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey); err != nil && err != http.ErrServerClosed {
				logging.Error("REST server failed", "error", err)
				os.Exit(1)
			}
		} else {
			logging.Info("starting Qdrant Adapter REST API", "addr", cfg.HTTPAddr)
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				logging.Error("REST server failed", "error", err)
				os.Exit(1)
			}
		}
	}()

	logging.Info("Qdrant Adapter started", "ops_topic", cfg.QdrantOpsTopic, "results_topic", cfg.QdrantResultsTopic)

	// Graceful shutdown setup
	ctx, cancel := context.WithCancel(context.Background())
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

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
			logging.Error("receive error", "error", err)
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
	logging.Info("waiting for in-flight Qdrant operations to complete")
	done := make(chan struct{})
	go func() {
		adapter.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		logging.Info("all in-flight operations completed")
	case <-time.After(shutdownTimeout):
		logging.Warn("shutdown timeout reached", "timeout", shutdownTimeout)
	}

	logging.Info("Qdrant Adapter shutdown complete")
}

func (a *Adapter) executeOp(ctx context.Context, data *contracts.QdrantOp) (*contracts.QdrantResponse, error) {
	start := time.Now()
	opID := data.Id
	action := data.Action
	collection := data.Collection
	embeddingModel := data.EmbeddingModel
	vs := int(data.VectorSize)
	effectiveCollection := contracts.BuildEmbeddingCollection(collection, embeddingModel, vs)

	attrs := []attribute.KeyValue{
		attribute.String("action", action),
		attribute.String("collection", effectiveCollection),
		attribute.Int("vector_size", vs),
		attribute.Int64("session_id", data.SessionId),
	}

	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		opLatency.Record(ctx, duration, metric.WithAttributes(attrs...))
	}()
	opCounter.Add(ctx, 1, metric.WithAttributes(attrs...))

	logging.L.WithTrace(ctx).Info("executing Qdrant op", "session_id", data.SessionId, "action", action, "collection", effectiveCollection)

	var (
		result interface{}
		opErr  error
	)

	switch action {
	case "search":
		res, err := a.qdrant.Search(collection, embeddingModel, vs, data.Vector, int(data.Limit), data.Tags, data.SessionId, data.IncludeGlobal)
		if err == nil {
			logging.L.WithTrace(ctx).Info("Qdrant search successful", "op_id", opID, "results", len(res))
		}
		result, opErr = res, err
	case "retrieve_paths":
		res, err := a.qdrant.RetrieveByPaths(collection, embeddingModel, vs, data.Paths, int(data.Limit))
		if err == nil {
			logging.L.WithTrace(ctx).Info("Qdrant retrieve_paths successful", "op_id", opID, "results", len(res))
		}
		result, opErr = res, err
	case "delete":
		logging.L.WithTrace(ctx).Info("deleting points from collection", "op_id", opID, "collection", effectiveCollection, "tags", data.Tags, "paths", data.Paths)
		opErr = a.qdrant.DeleteByFilter(collection, embeddingModel, vs, data.Tags, data.Paths)
	case "upsert":
		logging.L.WithTrace(ctx).Info("upserting points into collection", "op_id", opID, "points", len(data.Points), "collection", effectiveCollection)
		opErr = a.qdrant.UpsertProto(collection, embeddingModel, vs, data.Points)
	case "create_collection":
		opErr = a.qdrant.CreateCollection(collection, embeddingModel, vs)
	case "merge_tags":
		opErr = a.qdrant.MergeTags(collection, embeddingModel, vs, data.SourceTag, data.TargetTag)
	default:
		return nil, fmt.Errorf("unsupported action: %s", action)
	}

	if opErr != nil {
		logging.L.WithTrace(ctx).Error("Qdrant action failed", "op_id", opID, "action", action, "collection", collection, "error", opErr)
		errorCounter.Add(ctx, 1, metric.WithAttributes(attrs...))
	}

	resp := &contracts.QdrantResponse{
		Id:         opID,
		Action:     action,
		Collection: effectiveCollection,
		Timestamp:  time.Now().Format(time.RFC3339),
	}
	if opErr != nil {
		resp.Error = opErr.Error()
		logging.Printf("[%s] Qdrant action '%s' failed on collection '%s': %v", opID, action, collection, opErr)
	} else {
		resp.Result = contracts.ToValue(result)
	}
	return resp, nil
}

func (a *Adapter) handleWithResult(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	var data contracts.QdrantOp
	if err := protojson.Unmarshal(msg.Payload(), &data); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("bad payload: %w", err)
	}

	tracer := otel.Tracer("qdrant-adapter")
	ctx, span := tracer.Start(ctx, "HandleOp")
	defer span.End()

	resp, err := a.executeOp(ctx, &data)
	if err != nil {
		return dlq.PermanentFailure, err
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

	if resp.Error != "" {
		return dlq.TransientFailure, fmt.Errorf("%s", resp.Error)
	}
	return dlq.Success, nil
}

func (a *Adapter) HandleSearch(w http.ResponseWriter, r *http.Request) {
	a.handleHTTP(w, r, "search")
}

func (a *Adapter) HandleUpsert(w http.ResponseWriter, r *http.Request) {
	a.handleHTTP(w, r, "upsert")
}

func (a *Adapter) HandleDelete(w http.ResponseWriter, r *http.Request) {
	a.handleHTTP(w, r, "delete")
}

func (a *Adapter) handleHTTP(w http.ResponseWriter, r *http.Request, defaultAction string) {
	var op contracts.QdrantOp
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "failed to read body", http.StatusBadRequest)
		return
	}
	if err := protojson.Unmarshal(body, &op); err != nil {
		http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
		return
	}
	if op.Action == "" {
		op.Action = defaultAction
	}

	resp, err := a.executeOp(r.Context(), &op)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	out, err := protojson.Marshal(resp)
	if err != nil {
		http.Error(w, "failed to marshal response", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(out)
}
