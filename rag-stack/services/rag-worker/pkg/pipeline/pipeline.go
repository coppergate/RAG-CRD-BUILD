package pipeline

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"

	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/common/telemetry"
	"app-builds/rag-worker/internal/config"
	"app-builds/rag-worker/internal/models"
	"app-builds/rag-worker/pkg/messaging"
	"app-builds/rag-worker/pkg/search"
)

var (
	meter          = telemetry.Meter("rag-worker")
	taskCounter    metric.Int64Counter
	errorCounter   metric.Int64Counter
	taskLatency    metric.Float64Histogram
	llmLatency     metric.Float64Histogram
)

func init() {
	var err error
	taskCounter, err = meter.Int64Counter("worker_tasks_total")
	if err != nil {
		log.Printf("Warning: failed to create task counter metric: %v", err)
	}
	errorCounter, err = meter.Int64Counter("worker_errors_total")
	if err != nil {
		log.Printf("Warning: failed to create error counter metric: %v", err)
	}
	taskLatency, err = meter.Float64Histogram("worker_task_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		log.Printf("Warning: failed to create task latency metric: %v", err)
	}
	llmLatency, err = meter.Float64Histogram("worker_llm_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		log.Printf("Warning: failed to create llm latency metric: %v", err)
	}
}

// Handler processes RAG pipeline stage messages.
type Handler struct {
	cfg      *config.Config
	msg      *messaging.Client
	registry *models.ModelRegistry
	searcher *search.QdrantSearcher
}

// NewHandler creates a new pipeline stage handler.
func NewHandler(cfg *config.Config, msg *messaging.Client, registry *models.ModelRegistry, searcher *search.QdrantSearcher) *Handler {
	return &Handler{
		cfg:      cfg,
		msg:      msg,
		registry: registry,
		searcher: searcher,
	}
}

// HandleStageMessage processes a message for the given stage with DLQ support.
func (h *Handler) HandleStageMessage(ctx context.Context, stage string, msg pulsar.Message) (dlq.ProcessResult, error) {
	start := time.Now()

	tracer := otel.Tracer("rag-worker")
	ctx, span := tracer.Start(ctx, fmt.Sprintf("handleStage:%s", stage))
	defer span.End()

	attrs := []attribute.KeyValue{attribute.String("stage", stage)}
	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		if taskLatency != nil {
			taskLatency.Record(ctx, duration, metric.WithAttributes(attrs...))
		}
	}()
	if taskCounter != nil {
		taskCounter.Add(ctx, 1, metric.WithAttributes(attrs...))
	}

	var req contracts.InternalRequest
	if err := json.Unmarshal(msg.Payload(), &req); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal payload for stage %s: %w", stage, err)
	}

	switch stage {
	case "ingress":
		return h.handleIngress(ctx, &req)
	case "plan":
		return h.handlePlan(ctx, &req)
	case "exec":
		return h.handleExec(ctx, &req)
	default:
		return dlq.PermanentFailure, fmt.Errorf("unknown stage: %s", stage)
	}
}

func (h *Handler) handleIngress(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	h.msg.SendStatus(ctx, req.ID, req.SessionID, "INGRESS_RECEIVED", "Initial request received")

	payload, err := json.Marshal(req)
	if err != nil {
		log.Printf("[%s] Failed to marshal ingress data: %v", req.ID, err)
		h.msg.SendError(ctx, req.ID, "Internal serialization error")
		return dlq.PermanentFailure, fmt.Errorf("marshal ingress data: %w", err)
	}
	if _, err := h.msg.Producers.Plan.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		log.Printf("[%s] Failed to send to plan topic: %v", req.ID, err)
		h.msg.SendError(ctx, req.ID, "Internal messaging error")
		return dlq.TransientFailure, fmt.Errorf("send to plan topic: %w", err)
	}

	return dlq.Success, nil
}

func (h *Handler) handlePlan(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	h.msg.SendStatus(ctx, req.ID, req.SessionID, "PLANNING_TASK", "Decomposing prompt into sub-tasks")

	modelID := req.PlannerModel
	if modelID == "" {
		modelID = h.cfg.PlannerModel
	}

	planner, err := h.registry.GetPlanner(modelID)
	if err != nil {
		log.Printf("[%s] Planner resolution error: %v", req.ID, err)
		h.msg.SendError(ctx, req.ID, fmt.Sprintf("Unsupported planner model: %s", modelID))
		return dlq.PermanentFailure, fmt.Errorf("planner resolution: %w", err)
	}

	subQueries, err := planner.Plan(ctx, req.Prompt)
	if err != nil {
		log.Printf("[%s] Planning failed: %v", req.ID, err)
		h.msg.SendError(ctx, req.ID, fmt.Sprintf("Planning failed: %v", err))
		return dlq.TransientFailure, fmt.Errorf("planning: %w", err)
	}

	if len(subQueries) == 0 {
		subQueries = []string{req.Prompt}
	}

	h.msg.SendStatus(ctx, req.ID, req.SessionID, "RETRIEVING_CONTEXT", fmt.Sprintf("Executing %d sub-queries", len(subQueries)))

	tags := req.Tags
	var allContexts []string
	for _, sq := range subQueries {
		vector, err := planner.GetEmbeddings(ctx, sq)
		if err != nil {
			log.Printf("[%s] Failed to get embeddings for sub-query '%s': %v", req.ID, sq, err)
			continue
		}
		vs := len(vector)
		log.Printf("[%s] Searching Qdrant: collection=%s, dims=%d, tags=%v, query='%s'", req.ID, h.cfg.QdrantCollection, vs, tags, sq)
		contexts, err := h.searcher.Search(ctx, vector, tags)
		if err != nil {
			log.Printf("[%s] Qdrant search failed for sub-query '%s' (dims: %d): %v", req.ID, sq, vs, err)
			continue
		}
		log.Printf("[%s] Retrieved %d contexts for sub-query '%s'", req.ID, len(contexts), sq)
		allContexts = append(allContexts, contexts...)
	}

	if req.Metadata == nil {
		req.Metadata = make(map[string]interface{})
	}
	req.Metadata["contexts"] = allContexts
	if req.Metadata["recursion_budget"] == nil {
		req.Metadata["recursion_budget"] = h.cfg.RecursionBudget
	}

	payload, err := json.Marshal(req)
	if err != nil {
		log.Printf("[%s] Failed to marshal plan data: %v", req.ID, err)
		h.msg.SendError(ctx, req.ID, "Internal serialization error")
		return dlq.PermanentFailure, fmt.Errorf("marshal plan data: %w", err)
	}
	if _, err := h.msg.Producers.Exec.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		log.Printf("[%s] Failed to send to exec topic: %v", req.ID, err)
		h.msg.SendError(ctx, req.ID, "Internal messaging error")
		return dlq.TransientFailure, fmt.Errorf("send to exec topic: %w", err)
	}

	return dlq.Success, nil
}

func (h *Handler) handleExec(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	h.msg.SendStatus(ctx, req.ID, req.SessionID, "EXECUTING_TASK", "Generating response with specialized model")

	var contexts []interface{}
	if c, ok := req.Metadata["contexts"].([]interface{}); ok {
		contexts = c
	}

	modelID := req.ExecutorModel
	if modelID == "" {
		modelID = h.cfg.ExecutorModel
	}

	executor, err := h.registry.GetExecutor(modelID)
	if err != nil {
		log.Printf("[%s] Executor resolution error: %v", req.ID, err)
		h.msg.SendError(ctx, req.ID, fmt.Sprintf("Unsupported executor model: %s", modelID))
		return dlq.PermanentFailure, fmt.Errorf("executor resolution: %w", err)
	}

	if req.Stream {
		stream, errCh := executor.ExecuteStream(ctx, req.Prompt, contexts)
		var fullResult string
		seq := 0
		for {
			select {
			case chunk, ok := <-stream:
				if !ok {
					// Stream closed, handle grounding/recursion check on fullResult if needed
					// For now, just send completed status
					h.msg.SendStatus(ctx, req.ID, req.SessionID, "COMPLETED", "Response generated")
					h.msg.SendStreamChunk(ctx, req.ID, req.SessionID, "", seq, true, modelID)
					return dlq.Success, nil
				}
				fullResult += chunk
				h.msg.SendStreamChunk(ctx, req.ID, req.SessionID, chunk, seq, false, modelID)
				seq++
			case err := <-errCh:
				if err != nil {
					log.Printf("[%s] Execution stream failed: %v", req.ID, err)
					h.msg.SendError(ctx, req.ID, fmt.Sprintf("Execution stream failed: %v", err))
					return dlq.TransientFailure, fmt.Errorf("execution stream: %w", err)
				}
			case <-ctx.Done():
				return dlq.TransientFailure, ctx.Err()
			}
		}
	}

	result, err := executor.Execute(ctx, req.Prompt, contexts)
	if err != nil {
		log.Printf("[%s] Execution failed: %v", req.ID, err)
		h.msg.SendError(ctx, req.ID, fmt.Sprintf("Execution failed: %v", err))
		return dlq.TransientFailure, fmt.Errorf("execution: %w", err)
	}

	// Grounding Guard / Recursion Check
	if executor.IsInsufficientContext(result) {
		budget, _ := req.Metadata["recursion_budget"].(float64)
		if budget > 0 {
			h.msg.SendStatus(ctx, req.ID, req.SessionID, "REFINING_PLAN", "Context insufficient, triggering recursion")
			req.Metadata["recursion_budget"] = budget - 1
			payload, err := json.Marshal(req)
			if err != nil {
				log.Printf("[%s] Failed to marshal recursion data: %v", req.ID, err)
				h.msg.SendError(ctx, req.ID, "Internal serialization error during recursion")
				return dlq.PermanentFailure, fmt.Errorf("marshal recursion data: %w", err)
			}
			if _, err := h.msg.Producers.Plan.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
				log.Printf("[%s] Failed to send recursion to plan topic: %v", req.ID, err)
				h.msg.SendError(ctx, req.ID, "Internal messaging error during recursion")
				return dlq.TransientFailure, fmt.Errorf("send recursion to plan: %w", err)
			}
			return dlq.Success, nil
		}
	}

	h.msg.SendStatus(ctx, req.ID, req.SessionID, "COMPLETED", "Response generated")
	h.msg.SendResult(ctx, req.ID, req.SessionID, result, modelID)
	return dlq.Success, nil
}
