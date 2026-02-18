package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"app-builds/qdrant-adapter/internal/config"
	"app-builds/qdrant-adapter/internal/qdrant"
	"app-builds/qdrant-adapter/internal/telemetry"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

type Adapter struct {
	cfg     *config.Config
	client  pulsar.Client
	prod    pulsar.Producer
	qdrant  *qdrant.QdrantClient
}

func main() {
	cfg := config.LoadConfig()

	shutdown, err := telemetry.InitTracer("qdrant-adapter")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	client, err := pulsar.NewClient(pulsar.ClientOptions{URL: cfg.PulsarURL})
	if err != nil {
		log.Fatalf("could not create pulsar client: %v", err)
	}
	defer client.Close()

	producer, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.QdrantResultsTopic})
	if err != nil {
		log.Fatalf("could not create results producer: %v", err)
	}
	defer producer.Close()

	adapter := &Adapter{
		cfg:    cfg,
		client: client,
		prod:   producer,
		qdrant: qdrant.NewClient(cfg),
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

	log.Printf("Qdrant Adapter started. Listening on %s, publishing to %s", cfg.QdrantOpsTopic, cfg.QdrantResultsTopic)
	for {
		msg, err := consumer.Receive(context.Background())
		if err != nil {
			log.Printf("receive error: %v", err)
			continue
		}

		// Extract tracing context from Pulsar message properties
		msgCtx := otel.GetTextMapPropagator().Extract(context.Background(), propagation.MapCarrier(msg.Properties()))

		go adapter.handle(msgCtx, msg, consumer)
	}
}

func (a *Adapter) handle(ctx context.Context, msg pulsar.Message, consumer pulsar.Consumer) {
	defer consumer.Ack(msg)

	tracer := otel.Tracer("qdrant-adapter")
	ctx, span := tracer.Start(ctx, "HandleOp")
	defer span.End()

	var data map[string]interface{}
	if err := json.Unmarshal(msg.Payload(), &data); err != nil {
		log.Printf("bad payload: %v", err)
		return
	}

	opID, _ := data["id"].(string)
	action, _ := data["action"].(string)
	collection, _ := data["collection"].(string)

	var (
		result interface{}
		err    error
	)

	switch action {
	case "search":
		vector := toFloat32Slice(data["vector"]) 
		limit := 5
		if l, ok := data["limit"].(float64); ok { limit = int(l) }
		tags := toStringSlice(data["tags"]) 
		result, err = a.qdrant.Search(collection, vector, limit, tags)
	case "upsert":
		points, _ := data["points"].([]interface{})
		err = a.qdrant.Upsert(collection, points)
		if err == nil { result = map[string]any{"ok": true, "count": len(points)} }
	case "create_collection":
		vs := 0
		if s, ok := data["vector_size"].(float64); ok { vs = int(s) }
		err = a.qdrant.CreateCollection(collection, vs)
		if err == nil { result = map[string]any{"ok": true} }
	default:
		err = fmt.Errorf("unsupported action: %s", action)
	}

	resp := map[string]any{
		"id":        opID,
		"action":    action,
		"collection": collection,
		"timestamp": time.Now().Format(time.RFC3339),
	}
	if err != nil {
		resp["error"] = err.Error()
	} else {
		resp["result"] = result
	}

	payload, _ := json.Marshal(resp)

	msgOut := &pulsar.ProducerMessage{
		Payload: payload,
	}
	// Inject tracing context
	if msgOut.Properties == nil {
		msgOut.Properties = make(map[string]string)
	}
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msgOut.Properties))

	_, perr := a.prod.Send(ctx, msgOut)
	if perr != nil {
		log.Printf("failed to publish result: %v", perr)
	}
}

func toFloat32Slice(v any) []float32 {
	arr, ok := v.([]interface{})
	if !ok { return nil }
	res := make([]float32, 0, len(arr))
	for _, it := range arr {
		if f, ok := it.(float64); ok { res = append(res, float32(f)) }
	}
	return res
}

func toStringSlice(v any) []string {
	arr, ok := v.([]interface{})
	if !ok { return nil }
	res := make([]string, 0, len(arr))
	for _, it := range arr {
		if s, ok := it.(string); ok { res = append(res, s) }
	}
	return res
}
