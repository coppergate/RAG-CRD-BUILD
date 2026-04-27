package pipeline

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"

	"google.golang.org/protobuf/encoding/protojson"
	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/common/telemetry"
	"app-builds/rag-worker/internal/config"
	"app-builds/rag-worker/internal/models"
	"app-builds/rag-worker/pkg/messaging"
	"app-builds/rag-worker/pkg/search"
)

var (
	meter            = telemetry.Meter("rag-worker")
	taskCounter      metric.Int64Counter
	errorCounter     metric.Int64Counter
	taskLatency      metric.Float64Histogram
	llmLatency       metric.Float64Histogram
	responseSizeHist metric.Int64Histogram
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
	responseSizeHist, err = meter.Int64Histogram("worker_response_size_bytes", metric.WithUnit("By"))
	if err != nil {
		log.Printf("Warning: failed to create response size histogram: %v", err)
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
	if err := protojson.Unmarshal(msg.Payload(), &req); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal payload for stage %s: %w", stage, err)
	}

	switch stage {
	case "ingress":
		return h.handleIngress(ctx, &req)
	case "plan":
		return h.handlePlan(ctx, &req)
	case "search":
		return h.handleSearch(ctx, &req)
	case "exec":
		return h.handleExec(ctx, &req)
	default:
		return dlq.PermanentFailure, fmt.Errorf("unknown stage: %s", stage)
	}
}

func (h *Handler) handleIngress(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	h.msg.SendStatus(ctx, req.Id, req.SessionId, "INGRESS_RECEIVED", "Initial request received")

	payload, err := json.Marshal(req)
	if err != nil {
		log.Printf("[%s] Failed to marshal ingress data: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, "Internal serialization error", false)
		return dlq.PermanentFailure, fmt.Errorf("marshal ingress data: %w", err)
	}
	if _, err := h.msg.Producers.Plan.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		log.Printf("[%s] Failed to send to plan topic: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, "Internal messaging error", false)
		return dlq.TransientFailure, fmt.Errorf("send to plan topic: %w", err)
	}

	return dlq.Success, nil
}

func (h *Handler) handlePlan(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	h.msg.SendStatus(ctx, req.Id, req.SessionId, "PLANNING_TASK", "Decomposing prompt into sub-tasks")

	modelID := req.PlannerModel
	if modelID == "" {
		modelID = h.cfg.PlannerModel
	}

	planner, err := h.registry.GetPlanner(modelID)
	if err != nil {
		log.Printf("[%s] Planner resolution error: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Unsupported planner model: %s", modelID), false)
		return dlq.PermanentFailure, fmt.Errorf("planner resolution: %w", err)
	}

	subQueries, metrics, err := planner.Plan(ctx, req.Prompt)
	if err != nil {
		log.Printf("[%s] Planning failed: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Planning failed: %v", err), false)
		return dlq.TransientFailure, fmt.Errorf("planning: %w", err)
	}

	// We don't store planning metrics yet, but we could in the future.
	_ = metrics 

	if len(subQueries) == 0 {
		subQueries = []string{req.Prompt}
	}

	metadata := contracts.FromStruct(req.Metadata)
	if metadata == nil {
		metadata = make(map[string]interface{})
	}
	metadata["sub_queries"] = subQueries
	req.Metadata = contracts.ToStruct(metadata)

	payload, err := json.Marshal(req)
	if err != nil {
		log.Printf("[%s] Failed to marshal plan data: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, "Internal serialization error", false)
		return dlq.PermanentFailure, fmt.Errorf("marshal plan data: %w", err)
	}
	if _, err := h.msg.Producers.Search.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		log.Printf("[%s] Failed to send to search topic: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, "Internal messaging error", false)
		return dlq.TransientFailure, fmt.Errorf("send to search topic: %w", err)
	}

	return dlq.Success, nil
}

func (h *Handler) handleSearch(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	var subQueries []string
	metadata := contracts.FromStruct(req.Metadata)
	if metadata != nil {
		if sq, ok := metadata["sub_queries"].([]interface{}); ok {
			for _, q := range sq {
				if s, ok := q.(string); ok {
					subQueries = append(subQueries, s)
				}
			}
		}
	}
	if len(subQueries) == 0 {
		subQueries = []string{req.Prompt}
	}

	h.msg.SendStatus(ctx, req.Id, req.SessionId, "RETRIEVING_CONTEXT", fmt.Sprintf("Executing %d sub-queries", len(subQueries)))

	modelID := req.PlannerModel
	if modelID == "" {
		modelID = h.cfg.PlannerModel
	}

	planner, err := h.registry.GetPlanner(modelID)
	if err != nil {
		log.Printf("[%s] Planner resolution error in search: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Unsupported planner model for embeddings: %s", modelID), false)
		return dlq.PermanentFailure, fmt.Errorf("planner resolution: %w", err)
	}

	tags := req.Tags
	var allContexts []string
	for _, sq := range subQueries {
		vector, err := planner.GetEmbeddings(ctx, sq)
		if err != nil {
			log.Printf("[%s] Failed to get embeddings for sub-query '%s': %v", req.Id, sq, err)
			continue
		}
		vs := len(vector)
		log.Printf("[%s] Searching Qdrant: collection=%s, dims=%d, tags=%v, session=%s, query='%s'", req.Id, h.cfg.QdrantCollection, vs, tags, req.SessionId, sq)
		contexts, err := h.searcher.Search(ctx, vector, tags, req.SessionId)
		if err != nil {
			log.Printf("[%s] Qdrant search failed for sub-query '%s' (dims: %d): %v", req.Id, sq, vs, err)
			continue
		}
		log.Printf("[%s] Retrieved %d contexts for sub-query '%s'", req.Id, len(contexts), sq)
		allContexts = append(allContexts, contexts...)
	}

	if req.Metadata == nil {
		req.Metadata = contracts.ToStruct(make(map[string]interface{}))
	}
	metadataMap := contracts.FromStruct(req.Metadata)
	if metadataMap == nil {
		metadataMap = make(map[string]interface{})
	}
	metadataMap["contexts"] = allContexts
	if metadataMap["recursion_budget"] == nil {
		metadataMap["recursion_budget"] = h.cfg.RecursionBudget
	}
	req.Metadata = contracts.ToStruct(metadataMap)

	payload, err := json.Marshal(req)
	if err != nil {
		log.Printf("[%s] Failed to marshal search result data: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, "Internal serialization error", false)
		return dlq.PermanentFailure, fmt.Errorf("marshal search result data: %w", err)
	}
	if _, err := h.msg.Producers.Exec.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		log.Printf("[%s] Failed to send to exec topic: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, "Internal messaging error", false)
		return dlq.TransientFailure, fmt.Errorf("send to exec topic: %w", err)
	}

	return dlq.Success, nil
}

func (h *Handler) handleExec(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	h.msg.SendStatus(ctx, req.Id, req.SessionId, "EXECUTING_TASK", "Generating response with specialized model")

	var contexts []interface{}
	metadata := contracts.FromStruct(req.Metadata)
	if c, ok := metadata["contexts"].([]interface{}); ok {
		contexts = c
	}

	modelID := req.ExecutorModel
	if modelID == "" {
		modelID = h.cfg.ExecutorModel
	}

	executor, err := h.registry.GetExecutor(modelID)
	if err != nil {
		log.Printf("[%s] Executor resolution error: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Unsupported executor model: %s", modelID), false)
		return dlq.PermanentFailure, fmt.Errorf("executor resolution: %w", err)
	}

	if req.Stream {
		startTime := time.Now().UTC().Format(time.RFC3339)
		stream, metaCh, errCh := executor.ExecuteStream(ctx, req.Prompt, contexts)
		var fullResult string
		var finalMetrics *contracts.ExecutionMetrics
		seq := 0
		inConversation := false
		for {
			select {
			case chunk, ok := <-stream:
				if !ok {
					// Wait a bit for final metrics/error
					stream = nil
					if stream == nil && metaCh == nil && errCh == nil {
						goto endStream
					}
					continue
				}
				fullResult += chunk
				inConversation = true
				h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, chunk, seq, false, modelID, inConversation, contracts.FromStruct(req.Metadata))
				seq++
			case rawMeta, ok := <-metaCh:
				if !ok {
					metaCh = nil
					continue
				}
				finalMetrics = h.mapMetrics(rawMeta, modelID)
			case err := <-errCh:
				if err != nil {
					log.Printf("[%s] Execution stream failed: %v", req.Id, err)
					h.msg.SendError(ctx, req.Id, fmt.Sprintf("Execution stream failed: %v", err), inConversation)
					h.msg.SendCompletion(ctx, req.Id, req.SessionId, startTime, modelID, "FAILED", nil)
					return dlq.TransientFailure, fmt.Errorf("execution stream: %w", err)
				}
				errCh = nil
			case <-ctx.Done():
				h.msg.SendCompletion(ctx, req.Id, req.SessionId, startTime, modelID, "FAILED", nil)
				return dlq.TransientFailure, ctx.Err()
			}
		}

	endStream:
		// Record response size
		responseSizeHist.Record(ctx, int64(len(fullResult)), metric.WithAttributes(attribute.String("model", modelID), attribute.String("stage", "exec")))

		h.msg.SendStatus(ctx, req.Id, req.SessionId, "COMPLETED", "Response generated")
		h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, "", seq, true, modelID, inConversation, contracts.FromStruct(req.Metadata))
		h.msg.SendCompletion(ctx, req.Id, req.SessionId, startTime, modelID, "COMPLETED", finalMetrics)
		return dlq.Success, nil
	}

	startTime := time.Now().UTC().Format(time.RFC3339)
	result, rawMetrics, err := executor.Execute(ctx, req.Prompt, contexts)
	if err != nil {
		log.Printf("[%s] Execution failed: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Execution failed: %v", err), false)
		h.msg.SendCompletion(ctx, req.Id, req.SessionId, startTime, modelID, "FAILED", nil)
		return dlq.TransientFailure, fmt.Errorf("execution: %w", err)
	}

	metrics := h.mapMetrics(rawMetrics, modelID)

	// Grounding Guard / Recursion Check
	if executor.IsInsufficientContext(result) {
		currentMeta := contracts.FromStruct(req.Metadata)
		budget, _ := currentMeta["recursion_budget"].(float64)
		if budget > 0 {
			h.msg.SendStatus(ctx, req.Id, req.SessionId, "REFINING_PLAN", "Context insufficient, triggering recursion")
			currentMeta["recursion_budget"] = budget - 1
			req.Metadata = contracts.ToStruct(currentMeta)
			payload, err := json.Marshal(req)
			if err != nil {
				log.Printf("[%s] Failed to marshal recursion data: %v", req.Id, err)
				h.msg.SendError(ctx, req.Id, "Internal serialization error during recursion", false)
				return dlq.PermanentFailure, fmt.Errorf("marshal recursion data: %w", err)
			}
			if _, err := h.msg.Producers.Plan.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
				log.Printf("[%s] Failed to send recursion to plan topic: %v", req.Id, err)
				h.msg.SendError(ctx, req.Id, "Internal messaging error during recursion", false)
				return dlq.TransientFailure, fmt.Errorf("send recursion to plan: %w", err)
			}
			return dlq.Success, nil
		}
	}

	h.msg.SendStatus(ctx, req.Id, req.SessionId, "COMPLETED", "Response generated")
	h.msg.SendResult(ctx, req.Id, req.SessionId, result, modelID, contracts.FromStruct(req.Metadata))
	h.msg.SendCompletion(ctx, req.Id, req.SessionId, startTime, modelID, "COMPLETED", metrics)

	// Record response size
	responseSizeHist.Record(ctx, int64(len(result)), metric.WithAttributes(attribute.String("model", modelID), attribute.String("stage", "exec")))

	return dlq.Success, nil
}

func (h *Handler) mapMetrics(raw interface{}, modelID string) *contracts.ExecutionMetrics {
	if raw == nil {
		return nil
	}

	var m *contracts.ExecutionMetrics
	if or, ok := raw.(interface{ GetMetrics() *contracts.ExecutionMetrics }); ok {
		m = or.GetMetrics()
	}

	if m != nil && m.ModelFamily == "" {
		if strings.Contains(strings.ToLower(modelID), "llama") {
			m.ModelFamily = "llama"
		} else if strings.Contains(strings.ToLower(modelID), "granite") {
			m.ModelFamily = "granite"
		}
	}

	return m
}
