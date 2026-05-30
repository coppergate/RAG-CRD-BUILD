package pipeline

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"

	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/common/logging"
	"app-builds/common/telemetry"
	"app-builds/rag-worker/internal/behavioral"
	"app-builds/rag-worker/internal/config"
	"app-builds/rag-worker/internal/models"
	"app-builds/rag-worker/internal/ollama"
	"app-builds/rag-worker/pkg/messaging"

	"google.golang.org/protobuf/encoding/protojson"
)

var (
	meter            = telemetry.Meter("rag-worker")
	taskCounter      metric.Int64Counter
	errorCounter     metric.Int64Counter
	taskLatency      metric.Float64Histogram
	llmLatency       metric.Float64Histogram
	responseSizeHist metric.Int64Histogram

	literalAnswerFallbackPatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b(?:secret code|code|answer|token)\s*(?:is|:)\s*([A-Z0-9][A-Z0-9-]{2,})\b`),
	}
)

func init() {
	var err error
	taskCounter, err = meter.Int64Counter("worker_tasks_total")
	if err != nil {
		logging.Printf("Warning: failed to create task counter metric: %v", err)
	}
	errorCounter, err = meter.Int64Counter("worker_errors_total")
	if err != nil {
		logging.Printf("Warning: failed to create error counter metric: %v", err)
	}
	taskLatency, err = meter.Float64Histogram("worker_task_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		logging.Printf("Warning: failed to create task latency metric: %v", err)
	}
	llmLatency, err = meter.Float64Histogram("worker_llm_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		logging.Printf("Warning: failed to create llm latency metric: %v", err)
	}
	responseSizeHist, err = meter.Int64Histogram("worker_response_size_bytes", metric.WithUnit("By"))
	if err != nil {
		logging.Printf("Warning: failed to create response size histogram: %v", err)
	}
}

type QdrantSearcher interface {
	Search(ctx context.Context, embeddingModel string, vector []float32, tags []int64, sessionID int64, includeGlobal bool, limit int) ([]interface{}, error)
	RetrieveByPaths(ctx context.Context, embeddingModel string, paths []string) ([]interface{}, error)
}

type MemoryClient interface {
	Retrieve(ctx context.Context, sessionID int64, tags []int64, actionType, query string) (*contracts.MemoryPack, error)
	AuditRuleApplication(ctx context.Context, promptID string, ruleID int64, actionType string, metadata map[string]interface{}) error
	GetActionIdentifiers(ctx context.Context) (map[string][]string, error)
	RecordLearning(ctx context.Context, feedback string, actionType, category string, priority int) error
	ResetSessionBehavior(ctx context.Context, sessionID int64) error
}

type ModelRegistry interface {
	GetPlanner(modelID string) (models.Planner, error)
	GetExecutor(modelID string) (models.Executor, error)
}

type chunkSource struct {
	QdrantID       string `json:"qdrant_id,omitempty"`
	Path           string `json:"path,omitempty"`
	Chunk          int    `json:"chunk,omitempty"`
	Content        string `json:"content,omitempty"`
	EmbeddingModel string `json:"embedding_model,omitempty"`
	VectorSize     int    `json:"vector_size,omitempty"`
}

type chunkGroupDetail struct {
	Texts   []string      `json:"texts,omitempty"`
	Sources []chunkSource `json:"sources,omitempty"`
}

type executionUnit struct {
	Prompt   string
	Contexts []interface{}
	Label    string
}

// Handler processes RAG pipeline stage messages.
type Handler struct {
	cfg          *config.Config
	msg          *messaging.Client
	registry     ModelRegistry
	searcher     QdrantSearcher
	memoryClient MemoryClient
	tagSource    TagSource
	httpClient   *http.Client
}

// NewHandler creates a new pipeline stage handler.
func NewHandler(cfg *config.Config, msg *messaging.Client, registry ModelRegistry, searcher QdrantSearcher, mem MemoryClient, tagSource TagSource) *Handler {
	return &Handler{
		cfg:          cfg,
		msg:          msg,
		registry:     registry,
		searcher:     searcher,
		memoryClient: mem,
		tagSource:    tagSource,
		httpClient:   &http.Client{Timeout: 30 * time.Second},
	}
}

var errUnsupportedEmbeddingModel = fmt.Errorf("unsupported embedding model")

// HandleStageMessage processes a message for the given stage with DLQ support.
func (h *Handler) HandleStageMessage(ctx context.Context, stage string, msg pulsar.Message) (dlq.ProcessResult, error) {
	start := time.Now()

	var req contracts.InternalRequest
	if err := protojson.Unmarshal(msg.Payload(), &req); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal payload for stage %s: %w", stage, err)
	}

	tracer := otel.Tracer("rag-worker")
	ctx, span := tracer.Start(ctx, fmt.Sprintf("handleStage:%s", stage))
	defer span.End()

	attrs := []attribute.KeyValue{
		attribute.String("stage", stage),
		attribute.Int64("session_id", req.SessionId),
		attribute.String("request_id", req.Id),
	}
	span.SetAttributes(attrs...)

	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		if taskLatency != nil {
			taskLatency.Record(ctx, duration, metric.WithAttributes(attrs...))
		}
	}()
	if taskCounter != nil {
		taskCounter.Add(ctx, 1, metric.WithAttributes(attrs...))
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

	marshaller := protojson.MarshalOptions{UseProtoNames: true}
	payload, err := marshaller.Marshal(req)
	if err != nil {
		logging.Printf("[%s][SID:%d] Failed to marshal ingress data: %v", req.Id, req.SessionId, err)
		h.msg.SendError(ctx, req.Id, "Internal serialization error", false)
		return dlq.PermanentFailure, fmt.Errorf("marshal ingress data: %w", err)
	}
	if _, err := h.msg.Producers.Plan.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		logging.Printf("[%s][SID:%d] Failed to send to plan topic: %v", req.Id, req.SessionId, err)
		h.msg.SendError(ctx, req.Id, "Internal messaging error", false)
		return dlq.TransientFailure, fmt.Errorf("send to plan topic: %w", err)
	}

	return dlq.Success, nil
}

func (h *Handler) handlePlan(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	telemetry.RecordRecursion(ctx, "plan")
	if req.Stream {
		h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, "\n\u231B *Decomposing prompt into sub-tasks*...")
	}
	h.msg.SendStatus(ctx, req.Id, req.SessionId, "PLANNING_TASK", "Decomposing prompt into sub-tasks")

	modelID := req.PlannerModel
	if modelID == "" {
		modelID = h.cfg.PlannerModel
	}

	planner, err := h.registry.GetPlanner(modelID)
	if err != nil {
		logging.Printf("[%s][SID:%d] Planner resolution error: %v", req.Id, req.SessionId, err)
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Unsupported planner model: %s", modelID), false)
		return dlq.PermanentFailure, fmt.Errorf("planner resolution: %w", err)
	}

	actionMap, _ := h.memoryClient.GetActionIdentifiers(ctx)
	detectedActionType := behavioral.DetectActionType(req.Prompt, actionMap)

	// Fetch Memory (History + Behavioral Rules) for Planning Governance (Iteration 9)
	historyPack, err := h.memoryClient.Retrieve(ctx, req.SessionId, req.Tags, detectedActionType, req.Prompt)
	if err != nil {
		logging.Printf("[%s][SID:%d] Memory retrieval failed in planning: %v", req.Id, req.SessionId, err)
	}

	var history []interface{}
	if historyPack != nil {
		for _, item := range historyPack.Items {
			history = append(history, item)
		}
	}

	plan, metrics, err := planner.Plan(ctx, req.Prompt, nil, history)
	if err != nil {
		logging.Printf("[%s][SID:%d] Planning failed: %v", req.Id, req.SessionId, err)
		if ollama.IsMissingModelError(err) {
			h.msg.SendError(ctx, req.Id, fmt.Sprintf("Planning model unavailable in Ollama: %s", modelID), false)
			return dlq.PermanentFailure, fmt.Errorf("planning model unavailable: %w", err)
		}
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Planning failed: %v", err), false)
		return dlq.TransientFailure, fmt.Errorf("planning: %w", err)
	}

	actionType := detectedActionType
	if plan != nil && strings.TrimSpace(plan.ActionType) != "" && strings.ToUpper(strings.TrimSpace(plan.ActionType)) != contracts.PlannerActionUnknown {
		actionType = strings.ToUpper(strings.TrimSpace(plan.ActionType))
	}
	logging.Printf("[%s][SID:%d] Detected ActionType: %s", req.Id, req.SessionId, actionType)

	// Detect Memory Suggestions (Iteration 9b: The Learning Loop)
	if suggestion := behavioral.DetectMemorySuggestion(req.Prompt); suggestion != nil {
		logging.Printf("[%s] Detected memory suggestion for %s: %s (Priority: %d, Category: %s)",
			req.Id, suggestion.ActionType, suggestion.Instruction, suggestion.Priority, suggestion.Category)

		err := h.memoryClient.RecordLearning(ctx, suggestion.Instruction, suggestion.ActionType, suggestion.Category, suggestion.Priority)
		if err != nil {
			logging.Printf("[%s] Failed to record learning: %v", req.Id, err)
		} else {
			h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId,
				fmt.Sprintf("\n\U0001f4a1 *I've staged a new behavioral rule for %s.* (Category: %s, Priority: %d)\nWould you like to accept this memory?",
					suggestion.ActionType, suggestion.Category, suggestion.Priority))
		}
	}

	// Handle Session Behavior Reset
	if strings.Contains(strings.ToUpper(req.Prompt), "RESET BEHAVIOR") {
		if err := h.memoryClient.ResetSessionBehavior(ctx, req.SessionId); err != nil {
			logging.Printf("[%s] Failed to reset session behavior: %v", req.Id, err)
		} else {
			h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, "\n\u2705 *Session behavior priorities have been reset to defaults.*")
		}
	}

	// ...

	// We don't store planning metrics yet, but we could in the future.
	_ = metrics

	if plan == nil {
		plan = &contracts.PlannerTaskPlan{Objective: req.Prompt, ActionType: contracts.PlannerActionUnknown}
	}

	plan.ActionType = actionType
	plan.Normalize(req.Prompt)
	plan.Trace.ContextSources = []string{"memory-controller", "action-identifiers"}
	if historyPack != nil && len(historyPack.Items) > 0 {
		plan.Trace.ContextSources = append(plan.Trace.ContextSources, contextBucketSummary(historyPack.Items)...)
	}
	plan.Trace.AppliedRules = appliedRuleSummaries(historyPack)
	subQueries := append([]string{}, plan.SearchQueries...)
	if len(subQueries) == 0 {
		subQueries = []string{req.Prompt}
		plan.SearchQueries = subQueries
	}

	planningText := formatPlannerPlan(plan)
	planningMetrics := buildPlannerMetrics(req, plan, metrics, historyPack, detectedActionType, actionType)
	planningMetadata := map[string]interface{}{
		"planner_task":       plan.ToMap(),
		"planner_trace":      plan.Trace.ToMap(),
		"sub_queries":        subQueries,
		"action_type":        string(actionType),
		"evaluation_metrics": planningMetrics,
	}
	h.msg.SendPlanningResponseWithMetadata(ctx, req.Id, req.SessionId, planningText, planningMetadata)

	metadata := contracts.FromStruct(req.Metadata)
	if metadata == nil {
		metadata = make(map[string]interface{})
	}
	metadata["sub_queries"] = subQueries
	metadata["action_type"] = string(actionType)
	metadata["planner_task"] = plan.ToMap()
	metadata["planner_trace"] = plan.Trace.ToMap()
	metadata["evaluation_metrics"] = planningMetrics
	if historyPack != nil {
		metadata["history"] = historyPack.Items
	}
	req.Metadata = contracts.ToStruct(metadata)

	marshaller := protojson.MarshalOptions{UseProtoNames: true}
	payload, err := marshaller.Marshal(req)
	if err != nil {
		logging.Printf("[%s] Failed to marshal plan data: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, "Internal serialization error", false)
		return dlq.PermanentFailure, fmt.Errorf("marshal plan data: %w", err)
	}
	if _, err := h.msg.Producers.Search.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		logging.Printf("[%s][SID:%d] Failed to send to search topic: %v", req.Id, req.SessionId, err)
		h.msg.SendError(ctx, req.Id, "Internal messaging error", false)
		return dlq.TransientFailure, fmt.Errorf("send to search topic: %w", err)
	}

	return dlq.Success, nil
}

func formatPlannerPlan(plan *contracts.PlannerTaskPlan) string {
	if plan == nil {
		return "Planning complete."
	}

	var b strings.Builder
	b.WriteString("Planning complete.\n")
	b.WriteString(fmt.Sprintf("Objective: %s\n", plan.Objective))
	b.WriteString(fmt.Sprintf("Action type: %s\n", plan.ActionType))
	b.WriteString(fmt.Sprintf("Context budget: %d\n", plan.ContextBudget))
	b.WriteString(fmt.Sprintf("Risk: %s\n", plan.Risk))
	b.WriteString(fmt.Sprintf("Blocking: %t\n", plan.Blocking))

	if len(plan.Inputs) > 0 {
		b.WriteString("Inputs:\n")
		for _, input := range plan.Inputs {
			b.WriteString(fmt.Sprintf("- %s\n", input))
		}
	}

	if len(plan.Outputs) > 0 {
		b.WriteString("Outputs:\n")
		for _, output := range plan.Outputs {
			b.WriteString(fmt.Sprintf("- %s\n", output))
		}
	}

	if len(plan.Dependencies) > 0 {
		b.WriteString("Dependencies:\n")
		for _, dep := range plan.Dependencies {
			b.WriteString(fmt.Sprintf("- %s\n", dep))
		}
	}

	if len(plan.EvidenceRequirements) > 0 {
		b.WriteString("Evidence requirements:\n")
		for _, req := range plan.EvidenceRequirements {
			b.WriteString(fmt.Sprintf("- %s\n", req))
		}
	}

	if len(plan.SearchQueries) > 0 {
		b.WriteString("Search queries:\n")
		for _, sq := range plan.SearchQueries {
			b.WriteString(fmt.Sprintf("- %s\n", sq))
		}
	}

	if len(plan.Steps) > 0 {
		b.WriteString("Steps:\n")
		for _, step := range plan.Steps {
			label := step.Objective
			if label == "" {
				label = step.ActionType
			}
			b.WriteString(fmt.Sprintf("- %d. %s\n", step.Order, label))
			if len(step.Dependencies) > 0 {
				b.WriteString("  Dependencies:\n")
				for _, dep := range step.Dependencies {
					b.WriteString(fmt.Sprintf("  - %s\n", dep))
				}
			}
			if len(step.SearchQueries) > 0 {
				b.WriteString("  Search queries:\n")
				for _, sq := range step.SearchQueries {
					b.WriteString(fmt.Sprintf("  - %s\n", sq))
				}
			}
		}
	}

	return strings.TrimSpace(b.String())
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
	logging.Printf("[%s][SID:%d] search start: prompt_len=%d sub_queries=%d planner_model=%q executor_model=%q embedding_model=%q include_global=%v",
		req.Id, req.SessionId, len(req.Prompt), len(subQueries), req.PlannerModel, req.ExecutorModel, req.EmbeddingModel, req.IncludeGlobal)

	if req.Stream {
		h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, "\n\u231B *Retrieving context from vector store*...")
	}
	h.msg.SendStatus(ctx, req.Id, req.SessionId, "RETRIEVING_CONTEXT", fmt.Sprintf("Executing %d sub-queries", len(subQueries)))

	plannerModelID := req.PlannerModel
	if plannerModelID == "" {
		plannerModelID = h.cfg.PlannerModel
	}

	planner, err := h.registry.GetPlanner(plannerModelID)
	if err != nil {
		logging.Printf("[%s][SID:%d] Planner resolution error in search: %v", req.Id, req.SessionId, err)
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Unsupported planner model for embeddings: %s", plannerModelID), false)
		return dlq.PermanentFailure, fmt.Errorf("planner resolution: %w", err)
	}

	tags, err := h.resolveSearchTags(ctx, req)
	if err != nil {
		logging.Printf("[%s][SID:%d] Failed to resolve retrieval tags: %v", req.Id, req.SessionId, err)
		h.msg.SendError(ctx, req.Id, "Failed to resolve retrieval tags", false)
		return dlq.TransientFailure, fmt.Errorf("resolve retrieval tags: %w", err)
	}
	embeddingModels := h.resolveEmbeddingModelCandidates(req, plannerModelID)
	logging.Printf("[%s][SID:%d] resolved embedding candidates=%v", req.Id, req.SessionId, embeddingModels)
	var allRawResults []interface{}
	var retrievalProvenance []map[string]interface{}

	for idx, embeddingModel := range embeddingModels {
		embedder, err := h.registry.GetPlanner(embeddingModel)
		if err != nil {
			logging.Printf("[%s][SID:%d] Embedding model resolution error for %q: %v", req.Id, req.SessionId, embeddingModel, err)
			continue
		}

		logging.Printf("[%s][SID:%d] retrieval pass model=%q tags=%v sub_queries=%d", req.Id, req.SessionId, embeddingModel, tags, len(subQueries))
		contextFiles, err := h.fetchContextFiles(ctx, req, embeddingModel)
		if err != nil {
			logging.Printf("[%s][SID:%d] Context file discovery failed for %q: %v", req.Id, req.SessionId, embeddingModel, err)
		}

		modelResults, hydrated, hydrationNotes, err := h.searchWithEmbeddingModel(ctx, req, embeddingModel, embedder, subQueries, tags, contextFiles)
		if err != nil {
			if errors.Is(err, errUnsupportedEmbeddingModel) && idx+1 < len(embeddingModels) {
				logging.Printf("[%s][SID:%d] Embedding model %q is not embedding-capable; falling back to carried override %q", req.Id, req.SessionId, embeddingModel, embeddingModels[idx+1])
				continue
			}
			logging.Printf("[%s][SID:%d] Retrieval failed for embedding model %q: %v", req.Id, req.SessionId, embeddingModel, err)
			continue
		}
		if hydrated {
			retrievalProvenance = append(retrievalProvenance, hydrationNotes...)
		}
		allRawResults = append(allRawResults, modelResults...)
	}

	// 3. Deduplicate and chunk context
	chunkGroups := h.chunkResultsDetailed(ctx, allRawResults)
	allChunks := chunkGroupTexts(chunkGroups)

	if req.Stream {
		h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, fmt.Sprintf(" (Found %d vectors in %d groups)", len(allRawResults), len(allChunks)))
	}

	if req.Metadata == nil {
		req.Metadata = contracts.ToStruct(make(map[string]interface{}))
	}
	metadataMap := contracts.FromStruct(req.Metadata)
	if metadataMap == nil {
		metadataMap = make(map[string]interface{})
	}
	metadataMap["chunks"] = allChunks
	metadataMap["chunk_groups"] = chunkGroupsToMetadata(chunkGroups)
	metadataMap["contexts"] = flattenChunkContexts(allChunks)
	metadataMap["raw_results"] = allRawResults
	if len(embeddingModels) > 0 {
		metadataMap["embedding_models"] = embeddingModels
	}
	if len(retrievalProvenance) > 0 {
		metadataMap["retrieval_provenance"] = retrievalProvenance
	}

	var history []interface{}
	if hist, ok := metadataMap["history"].([]interface{}); ok {
		history = hist
	}

	refinedPlan, planMetrics, err := planner.Plan(ctx, req.Prompt, flattenChunkContexts(allChunks), history)
	if err != nil {
		logging.Printf("[%s][SID:%d] Refined planning with chunk context failed: %v", req.Id, req.SessionId, err)
	} else if refinedPlan != nil {
		metadataMap["planner_task"] = refinedPlan.ToMap()
		metadataMap["planner_trace"] = refinedPlan.Trace.ToMap()
		metadataMap["plan_step_contexts"] = buildPlanStepContexts(refinedPlan, chunkGroups)
		metadataMap["planner_refinement_metrics"] = planMetrics
	}

	metadataMap["evaluation_metrics"] = mergeNestedMetricMap(metadataMap["evaluation_metrics"], map[string]interface{}{
		"retrieval": map[string]interface{}{
			"sub_query_count":     len(subQueries),
			"raw_result_count":    len(allRawResults),
			"chunk_group_count":   len(allChunks),
			"chunk_source_count":  countChunkSources(chunkGroups),
			"tag_count":           len(tags),
			"include_global":      req.IncludeGlobal,
			"vector_search_count": len(subQueries),
			"has_tag_search":      len(tags) > 0,
		},
	})
	if metadataMap["recursion_budget"] == nil {
		metadataMap["recursion_budget"] = h.cfg.RecursionBudget
	}
	if metadataMap["recursion_count"] == nil {
		metadataMap["recursion_count"] = float64(0)
	}
	if metadataMap["total_chunks_processed"] == nil {
		metadataMap["total_chunks_processed"] = float64(0)
	}
	if metadataMap["chunk_offset"] == nil {
		metadataMap["chunk_offset"] = float64(0)
	}
	req.Metadata = contracts.ToStruct(metadataMap)

	marshaller := protojson.MarshalOptions{UseProtoNames: true}
	payload, err := marshaller.Marshal(req)
	if err != nil {
		logging.Printf("[%s] Failed to marshal search result data: %v", req.Id, err)
		h.msg.SendError(ctx, req.Id, "Internal serialization error", false)
		return dlq.PermanentFailure, fmt.Errorf("marshal search result data: %w", err)
	}
	if _, err := h.msg.Producers.Exec.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		logging.Printf("[%s][SID:%d] Failed to send to exec topic: %v", req.Id, req.SessionId, err)
		h.msg.SendError(ctx, req.Id, "Internal messaging error", false)
		return dlq.TransientFailure, fmt.Errorf("send to exec topic: %w", err)
	}

	return dlq.Success, nil
}

type contextFileRecord struct {
	Path           string   `json:"path"`
	Bucket         string   `json:"bucket"`
	CreatedAt      string   `json:"created_at"`
	Tags           []string `json:"tags"`
	Status         string   `json:"status"`
	EmbeddingModel string   `json:"embedding_model"`
	VectorSize     int      `json:"vector_size"`
	IngestionID    int64    `json:"ingestion_id"`
}

func (h *Handler) resolveEmbeddingModelCandidates(req *contracts.InternalRequest, primaryModelID string) []string {
	seen := make(map[string]bool)
	candidates := make([]string, 0, 2)

	add := func(model string) {
		model = strings.TrimSpace(model)
		if model == "" {
			return
		}
		key := contracts.NormalizeEmbeddingModelName(model)
		if key == "" {
			key = strings.ToLower(model)
		}
		if seen[key] {
			return
		}
		seen[key] = true
		candidates = append(candidates, model)
	}

	add(primaryModelID)
	add(req.EmbeddingModel)
	if len(candidates) == 1 && req.Metadata != nil {
		if meta := contracts.FromStruct(req.Metadata); meta != nil {
			if model, _ := meta["embedding_model"].(string); model != "" {
				add(model)
			}
		}
	}
	if len(candidates) == 0 && h.cfg.EmbeddingModel != "" {
		add(h.cfg.EmbeddingModel)
	}
	return candidates
}

func (h *Handler) fetchContextFiles(ctx context.Context, req *contracts.InternalRequest, embeddingModel string) ([]contextFileRecord, error) {
	baseURL := strings.TrimRight(h.cfg.DBAdapterURL, "/")
	if baseURL == "" {
		return nil, nil
	}

	params := url.Values{}
	if req.SessionId > 0 {
		params.Set("session_id", fmt.Sprintf("%d", req.SessionId))
	}
	for _, tagID := range req.Tags {
		params.Add("tag_id", fmt.Sprintf("%d", tagID))
	}
	embeddingModel = strings.TrimSpace(embeddingModel)
	if embeddingModel != "" {
		params.Set("embedding_model", embeddingModel)
	}

	endpoint := baseURL + "/storage/files"
	if encoded := params.Encode(); encoded != "" {
		endpoint += "?" + encoded
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}

	resp, err := h.httpClient.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("storage file lookup returned %d", resp.StatusCode)
	}

	var files []contextFileRecord
	if err := json.NewDecoder(resp.Body).Decode(&files); err != nil {
		return nil, err
	}
	return files, nil
}

func groupContextFilesByModel(files []contextFileRecord) map[string][]contextFileRecord {
	grouped := make(map[string][]contextFileRecord)
	for _, file := range files {
		model := strings.TrimSpace(file.EmbeddingModel)
		if model == "" {
			model = "default"
		}
		key := contracts.NormalizeEmbeddingModelName(model)
		if key == "" {
			key = strings.ToLower(model)
		}
		grouped[key] = append(grouped[key], file)
	}
	return grouped
}

func (h *Handler) searchWithEmbeddingModel(ctx context.Context, req *contracts.InternalRequest, embeddingModel string, embedder models.Planner, subQueries []string, tags []int64, contextFiles []contextFileRecord) ([]interface{}, bool, []map[string]interface{}, error) {
	logging.Printf("[%s][SID:%d] searchWithEmbeddingModel start model=%q tag_count=%d sub_queries=%d context_files=%d",
		req.Id, req.SessionId, embeddingModel, len(tags), len(subQueries), len(contextFiles))
	results, missingCollection, err := h.searchEmbeddingModelOnce(ctx, req, embeddingModel, embedder, subQueries, tags)
	if err != nil {
		return nil, false, nil, err
	}

	grouped := groupContextFilesByModel(contextFiles)
	modelKey := contracts.NormalizeEmbeddingModelName(embeddingModel)
	if modelKey == "" {
		modelKey = strings.ToLower(strings.TrimSpace(embeddingModel))
	}
	files := grouped[modelKey]
	if len(files) == 0 || len(results) > 0 && !missingCollection {
		return results, false, nil, nil
	}

	hydrationNotes, hydrateErr := h.hydrateContextFiles(ctx, req, embeddingModel, files)
	if hydrateErr != nil {
		return results, true, hydrationNotes, hydrateErr
	}

	var retryResults []interface{}
	var retryErr error
	for attempt := 0; attempt < 4; attempt++ {
		time.Sleep(time.Duration(attempt+1) * time.Second)
		retryResults, missingCollection, retryErr = h.searchEmbeddingModelOnce(ctx, req, embeddingModel, embedder, subQueries, tags)
		if retryErr != nil {
			if isMissingCollectionError(retryErr) {
				continue
			}
			return results, true, hydrationNotes, retryErr
		}
		if len(retryResults) > 0 || !missingCollection {
			return retryResults, true, hydrationNotes, nil
		}
	}

	if retryErr != nil && !isMissingCollectionError(retryErr) {
		return results, true, hydrationNotes, retryErr
	}
	return retryResults, true, hydrationNotes, nil
}

func (h *Handler) searchEmbeddingModelOnce(ctx context.Context, req *contracts.InternalRequest, embeddingModel string, embedder models.Planner, subQueries []string, tags []int64) ([]interface{}, bool, error) {
	var allRawResults []interface{}
	missingCollection := false

	if len(tags) > 0 {
		logging.Printf("[%s][SID:%d] tag-only Qdrant retrieval start model=%q tags=%v limit=%d include_global=%v",
			req.Id, req.SessionId, embeddingModel, tags, h.cfg.QdrantRetrievalLimit, req.IncludeGlobal)
		h.msg.SendStatus(ctx, req.Id, req.SessionId, "RETRIEVING_CONTEXT", fmt.Sprintf("Retrieving tagged context for %s", embeddingModel))
		tagResults, err := h.searcher.Search(ctx, embeddingModel, nil, tags, req.SessionId, req.IncludeGlobal, h.cfg.QdrantRetrievalLimit)
		if err != nil {
			logging.Printf("[%s][SID:%d] tag-only Qdrant retrieval failed model=%q tags=%v err=%v", req.Id, req.SessionId, embeddingModel, tags, err)
			if isMissingCollectionError(err) {
				missingCollection = true
			} else {
				return nil, false, err
			}
		} else {
			logging.Printf("[%s][SID:%d] tag-only Qdrant retrieval returned %d items model=%q tags=%v", req.Id, req.SessionId, len(tagResults), embeddingModel, tags)
			allRawResults = append(allRawResults, tagResults...)
		}
	}

	for _, sq := range subQueries {
		logging.Printf("[%s][SID:%d] embedding sub-query model=%q query=%q tag_count=%d", req.Id, req.SessionId, embeddingModel, sq, len(tags))
		vector, err := embedder.GetEmbeddings(ctx, sq)
		if err != nil {
			logging.Printf("[%s][SID:%d] Failed to get embeddings for sub-query '%s' using %s: %v", req.Id, req.SessionId, sq, embeddingModel, err)
			if ollama.IsMissingModelError(err) {
				return nil, false, fmt.Errorf("embedding model unavailable: %w", err)
			}
			if ollama.IsUnsupportedEmbeddingModelError(err) {
				return nil, false, errUnsupportedEmbeddingModel
			}
			continue
		}
		vs := len(vector)
		logging.Printf("[%s][SID:%d] qdrant semantic search request model=%q vector_dims=%d tags=%v limit=%d query=%q",
			req.Id, req.SessionId, embeddingModel, vs, tags, h.cfg.QdrantSearchLimit, sq)
		logging.Printf("[%s][SID:%d] Searching Qdrant for model=%s dims=%d tags=%v global=%v query='%s'", req.Id, req.SessionId, embeddingModel, vs, tags, req.IncludeGlobal, sq)
		results, err := h.searcher.Search(ctx, embeddingModel, vector, tags, req.SessionId, req.IncludeGlobal, h.cfg.QdrantSearchLimit)
		if err != nil {
			if isMissingCollectionError(err) {
				missingCollection = true
				continue
			}
			logging.Printf("[%s][SID:%d] Qdrant search failed for model=%s query '%s' (dims: %d): %v", req.Id, req.SessionId, embeddingModel, sq, vs, err)
			continue
		}
		logging.Printf("[%s][SID:%d] Retrieved %d items for model=%s query '%s'", req.Id, req.SessionId, len(results), embeddingModel, sq)
		allRawResults = append(allRawResults, results...)
	}

	return allRawResults, missingCollection, nil
}

func (h *Handler) hydrateContextFiles(ctx context.Context, req *contracts.InternalRequest, embeddingModel string, files []contextFileRecord) ([]map[string]interface{}, error) {
	if len(files) == 0 {
		return nil, nil
	}

	groupByBucket := make(map[string][]string)
	for _, file := range files {
		bucket := strings.TrimSpace(file.Bucket)
		if bucket == "" {
			continue
		}
		groupByBucket[bucket] = append(groupByBucket[bucket], file.Path)
	}

	if len(groupByBucket) == 0 {
		return nil, nil
	}

	baseURL := strings.TrimRight(h.cfg.IngestionURL, "/")
	if baseURL == "" {
		return nil, fmt.Errorf("ingestion URL is not configured")
	}

	notes := make([]map[string]interface{}, 0, len(groupByBucket))
	for bucket, paths := range groupByBucket {
		body := map[string]interface{}{
			"tag_ids":         req.Tags,
			"session_id":      req.SessionId,
			"file_names":      paths,
			"bucket_name":     bucket,
			"embedding_model": embeddingModel,
		}
		payload, err := json.Marshal(body)
		if err != nil {
			return notes, err
		}

		httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/ingest", bytes.NewReader(payload))
		if err != nil {
			return notes, err
		}
		httpReq.Header.Set("Content-Type", "application/json")

		resp, err := h.httpClient.Do(httpReq)
		if err != nil {
			return notes, err
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return notes, fmt.Errorf("hydration ingest returned %d", resp.StatusCode)
		}

		notes = append(notes, map[string]interface{}{
			"embedding_model": embeddingModel,
			"bucket":          bucket,
			"path_count":      len(paths),
			"paths":           paths,
		})
	}

	return notes, nil
}

func isMissingCollectionError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "collection not found") || strings.Contains(msg, "status 404")
}

func flattenChunkContexts(chunks [][]string) []interface{} {
	contexts := make([]interface{}, 0)
	for _, chunk := range chunks {
		for _, item := range chunk {
			if item != "" {
				contexts = append(contexts, item)
			}
		}
	}
	return contexts
}

func contextBucketSummary(items []*contracts.MemoryWriteItem) []string {
	seen := make(map[string]bool)
	order := make([]string, 0)
	for _, item := range items {
		if item == nil {
			continue
		}
		bucket := ""
		if item.Metadata != nil {
			meta := contracts.FromStruct(item.Metadata)
			bucket, _ = meta["context_bucket"].(string)
		}
		if bucket == "" {
			bucket = normalizeContextBucket(item.MemoryType)
		} else {
			bucket = normalizeContextBucket(bucket)
		}
		if bucket == "" {
			continue
		}
		if !seen[bucket] {
			seen[bucket] = true
			order = append(order, bucket)
		}
	}
	return order
}

func appliedRuleSummaries(pack *contracts.MemoryPack) []string {
	if pack == nil {
		return nil
	}
	summaries := make([]string, 0)
	for _, item := range pack.Items {
		if item == nil || item.MemoryType != "behavioral_rule" || item.Metadata == nil {
			continue
		}
		meta := contracts.FromStruct(item.Metadata)
		ruleID := formatMetricValue(meta["rule_id"])
		scope := formatMetricValue(meta["scope"])
		priority := formatMetricValue(meta["applied_priority"])
		summaries = append(summaries, fmt.Sprintf("%s:%s:%s", ruleID, scope, priority))
	}
	return summaries
}

func buildPlannerMetrics(req *contracts.InternalRequest, plan *contracts.PlannerTaskPlan, metrics interface{}, historyPack *contracts.MemoryPack, detectedActionType, finalActionType string) map[string]interface{} {
	metricMap := make(map[string]interface{})
	metricMap["prompt_char_count"] = len(req.Prompt)
	metricMap["detected_action_type"] = detectedActionType
	metricMap["final_action_type"] = finalActionType
	metricMap["context_budget"] = plan.ContextBudget
	metricMap["step_count"] = len(plan.Steps)
	metricMap["sub_query_count"] = len(plan.SearchQueries)
	metricMap["history_item_count"] = 0
	metricMap["behavioral_rule_count"] = 0
	metricMap["task_context_count"] = 0
	metricMap["episodic_history_count"] = 0

	if historyPack != nil {
		metricMap["history_item_count"] = len(historyPack.Items)
		for _, item := range historyPack.Items {
			if item == nil {
				continue
			}
			meta := map[string]interface{}{}
			if item.Metadata != nil {
				meta = contracts.FromStruct(item.Metadata)
			}
			bucket, _ := meta["context_bucket"].(string)
			bucket = normalizeContextBucket(bucket)
			if bucket == "" {
				bucket = normalizeContextBucket(item.MemoryType)
			}
			switch bucket {
			case "behavioral_rules", "action_scoped_behavior", "global_fallback_policy":
				metricMap["behavioral_rule_count"] = metricMap["behavioral_rule_count"].(int) + 1
			case "task_local_retrieval":
				metricMap["task_context_count"] = metricMap["task_context_count"].(int) + 1
			case "episodic_history":
				metricMap["episodic_history_count"] = metricMap["episodic_history_count"].(int) + 1
			}
		}
	}

	if normalized := normalizeAny(metrics); normalized != nil {
		metricMap["planner_model_metrics"] = normalized
	}
	return metricMap
}

func normalizeAny(v interface{}) interface{} {
	if v == nil {
		return nil
	}
	raw, err := json.Marshal(v)
	if err != nil {
		return fmt.Sprintf("%v", v)
	}
	var out interface{}
	if err := json.Unmarshal(raw, &out); err != nil {
		return fmt.Sprintf("%v", v)
	}
	return out
}

func formatMetricValue(v interface{}) string {
	switch t := v.(type) {
	case nil:
		return ""
	case string:
		return t
	case fmt.Stringer:
		return t.String()
	default:
		return fmt.Sprintf("%v", v)
	}
}

func mergeNestedMetricMap(existing interface{}, update map[string]interface{}) map[string]interface{} {
	merged := map[string]interface{}{}
	if existing != nil {
		if existingMap, ok := normalizeAny(existing).(map[string]interface{}); ok {
			for k, v := range existingMap {
				merged[k] = v
			}
		}
	}
	for k, v := range update {
		if existingVal, ok := merged[k].(map[string]interface{}); ok {
			if updateVal, ok := v.(map[string]interface{}); ok {
				merged[k] = mergeNestedMetricMap(existingVal, updateVal)
				continue
			}
		}
		merged[k] = v
	}
	return merged
}

func normalizeContextBucket(bucket string) string {
	switch strings.ToLower(strings.TrimSpace(bucket)) {
	case "behavioral_rule":
		return "behavioral_rules"
	case "chat_history":
		return "episodic_history"
	default:
		return strings.TrimSpace(bucket)
	}
}

func (h *Handler) chunkResults(ctx context.Context, rawResults []interface{}) [][]string {
	return chunkGroupTexts(h.chunkResultsDetailed(ctx, rawResults))
}

func (h *Handler) chunkResultsDetailed(ctx context.Context, rawResults []interface{}) []chunkGroupDetail {
	seenIDs := make(map[string]bool)
	type chunkInfo struct {
		source chunkSource
		index  int
	}
	files := make(map[string][]chunkInfo)
	var nonFileContexts []chunkSource
	pathsToFetch := make(map[string]map[string]bool)

	for _, it := range rawResults {
		m, ok := it.(map[string]interface{})
		if !ok {
			continue
		}

		id, _ := m["_qdrant_id"].(string)
		if id != "" {
			if seenIDs[id] {
				continue
			}
			seenIDs[id] = true
		}

		content, _ := m["content"].(string)
		if content == "" {
			content, _ = m["text"].(string)
		}
		if content == "" {
			continue
		}

		path, _ := m["path"].(string)
		embeddingModel, _ := m["embedding_model"].(string)
		if embeddingModel == "" {
			if meta, ok := m["metadata"].(map[string]interface{}); ok {
				embeddingModel, _ = meta["embedding_model"].(string)
			}
		}
		vectorSize := 0
		if vs, ok := m["vector_size"].(float64); ok {
			vectorSize = int(vs)
		} else if meta, ok := m["metadata"].(map[string]interface{}); ok {
			if vs, ok := meta["vector_size"].(float64); ok {
				vectorSize = int(vs)
			}
		}
		idxVal, _ := m["chunk"].(float64)
		src := chunkSource{
			QdrantID:       id,
			Path:           path,
			Chunk:          int(idxVal),
			Content:        content,
			EmbeddingModel: embeddingModel,
			VectorSize:     vectorSize,
		}

		if path != "" {
			key := chunkResultKey(path, embeddingModel)
			files[key] = append(files[key], chunkInfo{source: src, index: src.Chunk})
			if _, ok := pathsToFetch[embeddingModel]; !ok {
				pathsToFetch[embeddingModel] = make(map[string]bool)
			}
			pathsToFetch[embeddingModel][path] = true
		} else {
			nonFileContexts = append(nonFileContexts, src)
		}
	}

	if len(pathsToFetch) > 0 {
		for embeddingModel, fileSet := range pathsToFetch {
			pathList := make([]string, 0, len(fileSet))
			for p := range fileSet {
				pathList = append(pathList, p)
			}

			logging.Printf("Reassembling %d files for model %s from paths: %v", len(pathList), embeddingModel, pathList)
			fullFileChunks, err := h.searcher.RetrieveByPaths(ctx, embeddingModel, pathList)
			if err == nil {
				for _, it := range fullFileChunks {
					m, ok := it.(map[string]interface{})
					if !ok {
						continue
					}
					id, _ := m["_qdrant_id"].(string)
					if id != "" && seenIDs[id] {
						continue
					}
					if id != "" {
						seenIDs[id] = true
					}

					path, _ := m["path"].(string)
					content, _ := m["content"].(string)
					if content == "" {
						content, _ = m["text"].(string)
					}
					if path == "" || content == "" {
						continue
					}
					idxVal, _ := m["chunk"].(float64)
					vectorSize := 0
					if vs, ok := m["vector_size"].(float64); ok {
						vectorSize = int(vs)
					}
					src := chunkSource{
						QdrantID:       id,
						Path:           path,
						Chunk:          int(idxVal),
						Content:        content,
						EmbeddingModel: embeddingModel,
						VectorSize:     vectorSize,
					}
					key := chunkResultKey(path, embeddingModel)
					files[key] = append(files[key], chunkInfo{source: src, index: src.Chunk})
				}
			} else {
				logging.Printf("Failed to fetch full file chunks for %s: %v", embeddingModel, err)
			}
		}
	}

	var chunks []chunkGroupDetail
	currentChunk := chunkGroupDetail{}
	currentChunkSize := 0
	currentChunkModel := ""
	limit := h.cfg.ChunkVectorLimit
	if limit <= 0 {
		limit = 50
	}

	pathKeys := make([]string, 0, len(files))
	for p := range files {
		pathKeys = append(pathKeys, p)
	}
	sort.Strings(pathKeys)

	appendChunk := func(group chunkGroupDetail) {
		if len(group.Texts) == 0 {
			return
		}
		chunks = append(chunks, group)
	}

	for _, p := range pathKeys {
		_, groupModel := splitChunkGroupKey(p)
		fChunks := files[p]
		sort.Slice(fChunks, func(i, j int) bool {
			return fChunks[i].index < fChunks[j].index
		})

		numVectors := len(fChunks)
		if len(currentChunk.Texts) > 0 && currentChunkModel != "" && groupModel != currentChunkModel {
			appendChunk(currentChunk)
			currentChunk = chunkGroupDetail{}
			currentChunkSize = 0
			currentChunkModel = ""
		}
		if numVectors > limit {
			logging.Printf("ERROR: File %s too large (%d vectors), splitting into chunks of %d", p, numVectors, limit)
			if len(currentChunk.Texts) > 0 {
				appendChunk(currentChunk)
				currentChunk = chunkGroupDetail{}
				currentChunkSize = 0
				currentChunkModel = ""
			}
			for i := 0; i < numVectors; i += limit {
				end := i + limit
				if end > numVectors {
					end = numVectors
				}
				var sb strings.Builder
				sb.WriteString(fmt.Sprintf("--- File: %s (Part %d) ---", displayChunkGroupName(p), (i/limit)+1))
				var sources []chunkSource
				for _, c := range fChunks[i:end] {
					if sb.Len() > 0 {
						sb.WriteString("\n")
					}
					sb.WriteString(c.source.Content)
					sources = append(sources, c.source)
				}
				group := chunkGroupDetail{
					Texts:   []string{sb.String()},
					Sources: sources,
				}
				if (end - i) == limit {
					appendChunk(group)
				} else {
					currentChunk = group
					currentChunkSize = end - i
					currentChunkModel = groupModel
				}
			}
			continue
		}

		var sb strings.Builder
		sb.WriteString(fmt.Sprintf("--- File: %s ---", displayChunkGroupName(p)))
		var sources []chunkSource
		for _, c := range fChunks {
			sb.WriteString("\n")
			sb.WriteString(c.source.Content)
			sources = append(sources, c.source)
		}
		group := chunkGroupDetail{
			Texts:   []string{sb.String()},
			Sources: sources,
		}

		if currentChunkSize+numVectors > limit {
			appendChunk(currentChunk)
			currentChunk = group
			currentChunkSize = numVectors
			currentChunkModel = groupModel
		} else {
			currentChunk.Texts = append(currentChunk.Texts, group.Texts...)
			currentChunk.Sources = append(currentChunk.Sources, group.Sources...)
			currentChunkSize += numVectors
			currentChunkModel = groupModel
		}
	}

	for _, nfc := range nonFileContexts {
		if currentChunkSize+1 > limit {
			appendChunk(currentChunk)
			currentChunk = chunkGroupDetail{}
			currentChunkSize = 0
		}
		currentChunk.Texts = append(currentChunk.Texts, nfc.Content)
		currentChunk.Sources = append(currentChunk.Sources, nfc)
		currentChunkSize++
	}

	appendChunk(currentChunk)
	return chunks
}

func chunkGroupTexts(groups []chunkGroupDetail) [][]string {
	chunks := make([][]string, 0, len(groups))
	for _, group := range groups {
		if len(group.Texts) == 0 {
			continue
		}
		texts := make([]string, len(group.Texts))
		copy(texts, group.Texts)
		chunks = append(chunks, texts)
	}
	return chunks
}

func chunkResultKey(path, embeddingModel string) string {
	return path + "::" + strings.ToLower(strings.TrimSpace(embeddingModel))
}

func displayChunkGroupName(key string) string {
	parts := strings.SplitN(key, "::", 2)
	path := ""
	model := ""
	if len(parts) > 0 {
		path = parts[0]
	}
	if len(parts) > 1 {
		model = parts[1]
	}
	if model != "" {
		return fmt.Sprintf("%s [%s]", path, model)
	}
	if path != "" {
		return path
	}
	return key
}

func splitChunkGroupKey(key string) (string, string) {
	parts := strings.SplitN(key, "::", 2)
	if len(parts) == 0 {
		return "", ""
	}
	if len(parts) == 1 {
		return parts[0], ""
	}
	return parts[0], parts[1]
}

func chunkGroupsToMetadata(groups []chunkGroupDetail) []map[string]interface{} {
	out := make([]map[string]interface{}, 0, len(groups))
	for _, group := range groups {
		if len(group.Texts) == 0 {
			continue
		}
		sources := make([]map[string]interface{}, 0, len(group.Sources))
		for _, source := range group.Sources {
			sources = append(sources, map[string]interface{}{
				"qdrant_id":       source.QdrantID,
				"path":            source.Path,
				"chunk":           source.Chunk,
				"embedding_model": source.EmbeddingModel,
				"vector_size":     source.VectorSize,
			})
		}
		out = append(out, map[string]interface{}{
			"texts":   group.Texts,
			"sources": sources,
		})
	}
	return out
}

func countChunkSources(groups []chunkGroupDetail) int {
	total := 0
	for _, group := range groups {
		total += len(group.Sources)
	}
	return total
}

func normalizeTextTokens(text string) map[string]struct{} {
	tokens := make(map[string]struct{})
	fields := strings.FieldsFunc(strings.ToLower(text), func(r rune) bool {
		return !(unicode.IsLetter(r) || unicode.IsDigit(r))
	})
	for _, field := range fields {
		if len(field) < 3 {
			continue
		}
		tokens[field] = struct{}{}
	}
	return tokens
}

func joinPlanTerms(step contracts.PlannerStep) string {
	parts := []string{step.Objective, step.ActionType}
	parts = append(parts, step.SearchQueries...)
	parts = append(parts, step.Inputs...)
	parts = append(parts, step.Outputs...)
	parts = append(parts, step.Dependencies...)
	parts = append(parts, step.EvidenceRequirements...)
	return strings.Join(parts, " ")
}

func scoreChunkGroup(step contracts.PlannerStep, group chunkGroupDetail) int {
	stepTokens := normalizeTextTokens(joinPlanTerms(step))
	if len(stepTokens) == 0 {
		return 0
	}
	groupTokens := normalizeTextTokens(strings.Join(group.Texts, "\n"))
	score := 0
	for token := range stepTokens {
		if _, ok := groupTokens[token]; ok {
			score++
		}
	}
	return score
}

func buildPlanStepContexts(plan *contracts.PlannerTaskPlan, groups []chunkGroupDetail) []map[string]interface{} {
	if plan == nil || len(plan.Steps) == 0 || len(groups) == 0 {
		return nil
	}

	results := make([]map[string]interface{}, 0, len(plan.Steps))
	for idx, step := range plan.Steps {
		limit := step.ContextBudget
		if limit <= 0 {
			limit = 2
		}

		type scoredGroup struct {
			index int
			score int
		}

		scored := make([]scoredGroup, 0, len(groups))
		for gi, group := range groups {
			scored = append(scored, scoredGroup{index: gi, score: scoreChunkGroup(step, group)})
		}

		sort.SliceStable(scored, func(i, j int) bool {
			if scored[i].score == scored[j].score {
				return scored[i].index < scored[j].index
			}
			return scored[i].score > scored[j].score
		})

		selectedTexts := make([]interface{}, 0, limit)
		selectedSources := make([]map[string]interface{}, 0)
		selectedGroupIndices := make([]int, 0, limit)

		for _, candidate := range scored {
			if candidate.score <= 0 && len(selectedTexts) > 0 {
				break
			}
			group := groups[candidate.index]
			groupText := strings.Join(group.Texts, "\n")
			if groupText == "" {
				continue
			}
			selectedGroupIndices = append(selectedGroupIndices, candidate.index)
			selectedTexts = append(selectedTexts, groupText)
			for _, source := range group.Sources {
				selectedSources = append(selectedSources, map[string]interface{}{
					"qdrant_id":       source.QdrantID,
					"path":            source.Path,
					"chunk":           source.Chunk,
					"embedding_model": source.EmbeddingModel,
					"vector_size":     source.VectorSize,
				})
			}
			if len(selectedTexts) >= limit {
				break
			}
		}

		if len(selectedTexts) == 0 && len(groups) > 0 {
			groupText := strings.Join(groups[0].Texts, "\n")
			if groupText != "" {
				selectedTexts = append(selectedTexts, groupText)
				selectedGroupIndices = append(selectedGroupIndices, 0)
				for _, source := range groups[0].Sources {
					selectedSources = append(selectedSources, map[string]interface{}{
						"qdrant_id":       source.QdrantID,
						"path":            source.Path,
						"chunk":           source.Chunk,
						"embedding_model": source.EmbeddingModel,
						"vector_size":     source.VectorSize,
					})
				}
			}
		}

		stepPrompt := step.Objective
		if strings.TrimSpace(stepPrompt) == "" {
			stepPrompt = plan.Objective
		}
		actionType := strings.TrimSpace(step.ActionType)
		if actionType != "" && strings.ToUpper(actionType) != contracts.PlannerActionUnknown {
			if stepPrompt != "" {
				stepPrompt += "\n"
			}
			stepPrompt += fmt.Sprintf("Step action: %s", actionType)
		}

		results = append(results, map[string]interface{}{
			"step_index":          idx,
			"step_order":          step.Order,
			"step_objective":      step.Objective,
			"step_action_type":    step.ActionType,
			"step_prompt":         stepPrompt,
			"contexts":            selectedTexts,
			"context_texts":       selectedTexts,
			"matched_groups":      selectedGroupIndices,
			"matched_sources":     selectedSources,
			"context_budget":      limit,
			"step_search_queries": step.SearchQueries,
		})
	}

	return results
}

func extractExecutionUnits(metadata map[string]interface{}, fallbackPrompt string, chunks [][]interface{}) []executionUnit {
	if raw, ok := metadata["plan_step_contexts"].([]interface{}); ok && len(raw) > 0 {
		units := make([]executionUnit, 0, len(raw))
		for _, item := range raw {
			stepMap, ok := item.(map[string]interface{})
			if !ok {
				continue
			}
			unit := executionUnit{Prompt: fallbackPrompt}
			if prompt, ok := stepMap["step_prompt"].(string); ok && strings.TrimSpace(prompt) != "" {
				unit.Prompt = prompt
			}
			if contexts, ok := stepMap["contexts"].([]interface{}); ok {
				unit.Contexts = append(unit.Contexts, contexts...)
			}
			if len(unit.Contexts) == 0 {
				if contextTexts, ok := stepMap["context_texts"].([]interface{}); ok {
					unit.Contexts = append(unit.Contexts, contextTexts...)
				}
			}
			if label, ok := stepMap["step_objective"].(string); ok && label != "" {
				unit.Label = label
			} else if action, ok := stepMap["step_action_type"].(string); ok && action != "" {
				unit.Label = action
			} else {
				unit.Label = fmt.Sprintf("step-%v", stepMap["step_order"])
			}
			if len(unit.Contexts) > 0 {
				units = append(units, unit)
			}
		}
		if len(units) > 0 {
			return units
		}
	}

	units := make([]executionUnit, 0, len(chunks))
	for idx, chunk := range chunks {
		unit := executionUnit{Prompt: fallbackPrompt, Contexts: chunk, Label: fmt.Sprintf("chunk-%d", idx+1)}
		units = append(units, unit)
	}
	return units
}

func rawResultContextText(item interface{}) string {
	switch v := item.(type) {
	case map[string]interface{}:
		if content, _ := v["content"].(string); content != "" {
			return content
		}
		if text, _ := v["text"].(string); text != "" {
			return text
		}
		if payload, ok := v["payload"].(map[string]interface{}); ok {
			if content, _ := payload["content"].(string); content != "" {
				return content
			}
			if text, _ := payload["text"].(string); text != "" {
				return text
			}
		}
		if encoded, err := json.Marshal(v); err == nil {
			return string(encoded)
		}
	default:
		if v == nil {
			return ""
		}
		return fmt.Sprintf("%v", v)
	}
	return ""
}

func extractLiteralAnswerFallback(prompt string, chunks [][]interface{}) (string, bool) {
	promptLower := strings.ToLower(prompt)
	interested := strings.Contains(promptLower, "code") || strings.Contains(promptLower, "answer") || strings.Contains(promptLower, "token")
	if !interested {
		return "", false
	}

	for _, chunk := range chunks {
		for _, item := range chunk {
			text := rawResultContextText(item)
			if text == "" {
				continue
			}
			for _, re := range literalAnswerFallbackPatterns {
				match := re.FindStringSubmatch(text)
				if len(match) > 1 {
					return strings.TrimSpace(match[1]), true
				}
			}
		}
	}

	return "", false
}

func (h *Handler) handleExec(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	h.msg.SendStatus(ctx, req.Id, req.SessionId, "EXECUTING_TASK", "Generating response with specialized model")

	var history []interface{}
	metadata := contracts.FromStruct(req.Metadata)
	if metadata == nil {
		metadata = map[string]interface{}{}
	}
	if hist, ok := metadata["history"].([]interface{}); ok {
		history = hist
	}

	var chunks [][]interface{}
	if c, ok := metadata["chunks"].([]interface{}); ok {
		for _, chunk := range c {
			if chunkList, ok := chunk.([]interface{}); ok {
				chunks = append(chunks, chunkList)
			}
		}
	}
	if len(chunks) == 0 {
		if c, ok := metadata["contexts"].([]interface{}); ok {
			chunks = append(chunks, c)
		}
	}
	if len(chunks) == 0 {
		if raw, ok := metadata["raw_results"].([]interface{}); ok {
			for _, item := range raw {
				if text := rawResultContextText(item); text != "" {
					chunks = append(chunks, []interface{}{text})
				}
			}
		}
	}

	executionUnits := extractExecutionUnits(metadata, req.Prompt, chunks)
	if len(executionUnits) == 0 && len(chunks) == 0 {
		executionUnits = []executionUnit{{Prompt: req.Prompt, Contexts: []interface{}{}, Label: "step-1"}}
	}

	offset := 0
	if o, ok := metadata["chunk_offset"].(float64); ok {
		offset = int(o)
	}
	maxUnits := h.cfg.MaxChunksPerRecursion
	if maxUnits <= 0 {
		maxUnits = 10
	}
	if _, ok := metadata["plan_step_contexts"].([]interface{}); ok && len(executionUnits) > 0 {
		maxUnits = len(executionUnits)
	}

	end := offset + maxUnits
	if end > len(executionUnits) {
		end = len(executionUnits)
	}

	var unitsToProcess []executionUnit
	if offset < len(executionUnits) {
		unitsToProcess = executionUnits[offset:end]
	}
	if len(unitsToProcess) == 0 && offset == 0 {
		unitsToProcess = append(unitsToProcess, executionUnit{Prompt: req.Prompt, Contexts: []interface{}{}, Label: "step-1"})
	}

	modelID := req.ExecutorModel
	if modelID == "" {
		modelID = h.cfg.ExecutorModel
	}

	executor, err := h.registry.GetExecutor(modelID)
	if err != nil {
		logging.Printf("[%s][SID:%d] Executor resolution error: %v", req.Id, req.SessionId, err)
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Unsupported executor model: %s", modelID), false)
		return dlq.PermanentFailure, fmt.Errorf("executor resolution: %w", err)
	}

	plannerModelID := req.PlannerModel
	if plannerModelID == "" {
		plannerModelID = h.cfg.PlannerModel
	}
	planner, err := h.registry.GetPlanner(plannerModelID)
	if err != nil {
		logging.Printf("[%s][SID:%d] Planner resolution error in exec: %v", req.Id, req.SessionId, err)
	}

	startTime := time.Now().UTC().Format(time.RFC3339)
	var fullAccumulatedResult string
	var finalMetrics *contracts.ExecutionMetrics
	seq := 1
	inConversation := false
	hasSubstantialResult := false

	for i, unit := range unitsToProcess {
		actualIndex := offset + i
		label := unit.Label
		if label == "" {
			label = "context"
		}
		h.msg.SendStatus(ctx, req.Id, req.SessionId, "EXECUTING_TASK", fmt.Sprintf("Processing %s %d/%d (Total: %d)", label, actualIndex+1, end, len(executionUnits)))
		if req.Stream {
			h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, fmt.Sprintf("⌛ *Generating response (%s %d/%d)*...", label, actualIndex+1, end))
		}

		if planner != nil {
			refinedPlan, _, err := planner.Plan(ctx, unit.Prompt, unit.Contexts, history)
			if err == nil && refinedPlan != nil && len(refinedPlan.SearchQueries) > 0 && h.cfg.StreamIntermediate {
				planningText := fmt.Sprintf("Refined sub-queries for %s %d:", label, actualIndex+1)
				for _, sq := range refinedPlan.SearchQueries {
					planningText += fmt.Sprintf("\n- %s", sq)
				}
				h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, planningText)
			} else if err != nil && ollama.IsMissingModelError(err) {
				h.msg.SendError(ctx, req.Id, fmt.Sprintf("Planner model unavailable in Ollama: %s", plannerModelID), false)
				return dlq.PermanentFailure, fmt.Errorf("planner model unavailable: %w", err)
			}
		}

		if req.Stream {
			if actualIndex == 0 {
				h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, "", 0, false, modelID, false, metadata)
			}

			stream, metaCh, errCh := executor.ExecuteStream(ctx, unit.Prompt, unit.Contexts, history)
			var chunkBuffer string
			var chunkCount int
			var currentChunkResult string

			loop := true
			for loop {
				select {
				case c, ok := <-stream:
					if !ok {
						stream = nil
						if metaCh == nil && errCh == nil {
							loop = false
						}
						continue
					}
					fullAccumulatedResult += c
					currentChunkResult += c
					chunkBuffer += c
					chunkCount++
					inConversation = true

					if chunkCount >= h.cfg.StreamAccumulationCount {
						h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, chunkBuffer, seq, false, modelID, inConversation, nil)
						seq++
						chunkBuffer = ""
						chunkCount = 0
					}
				case rawMeta, ok := <-metaCh:
					if !ok {
						metaCh = nil
						if stream == nil && errCh == nil {
							loop = false
						}
						continue
					}
					m := h.mapMetrics(rawMeta, modelID)
					if finalMetrics == nil {
						finalMetrics = m
					} else if m != nil {
						finalMetrics.PromptTokens += m.PromptTokens
						finalMetrics.CompletionTokens += m.CompletionTokens
						finalMetrics.TotalDurationUsec += m.TotalDurationUsec
					}
				case err, ok := <-errCh:
					if !ok {
						errCh = nil
						if stream == nil && metaCh == nil {
							loop = false
						}
						continue
					}
					if err != nil {
						logging.Printf("[%s] Execution stream failed on %s %d: %v", req.Id, label, actualIndex+1, err)
						h.msg.SendError(ctx, req.Id, fmt.Sprintf("%s %d failed: %v", label, actualIndex+1, err), inConversation)
						if ollama.IsMissingModelError(err) {
							return dlq.PermanentFailure, fmt.Errorf("executor stream model unavailable: %w", err)
						}
					}
				case <-ctx.Done():
					h.msg.SendCompletion(ctx, req.Id, req.SessionId, startTime, modelID, "FAILED", nil)
					return dlq.TransientFailure, ctx.Err()
				}
			}
			if chunkBuffer != "" {
				h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, chunkBuffer, seq, false, modelID, inConversation, nil)
				seq++
			}
			if !executor.IsInsufficientContext(currentChunkResult) {
				hasSubstantialResult = true
			}
		} else {
			res, rawMeta, err := executor.Execute(ctx, unit.Prompt, unit.Contexts, history)
			if err != nil {
				logging.Printf("[%s] Execution failed on %s %d: %v", req.Id, label, actualIndex+1, err)
				h.msg.SendError(ctx, req.Id, fmt.Sprintf("%s %d failed: %v", label, actualIndex+1, err), inConversation)
				if ollama.IsMissingModelError(err) {
					return dlq.PermanentFailure, fmt.Errorf("executor model unavailable: %w", err)
				}
				continue
			}
			fullAccumulatedResult += res
			inConversation = true
			if !executor.IsInsufficientContext(res) {
				hasSubstantialResult = true
			}

			m := h.mapMetrics(rawMeta, modelID)
			if finalMetrics == nil {
				finalMetrics = m
			} else if m != nil {
				finalMetrics.PromptTokens += m.PromptTokens
				finalMetrics.CompletionTokens += m.CompletionTokens
				finalMetrics.TotalDurationUsec += m.TotalDurationUsec
			}

			if h.cfg.StreamIntermediate {
				h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, res, seq, false, modelID, inConversation, nil)
				seq++
			}
		}
	}

	isInsufficient := executor.IsInsufficientContext(fullAccumulatedResult)
	budget, _ := metadata["recursion_budget"].(float64)
	recursionCount, _ := metadata["recursion_count"].(float64)
	totalChunks, _ := metadata["total_chunks_processed"].(float64)

	if isInsufficient && !hasSubstantialResult {
		if fallback, ok := extractLiteralAnswerFallback(req.Prompt, chunks); ok {
			logging.Printf("[%s][SID:%d] Exec fallback extracted literal answer from retrieved context", req.Id, req.SessionId)
			fullAccumulatedResult = fallback
			isInsufficient = false
			hasSubstantialResult = true
		}
	}

	if responseSizeHist != nil {
		responseSizeHist.Record(ctx, int64(len(fullAccumulatedResult)), metric.WithAttributes(attribute.String("model", modelID), attribute.String("stage", "exec")))
	}

	totalChunks += float64(len(unitsToProcess))
	metadata["total_chunks_processed"] = totalChunks
	metadata["evaluation_metrics"] = mergeNestedMetricMap(metadata["evaluation_metrics"], map[string]interface{}{
		"execution": map[string]interface{}{
			"chunk_count":             len(unitsToProcess),
			"history_item_count":      len(history),
			"final_result_char_count": len(fullAccumulatedResult),
			"insufficient_context":    isInsufficient,
			"substantial_result":      hasSubstantialResult,
			"recursion_budget":        budget,
			"recursion_count":         recursionCount,
			"total_chunks_processed":  totalChunks,
			"stream_mode":             req.Stream,
		},
	})

	logging.Printf("[%s][SID:%d] Exec Summary: Insufficient=%v, Substantial=%v, Budget=%v, Recursions=%v, TotalChunks=%v",
		req.Id, req.SessionId, isInsufficient, hasSubstantialResult, budget, recursionCount, totalChunks)

	if end < len(executionUnits) && !hasSubstantialResult {
		if totalChunks >= float64(h.cfg.MaxTotalChunks) {
			logging.Printf("[%s][SID:%d] Max total chunks reached (%v), stopping pagination", req.Id, req.SessionId, totalChunks)
		} else if budget <= 0 {
			logging.Printf("[%s][SID:%d] Budget exhausted, stopping pagination", req.Id, req.SessionId)
		} else {
			logging.Printf("[%s][SID:%d] No substantial result in units %d-%d, paginating to next batch", req.Id, req.SessionId, offset+1, end)
			metadata["chunk_offset"] = float64(end)
			metadata["recursion_budget"] = budget - 0.1
			req.Metadata = contracts.ToStruct(metadata)
			marshaller := protojson.MarshalOptions{UseProtoNames: true}
			payload, err := marshaller.Marshal(req)
			if err == nil {
				if _, err := h.msg.Producers.Exec.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err == nil {
					return dlq.Success, nil
				}
			}
		}
	} else if isInsufficient && !hasSubstantialResult && budget >= 1.0 {
		if recursionCount >= float64(h.cfg.MaxRecursionCount) {
			logging.Printf("[%s][SID:%d] Max recursion count reached (%v), stopping", req.Id, req.SessionId, recursionCount)
		} else {
			logging.Printf("[%s][SID:%d] Context insufficient after all units, triggering re-plan", req.Id, req.SessionId)
			metadata["recursion_budget"] = budget - 1.0
			metadata["recursion_count"] = recursionCount + 1
			metadata["chunk_offset"] = float64(0)
			req.Metadata = contracts.ToStruct(metadata)
			marshaller := protojson.MarshalOptions{UseProtoNames: true}
			payload, err := marshaller.Marshal(req)
			if err == nil {
				if _, err := h.msg.Producers.Plan.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err == nil {
					return dlq.Success, nil
				}
			}
		}
	} else if end < len(executionUnits) && hasSubstantialResult {
		logging.Printf("[%s][SID:%d] Found substantial result, stopping processing early at %d/%d", req.Id, req.SessionId, end, len(executionUnits))
	}

	h.msg.SendStatus(ctx, req.Id, req.SessionId, "COMPLETED", "Response generated")
	if req.Stream {
		h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, "", seq, true, modelID, inConversation, nil)
	} else {
		h.msg.SendResult(ctx, req.Id, req.SessionId, fullAccumulatedResult, modelID, metadata)
	}
	h.msg.SendCompletion(ctx, req.Id, req.SessionId, startTime, modelID, "COMPLETED", finalMetrics)

	return dlq.Success, nil
}

func (h *Handler) mapMetrics(raw interface{}, modelID string) *contracts.ExecutionMetrics {
	if raw == nil {
		return nil
	}

	var m *contracts.ExecutionMetrics
	if or, ok := raw.(interface {
		GetMetrics() *contracts.ExecutionMetrics
	}); ok {
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
