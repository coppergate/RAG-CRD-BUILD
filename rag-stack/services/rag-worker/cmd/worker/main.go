package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"database/sql"
	_ "github.com/lib/pq"

	"github.com/apache/pulsar-client-go/pulsar"
	"app-builds/rag-worker/internal/config"
	"app-builds/rag-worker/internal/ollama"
	"app-builds/rag-worker/internal/models"
	"app-builds/rag-worker/internal/models/llama3"
	"app-builds/rag-worker/internal/models/granite31"
	"app-builds/common/telemetry"
	"app-builds/common/contracts"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
)

var (
	meter            = telemetry.Meter("rag-worker")
	taskCounter, _   = meter.Int64Counter("worker_tasks_total")
	errorCounter, _  = meter.Int64Counter("worker_errors_total")
	taskLatency, _   = meter.Float64Histogram("worker_task_duration_ms", metric.WithUnit("ms"))
	llmLatency, _    = meter.Float64Histogram("worker_llm_duration_ms", metric.WithUnit("ms"))
)

type Worker struct {
	cfg        *config.Config
	pulsar     pulsar.Client
	registry   *models.ModelRegistry
	db         *sql.DB
	producer   pulsar.Producer // Results producer
	statusProd pulsar.Producer
	planProd   pulsar.Producer
	execProd   pulsar.Producer
	qOpsProd   pulsar.Producer
	pending    sync.Map // correlationID -> chan []string
}

func main() {
	cfg := config.LoadConfig()
	startHealthServer(":8080")

	shutdown, err := telemetry.InitTracer("rag-worker")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	db, err := sql.Open("postgres", os.Getenv("DB_CONN_STRING"))
	if err != nil {
		log.Printf("Warning: Could not connect to database: %v", err)
	} else {
		defer db.Close()
	}

	client, err := pulsar.NewClient(pulsar.ClientOptions{
		URL: cfg.PulsarURL,
	})
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer client.Close()

	producer, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.PulsarResultsTopic,
	})
	if err != nil {
		log.Fatalf("Could not create Results producer: %v", err)
	}
	defer producer.Close()

	statusProd, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.PulsarStatusTopic,
	})
	if err != nil {
		log.Fatalf("Could not create Status producer: %v", err)
	}
	defer statusProd.Close()

	planProd, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.PulsarPlanTopic,
	})
	if err != nil {
		log.Fatalf("Could not create Plan producer: %v", err)
	}
	defer planProd.Close()

	execProd, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.PulsarExecTopic,
	})
	if err != nil {
		log.Fatalf("Could not create Exec producer: %v", err)
	}
	defer execProd.Close()

	qOpsProd, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.QdrantOpsTopic,
	})
	if err != nil {
		log.Fatalf("Could not create Qdrant ops producer: %v", err)
	}
	defer qOpsProd.Close()

	// Model Registry setup
	registry := models.NewModelRegistry()
	registry.RegisterBackend("ollama", func(endpoint, modelName string) models.ChatClient {
		return ollama.NewClient(endpoint, modelName)
	})
	registry.RegisterPromptType("llama3", llama3.NewPlanner, llama3.NewExecutor)
	registry.RegisterPromptType("granite31", granite31.NewPlanner, granite31.NewExecutor)

	// Add default models from config
	pPromptType := "llama3"
	if strings.Contains(cfg.PlannerModel, "granite") {
		pPromptType = "granite31"
	}
	registry.RegisterModel(models.ModelSpec{
		ID:         cfg.PlannerModel,
		Name:       cfg.PlannerModel,
		Endpoint:   cfg.PlannerURL,
		Backend:    "ollama",
		PromptType: pPromptType,
	})

	ePromptType := "llama3"
	if strings.Contains(cfg.ExecutorModel, "granite") {
		ePromptType = "granite31"
	}
	registry.RegisterModel(models.ModelSpec{
		ID:         cfg.ExecutorModel,
		Name:       cfg.ExecutorModel,
		Endpoint:   cfg.ExecutorURL,
		Backend:    "ollama",
		PromptType: ePromptType,
	})

	worker := &Worker{
		cfg:        cfg,
		pulsar:     client,
		registry:   registry,
		db:         db,
		producer:   producer,
		statusProd: statusProd,
		planProd:   planProd,
		execProd:   execProd,
		qOpsProd:   qOpsProd,
	}

	// Consumer for Qdrant Results (Search results)
	qResultsSub := fmt.Sprintf("rag-worker-q-res-%s", os.Getenv("HOSTNAME"))
	qResConsumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.QdrantResultsTopic,
		SubscriptionName: qResultsSub,
		Type:             pulsar.Exclusive,
	})
	if err != nil {
		log.Fatalf("Could not subscribe to Qdrant results: %v", err)
	}
	defer qResConsumer.Close()

	go func() {
		for {
			msg, err := qResConsumer.Receive(context.Background())
			if err != nil {
				log.Printf("Error receiving Qdrant result: %v", err)
				continue
			}
			qResConsumer.Ack(msg)

			var resp struct {
				ID     string   `json:"id"`
				Result []string `json:"result"`
				Error  string   `json:"error"`
			}
			if err := json.Unmarshal(msg.Payload(), &resp); err == nil {
				if resp.Error != "" {
					log.Printf("[%s] Qdrant search returned error: %s", resp.ID, resp.Error)
				}
				if ch, ok := worker.pending.Load(resp.ID); ok {
					ch.(chan []string) <- resp.Result
				}
			}
		}
	}()

	// Consumer for RAG Stages
	consumer, err := client.Subscribe(pulsar.ConsumerOptions{
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
	defer consumer.Close()

	log.Printf("RAG Worker started, listening on multiple stages")

	for {
		msg, err := consumer.Receive(context.Background())
		if err != nil {
			log.Printf("Error receiving message: %v", err)
			continue
		}

		// Determine stage based on topic
		topic := msg.Topic()
		var stage string
		if strings.HasSuffix(topic, "ingress") {
			stage = "ingress"
		} else if strings.HasSuffix(topic, "plan") {
			stage = "plan"
		} else if strings.HasSuffix(topic, "exec") {
			stage = "exec"
		}

		// Extract tracing context from Pulsar message properties
		msgCtx := otel.GetTextMapPropagator().Extract(context.Background(), propagation.MapCarrier(msg.Properties()))

		go worker.handleStageMessage(msgCtx, stage, msg, consumer)
	}
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

func (w *Worker) searchQdrant(ctx context.Context, collection string, vectorSize int, vector []float32, tags []string) ([]string, error) {
	id := fmt.Sprintf("search-%d", time.Now().UnixNano())
	resChan := make(chan []string, 1)
	w.pending.Store(id, resChan)
	defer w.pending.Delete(id)

	op := map[string]interface{}{
		"id":          id,
		"action":      "search",
		"collection":  collection,
		"vector_size": vectorSize,
		"vector":      vector,
		"limit":       5,
		"tags":        tags,
	}
	payload, _ := json.Marshal(op)

	_, err := w.qOpsProd.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
	})
	if err != nil {
		return nil, err
	}

	select {
	case res := <-resChan:
		return res, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(30 * time.Second):
		return nil, fmt.Errorf("qdrant search timed out")
	}
}

func (w *Worker) handleStageMessage(ctx context.Context, stage string, msg pulsar.Message, consumer pulsar.Consumer) {
	start := time.Now()
	defer consumer.Ack(msg)

	tracer := otel.Tracer("rag-worker")
	ctx, span := tracer.Start(ctx, fmt.Sprintf("handleStage:%s", stage))
	defer span.End()

	attrs := []attribute.KeyValue{attribute.String("stage", stage)}
	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		taskLatency.Record(ctx, duration, metric.WithAttributes(attrs...))
	}()
	taskCounter.Add(ctx, 1, metric.WithAttributes(attrs...))

	var req contracts.InternalRequest
	if err := json.Unmarshal(msg.Payload(), &req); err != nil {
		log.Printf("Error unmarshaling payload: %v. Raw: %s", err, string(msg.Payload()))
		return
	}

	switch stage {
	case "ingress":
		w.handleIngress(ctx, &req)
	case "plan":
		w.handlePlan(ctx, &req)
	case "exec":
		w.handleExec(ctx, &req)
	default:
		log.Printf("Unknown stage: %s", stage)
	}
}

func (w *Worker) sendStatus(ctx context.Context, id, sessionID, state, details string) {
	payload, err := json.Marshal(map[string]interface{}{
		"id":         id,
		"session_id": sessionID,
		"state":      state,
		"details":    details,
		"timestamp":  time.Now().Format(time.RFC3339),
	})
	if err != nil {
		log.Printf("[%s] Failed to marshal status: %v", id, err)
		return
	}
	if _, err := w.statusProd.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
	}); err != nil {
		log.Printf("[%s] Failed to send status message: %v", id, err)
	}
}

func (w *Worker) handleIngress(ctx context.Context, req *contracts.InternalRequest) {
	w.sendStatus(ctx, req.ID, req.SessionID, "INGRESS_RECEIVED", "Initial request received")

	// Move to planning stage
	payload, err := json.Marshal(req)
	if err != nil {
		log.Printf("[%s] Failed to marshal ingress data: %v", req.ID, err)
		w.sendError(ctx, req.ID, "Internal serialization error")
		return
	}
	if _, err := w.planProd.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
	}); err != nil {
		log.Printf("[%s] Failed to send to plan topic: %v", req.ID, err)
		w.sendError(ctx, req.ID, "Internal messaging error")
	}
}

func (w *Worker) handlePlan(ctx context.Context, req *contracts.InternalRequest) {
	w.sendStatus(ctx, req.ID, req.SessionID, "PLANNING_TASK", "Decomposing prompt into sub-tasks")

	modelID := req.PlannerModel
	if modelID == "" {
		modelID = w.cfg.PlannerModel
	}

	planner, err := w.registry.GetPlanner(modelID)
	if err != nil {
		log.Printf("[%s] Planner resolution error: %v", req.ID, err)
		w.sendError(ctx, req.ID, fmt.Sprintf("Unsupported planner model: %s", modelID))
		return
	}

	// 1. Planning: Decompose into sub-tasks
	subQueries, err := planner.Plan(ctx, req.Prompt)
	if err != nil {
		log.Printf("[%s] Planning failed: %v", req.ID, err)
		w.sendError(ctx, req.ID, "Planning failed")
		return
	}

	if len(subQueries) == 0 {
		subQueries = []string{req.Prompt}
	}

	w.sendStatus(ctx, req.ID, req.SessionID, "RETRIEVING_CONTEXT", fmt.Sprintf("Executing %d sub-queries", len(subQueries)))

	collection := "vectors"
	tags := req.Tags

	var allContexts []string
	for _, sq := range subQueries {
		vector, err := planner.GetEmbeddings(ctx, sq)
		if err != nil {
			log.Printf("[%s] Failed to get embeddings for sub-query '%s': %v", req.ID, sq, err)
			continue
		}
		vs := len(vector)
		log.Printf("[%s] Searching Qdrant: collection=%s, dims=%d, tags=%v, query='%s'", req.ID, collection, vs, tags, sq)
		contexts, err := w.searchQdrant(ctx, collection, vs, vector, tags)
		if err != nil {
			log.Printf("[%s] Qdrant search failed for sub-query '%s' (dims: %d): %v", req.ID, sq, vs, err)
			continue
		}
		log.Printf("[%s] Retrieved %d contexts for sub-query '%s'", req.ID, len(contexts), sq)
		allContexts = append(allContexts, contexts...)
	}

	// Send to execution
	if req.Metadata == nil {
		req.Metadata = make(map[string]interface{})
	}
	req.Metadata["contexts"] = allContexts
	if req.Metadata["recursion_budget"] == nil {
		req.Metadata["recursion_budget"] = 2.0
	}

	payload, err := json.Marshal(req)
	if err != nil {
		log.Printf("[%s] Failed to marshal plan data: %v", req.ID, err)
		w.sendError(ctx, req.ID, "Internal serialization error")
		return
	}
	if _, err := w.execProd.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
	}); err != nil {
		log.Printf("[%s] Failed to send to exec topic: %v", req.ID, err)
		w.sendError(ctx, req.ID, "Internal messaging error")
	}
}

func (w *Worker) handleExec(ctx context.Context, req *contracts.InternalRequest) {
	w.sendStatus(ctx, req.ID, req.SessionID, "EXECUTING_TASK", "Generating response with specialized model")

	var contexts []interface{}
	if c, ok := req.Metadata["contexts"].([]interface{}); ok {
		contexts = c
	}

	modelID := req.ExecutorModel
	if modelID == "" {
		modelID = w.cfg.ExecutorModel
	}

	executor, err := w.registry.GetExecutor(modelID)
	if err != nil {
		log.Printf("[%s] Executor resolution error: %v", req.ID, err)
		w.sendError(ctx, req.ID, fmt.Sprintf("Unsupported executor model: %s", modelID))
		return
	}

	result, err := executor.Execute(ctx, req.Prompt, contexts)
	if err != nil {
		log.Printf("[%s] Execution failed: %v", req.ID, err)
		w.sendError(ctx, req.ID, "Execution failed")
		return
	}

	// Grounding Guard / Recursion Check
	if executor.IsInsufficientContext(result) {
		budget, _ := req.Metadata["recursion_budget"].(float64)
		if budget > 0 {
			w.sendStatus(ctx, req.ID, req.SessionID, "REFINING_PLAN", "Context insufficient, triggering recursion")
			req.Metadata["recursion_budget"] = budget - 1
			payload, err := json.Marshal(req)
			if err != nil {
				log.Printf("[%s] Failed to marshal recursion data: %v", req.ID, err)
				w.sendError(ctx, req.ID, "Internal serialization error during recursion")
				return
			}
			if _, err := w.planProd.Send(ctx, &pulsar.ProducerMessage{
				Payload: payload,
			}); err != nil {
				log.Printf("[%s] Failed to send recursion to plan topic: %v", req.ID, err)
				w.sendError(ctx, req.ID, "Internal messaging error during recursion")
			}
			return
		}
	}

	w.sendStatus(ctx, req.ID, req.SessionID, "COMPLETED", "Response generated")
	w.sendResult(ctx, req.ID, req.SessionID, result, modelID)
}

func (w *Worker) sendResult(ctx context.Context, id, sessionID, result, model string) {
	payload, err := json.Marshal(map[string]interface{}{
		"id":              id,
		"session_id":      sessionID,
		"result":          result,
		"sequence_number": 1, // Simplified for now, can be incremented if we support streaming/multiple chunks
		"model":           model,
	})
	if err != nil {
		log.Printf("[%s] Failed to marshal result: %v", id, err)
		return
	}

	msg := &pulsar.ProducerMessage{
		Payload: payload,
	}
	// Inject tracing context
	if msg.Properties == nil {
		msg.Properties = make(map[string]string)
	}
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msg.Properties))

	if _, err := w.producer.Send(ctx, msg); err != nil {
		log.Printf("[%s] Failed to send result to topic: %v", id, err)
	} else {
		log.Printf("[%s] Result sent", id)
	}
}

func (w *Worker) sendError(ctx context.Context, id, errMsg string) {
	payload, err := json.Marshal(map[string]string{
		"id":    id,
		"error": errMsg,
	})
	if err != nil {
		log.Printf("[%s] Failed to marshal error: %v", id, err)
		return
	}
	if _, err := w.producer.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
	}); err != nil {
		log.Printf("[%s] Failed to send error to topic: %v", id, err)
	}
}
