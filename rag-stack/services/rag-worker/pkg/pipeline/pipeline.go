package pipeline

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

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
	"app-builds/rag-worker/pkg/embed"
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


// Handler processes RAG pipeline stage messages.
type Handler struct {
	cfg              *config.Config
	msg              *messaging.Client
	registry         ModelRegistry
	searcher         QdrantSearcher
	memoryClient     MemoryClient
	tagSource        TagSource
	httpClient       *http.Client
	hydrationClient  *http.Client

	// Embed fan-out (Iteration 10a). Non-nil only when cfg.EmbedFanoutEnabled is true.
	embedProducer    pulsar.Producer
	resultDispatcher *embed.ResultDispatcher
}

// NewHandler creates a new pipeline stage handler.
func NewHandler(cfg *config.Config, msg *messaging.Client, registry ModelRegistry, searcher QdrantSearcher, mem MemoryClient, tagSource TagSource) *Handler {
	h := &Handler{
		cfg:             cfg,
		msg:             msg,
		registry:        registry,
		searcher:        searcher,
		memoryClient:    mem,
		tagSource:       tagSource,
		httpClient:      &http.Client{Timeout: 30 * time.Second},
		hydrationClient: &http.Client{Timeout: cfg.HydrationTimeout},
	}
	if cfg.EmbedFanoutEnabled {
		h.initEmbedFanout(msg.PulsarClient())
	}
	return h
}

// initEmbedFanout initialises the embed producer and result dispatcher.
// Errors are logged but do not terminate the process; fanout will remain disabled.
func (h *Handler) initEmbedFanout(pulsarClient pulsar.Client) {
	prod, err := pulsarClient.CreateProducer(pulsar.ProducerOptions{
		Topic:           h.cfg.PulsarEmbedJobsTopic,
		CompressionType: pulsar.LZ4,
	})
	if err != nil {
		logging.Printf("[handler] embed fanout: could not create jobs producer on %s: %v — fanout disabled",
			h.cfg.PulsarEmbedJobsTopic, err)
		return
	}

	disp, err := embed.NewResultDispatcher(pulsarClient, h.cfg.WorkerInstanceID)
	if err != nil {
		prod.Close()
		logging.Printf("[handler] embed fanout: could not create result dispatcher for worker %s: %v — fanout disabled",
			h.cfg.WorkerInstanceID, err)
		return
	}

	h.embedProducer = prod
	h.resultDispatcher = disp

	// Run the dispatcher in the background for the process lifetime.
	go disp.Run(context.Background())
	logging.Printf("[handler] embed fanout enabled: worker=%s jobs_topic=%s",
		h.cfg.WorkerInstanceID, h.cfg.PulsarEmbedJobsTopic)
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

	// Coverage check: determine which tags have vectors for the primary embedding model.
	// Tags without coverage are excluded from Qdrant search; pending ones trigger async ingest.
	primaryEmbeddingModel := ""
	if len(embeddingModels) > 0 {
		primaryEmbeddingModel = embeddingModels[0]
	}
	if req.EmbeddingModel != "" {
		primaryEmbeddingModel = req.EmbeddingModel
	}

	var missingEmbeddings []map[string]interface{}
	searchableTags := tags // default: search all tags

	if len(req.Tags) > 0 && primaryEmbeddingModel != "" {
		coverage := h.checkEmbeddingCoverage(ctx, req.Tags, primaryEmbeddingModel)
		if coverage != nil {
			var filteredTagIDs []int64
			for _, entry := range coverage {
				switch entry.Status {
				case "complete":
					// Include in search — no advisory needed.
					filteredTagIDs = append(filteredTagIDs, entry.TagID)
				case "stale":
					// Include in search (vectors exist) — add to advisory.
					filteredTagIDs = append(filteredTagIDs, entry.TagID)
					missingEmbeddings = append(missingEmbeddings, map[string]interface{}{
						"tag_id": entry.TagID,
						"tag":    entry.Tag,
						"model":  primaryEmbeddingModel,
						"status": "stale",
					})
				case "pending":
					// No vectors — trigger async ingest and exclude from search.
					h.triggerAsyncIngest(entry.TagID, entry.Tag, primaryEmbeddingModel)
					missingEmbeddings = append(missingEmbeddings, map[string]interface{}{
						"tag_id": entry.TagID,
						"tag":    entry.Tag,
						"model":  primaryEmbeddingModel,
						"status": "pending",
					})
				case "building":
					// Ingest already in progress — exclude from search and advise.
					missingEmbeddings = append(missingEmbeddings, map[string]interface{}{
						"tag_id": entry.TagID,
						"tag":    entry.Tag,
						"model":  primaryEmbeddingModel,
						"status": "building",
					})
				}
			}
			searchableTags = filteredTagIDs
			logging.Printf("[%s][SID:%d] coverage check: searchable=%v missing=%d", req.Id, req.SessionId, searchableTags, len(missingEmbeddings))
		}
	}

	var allRawResults []interface{}
	var retrievalProvenance []map[string]interface{}

	for idx, embeddingModel := range embeddingModels {
		embedder, err := h.registry.GetPlanner(embeddingModel)
		if err != nil {
			logging.Printf("[%s][SID:%d] Embedding model resolution error for %q: %v", req.Id, req.SessionId, embeddingModel, err)
			continue
		}

		logging.Printf("[%s][SID:%d] retrieval pass model=%q tags=%v sub_queries=%d", req.Id, req.SessionId, embeddingModel, searchableTags, len(subQueries))
		contextFiles, err := h.fetchContextFiles(ctx, req, embeddingModel)
		if err != nil {
			logging.Printf("[%s][SID:%d] Context file discovery failed for %q: %v", req.Id, req.SessionId, embeddingModel, err)
		}

		modelResults, hydrated, hydrationNotes, err := h.searchWithEmbeddingModel(ctx, req, embeddingModel, embedder, subQueries, searchableTags, contextFiles)
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
	chunkGroups := h.newChunkProcessor().chunkResultsDetailed(ctx, allRawResults)
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
	if len(missingEmbeddings) > 0 {
		metadataMap["missing_embeddings"] = missingEmbeddings
	}
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

	h.msg.SendStatus(ctx, req.Id, req.SessionId, "REFINING_PLAN", fmt.Sprintf("Refining plan with %d context chunks", len(allChunks)))
	refinedPlan, _, err := planner.Plan(ctx, req.Prompt, flattenChunkContexts(allChunks), history)
	if err != nil {
		logging.Printf("[%s][SID:%d] Refined planning with chunk context failed: %v", req.Id, req.SessionId, err)
	} else if refinedPlan != nil {
		metadataMap["planner_task"] = refinedPlan.ToMap()
		metadataMap["planner_trace"] = refinedPlan.Trace.ToMap()
		metadataMap["plan_step_contexts"] = buildPlanStepContexts(refinedPlan, chunkGroups, req.Prompt)
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

// unitExecResult holds the outcome of processing a single execution unit.
type unitExecResult struct {
	content        string
	hasSubstantial bool
	metrics        *contracts.ExecutionMetrics
	nextSeq        int
	inConversation bool
}

// processExecutionUnit runs the planner-refinement and executor for one unit,
// returning the accumulated content, metrics, and updated streaming state.
func (h *Handler) processExecutionUnit(
	ctx context.Context,
	unit executionUnit,
	executor models.Executor,
	planner models.Planner,
	req *contracts.InternalRequest,
	modelID string,
	seq int,
	inConversation bool,
	history []interface{},
) (unitExecResult, error) {
	res := unitExecResult{nextSeq: seq, inConversation: inConversation}

	if planner != nil {
		refinedPlan, _, err := planner.Plan(ctx, unit.Prompt, unit.Contexts, history)
		if err == nil && refinedPlan != nil && len(refinedPlan.SearchQueries) > 0 && h.cfg.StreamIntermediate {
			planningText := fmt.Sprintf("Refined sub-queries for %s:", unit.Label)
			for _, sq := range refinedPlan.SearchQueries {
				planningText += fmt.Sprintf("\n- %s", sq)
			}
			h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, planningText)
		} else if err != nil && ollama.IsMissingModelError(err) {
			h.msg.SendError(ctx, req.Id, fmt.Sprintf("Planner model unavailable in Ollama: %s", req.PlannerModel), false)
			return res, fmt.Errorf("planner model unavailable: %w", err)
		}
	}

	if req.Stream {
		stream, metaCh, errCh := executor.ExecuteStream(ctx, unit.Prompt, unit.Contexts, history)
		var chunkBuffer string
		var chunkCount int

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
				res.content += c
				chunkBuffer += c
				chunkCount++
				res.inConversation = true

				if chunkCount >= h.cfg.StreamAccumulationCount {
					h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, chunkBuffer, res.nextSeq, false, modelID, res.inConversation, nil)
					res.nextSeq++
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
				res.metrics = mergeExecMetrics(res.metrics, h.mapMetrics(rawMeta, modelID))
			case err, ok := <-errCh:
				if !ok {
					errCh = nil
					if stream == nil && metaCh == nil {
						loop = false
					}
					continue
				}
				if err != nil {
					logging.Printf("[%s] Execution stream failed on %s: %v", req.Id, unit.Label, err)
					h.msg.SendError(ctx, req.Id, fmt.Sprintf("%s failed: %v", unit.Label, err), res.inConversation)
					if ollama.IsMissingModelError(err) {
						return res, fmt.Errorf("executor stream model unavailable: %w", err)
					}
				}
			case <-ctx.Done():
				return res, ctx.Err()
			}
		}
		if chunkBuffer != "" {
			h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, chunkBuffer, res.nextSeq, false, modelID, res.inConversation, nil)
			res.nextSeq++
		}
		if !executor.IsInsufficientContext(res.content) {
			res.hasSubstantial = true
		}
	} else {
		content, rawMeta, err := executor.Execute(ctx, unit.Prompt, unit.Contexts, history)
		if err != nil {
			logging.Printf("[%s] Execution failed on %s: %v", req.Id, unit.Label, err)
			h.msg.SendError(ctx, req.Id, fmt.Sprintf("%s failed: %v", unit.Label, err), res.inConversation)
			if ollama.IsMissingModelError(err) {
				return res, fmt.Errorf("executor model unavailable: %w", err)
			}
			return res, nil // non-fatal: continue to next unit
		}
		res.content = content
		res.inConversation = true
		if !executor.IsInsufficientContext(content) {
			res.hasSubstantial = true
		}
		res.metrics = mergeExecMetrics(res.metrics, h.mapMetrics(rawMeta, modelID))
		if h.cfg.StreamIntermediate && req.Stream {
			h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, content, res.nextSeq, false, modelID, res.inConversation, nil)
			res.nextSeq++
		}
	}

	return res, nil
}

func mergeExecMetrics(dst, src *contracts.ExecutionMetrics) *contracts.ExecutionMetrics {
	if src == nil {
		return dst
	}
	if dst == nil {
		return src
	}
	dst.PromptTokens += src.PromptTokens
	dst.CompletionTokens += src.CompletionTokens
	dst.TotalDurationUsec += src.TotalDurationUsec
	return dst
}

type execDecision int

const (
	execSendResult execDecision = iota
	execPaginate
	execReplan
)

// handleExecDecision is a pure function that determines what to do after
// processing a batch of execution units.
func handleExecDecision(
	isInsufficient, hasSubstantial bool,
	budget, recursionCount, totalChunks float64,
	unitsEnd, unitsLen, maxTotal, maxRecursion int,
) execDecision {
	if unitsEnd < unitsLen && !hasSubstantial {
		if totalChunks >= float64(maxTotal) || budget <= 0 {
			return execSendResult
		}
		return execPaginate
	}
	if isInsufficient && !hasSubstantial && budget >= 1.0 {
		if recursionCount >= float64(maxRecursion) {
			return execSendResult
		}
		return execReplan
	}
	return execSendResult
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
			if actualIndex == 0 {
				h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, "", 0, false, modelID, false, metadata)
			}
		}

		result, err := h.processExecutionUnit(ctx, unit, executor, planner, req, modelID, seq, inConversation, history)
		if err != nil {
			if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
				h.msg.SendCompletion(ctx, req.Id, req.SessionId, startTime, modelID, "FAILED", nil)
				return dlq.TransientFailure, err
			}
			return dlq.PermanentFailure, err
		}
		fullAccumulatedResult += result.content
		seq = result.nextSeq
		inConversation = result.inConversation
		if result.hasSubstantial {
			hasSubstantialResult = true
		}
		finalMetrics = mergeExecMetrics(finalMetrics, result.metrics)
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

	decision := handleExecDecision(isInsufficient, hasSubstantialResult, budget, recursionCount, totalChunks,
		end, len(executionUnits), h.cfg.MaxTotalChunks, h.cfg.MaxRecursionCount)

	switch decision {
	case execPaginate:
		logging.Printf("[%s][SID:%d] No substantial result in units %d-%d, paginating to next batch", req.Id, req.SessionId, offset+1, end)
		metadata["chunk_offset"] = float64(end)
		metadata["recursion_budget"] = budget - 0.1
		req.Metadata = contracts.ToStruct(metadata)
		marshaller := protojson.MarshalOptions{UseProtoNames: true}
		payload, err := marshaller.Marshal(req)
		if err != nil {
			h.msg.SendError(ctx, req.Id, "Internal pipeline routing error: failed to continue pagination", inConversation)
			return dlq.TransientFailure, fmt.Errorf("marshal for exec pagination [%s]: %w", req.Id, err)
		}
		if _, sendErr := h.msg.Producers.Exec.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); sendErr != nil {
			h.msg.SendError(ctx, req.Id, "Internal pipeline routing error: failed to continue pagination", inConversation)
			return dlq.TransientFailure, fmt.Errorf("send to exec for pagination [%s]: %w", req.Id, sendErr)
		}
		return dlq.Success, nil

	case execReplan:
		logging.Printf("[%s][SID:%d] Context insufficient after all units, triggering re-plan", req.Id, req.SessionId)
		metadata["recursion_budget"] = budget - 1.0
		metadata["recursion_count"] = recursionCount + 1
		metadata["chunk_offset"] = float64(0)
		req.Metadata = contracts.ToStruct(metadata)
		marshaller := protojson.MarshalOptions{UseProtoNames: true}
		payload, err := marshaller.Marshal(req)
		if err != nil {
			h.msg.SendError(ctx, req.Id, "Internal pipeline routing error: failed to trigger re-plan", inConversation)
			return dlq.TransientFailure, fmt.Errorf("marshal for re-plan [%s]: %w", req.Id, err)
		}
		if _, sendErr := h.msg.Producers.Plan.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); sendErr != nil {
			h.msg.SendError(ctx, req.Id, "Internal pipeline routing error: failed to trigger re-plan", inConversation)
			return dlq.TransientFailure, fmt.Errorf("send to plan for re-plan [%s]: %w", req.Id, sendErr)
		}
		return dlq.Success, nil
	}

	if end < len(executionUnits) && hasSubstantialResult {
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

