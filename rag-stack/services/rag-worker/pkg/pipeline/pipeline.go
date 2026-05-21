package pipeline

import (
	"context"
	"fmt"
	"sort"
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
	Search(ctx context.Context, vector []float32, tags []int64, sessionID int64, includeGlobal bool, limit int) ([]interface{}, error)
	RetrieveByPaths(ctx context.Context, paths []string) ([]interface{}, error)
}

type MemoryClient interface {
	Retrieve(ctx context.Context, sessionID int64, tags []int64, query string) (*contracts.MemoryPack, error)
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
	cfg          *config.Config
	msg          *messaging.Client
	registry     ModelRegistry
	searcher     QdrantSearcher
	memoryClient MemoryClient
}

// NewHandler creates a new pipeline stage handler.
func NewHandler(cfg *config.Config, msg *messaging.Client, registry ModelRegistry, searcher QdrantSearcher, mem MemoryClient) *Handler {
	return &Handler{
		cfg:          cfg,
		msg:          msg,
		registry:     registry,
		searcher:     searcher,
		memoryClient: mem,
	}
}

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

	// Fetch Memory (History + Behavioral Rules) for Planning Governance (Iteration 9)
	historyPack, err := h.memoryClient.Retrieve(ctx, req.SessionId, req.Tags, req.Prompt)
	if err != nil {
		logging.Printf("[%s][SID:%d] Memory retrieval failed in planning: %v", req.Id, req.SessionId, err)
	}

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

	// Filter behavioral rules by detected action type (Iteration 9)
	actionMap, _ := h.memoryClient.GetActionIdentifiers(ctx)
	actionType := behavioral.DetectActionType(req.Prompt, actionMap)
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
		plan.Trace.ContextSources = append(plan.Trace.ContextSources, "session-history")
	}
	subQueries := append([]string{}, plan.SearchQueries...)
	if len(subQueries) == 0 {
		subQueries = []string{req.Prompt}
		plan.SearchQueries = subQueries
	}

	planningText := formatPlannerPlan(plan)
	planningMetadata := map[string]interface{}{
		"planner_task":  plan.ToMap(),
		"planner_trace": plan.Trace.ToMap(),
		"sub_queries":   subQueries,
		"action_type":   string(actionType),
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

	if req.Stream {
		h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, "\n\u231B *Retrieving context from vector store*...")
	}
	h.msg.SendStatus(ctx, req.Id, req.SessionId, "RETRIEVING_CONTEXT", fmt.Sprintf("Executing %d sub-queries", len(subQueries)))

	modelID := req.PlannerModel
	if modelID == "" {
		modelID = h.cfg.PlannerModel
	}

	planner, err := h.registry.GetPlanner(modelID)
	if err != nil {
		logging.Printf("[%s][SID:%d] Planner resolution error in search: %v", req.Id, req.SessionId, err)
		h.msg.SendError(ctx, req.Id, fmt.Sprintf("Unsupported planner model for embeddings: %s", modelID), false)
		return dlq.PermanentFailure, fmt.Errorf("planner resolution: %w", err)
	}

	tags := req.Tags
	var allRawResults []interface{}

	// 1. Tag-only search (to ensure all info under a tag is retrieved)
	if len(tags) > 0 {
		h.msg.SendStatus(ctx, req.Id, req.SessionId, "RETRIEVING_CONTEXT", "Retrieving all items for tags")
		tagResults, err := h.searcher.Search(ctx, nil, tags, req.SessionId, req.IncludeGlobal, h.cfg.QdrantRetrievalLimit)
		if err == nil {
			allRawResults = append(allRawResults, tagResults...)
		}
	}

	// 2. Vector search for each sub-query
	for _, sq := range subQueries {
		vector, err := planner.GetEmbeddings(ctx, sq)
		if err != nil {
			logging.Printf("[%s][SID:%d] Failed to get embeddings for sub-query '%s': %v", req.Id, req.SessionId, sq, err)
			if ollama.IsMissingModelError(err) {
				h.msg.SendError(ctx, req.Id, fmt.Sprintf("Embedding model unavailable in Ollama: %s", modelID), false)
				return dlq.PermanentFailure, fmt.Errorf("embedding model unavailable: %w", err)
			}
			continue
		}
		vs := len(vector)
		logging.Printf("[%s][SID:%d] Searching Qdrant: collection=%s, dims=%d, tags=%v, global=%v, query='%s'", req.Id, req.SessionId, h.cfg.QdrantCollection, vs, tags, req.IncludeGlobal, sq)
		results, err := h.searcher.Search(ctx, vector, tags, req.SessionId, req.IncludeGlobal, h.cfg.QdrantSearchLimit)
		if err != nil {
			logging.Printf("[%s][SID:%d] Qdrant search failed for sub-query '%s' (dims: %d): %v", req.Id, req.SessionId, sq, vs, err)
			continue
		}
		logging.Printf("[%s][SID:%d] Retrieved %d items for sub-query '%s'", req.Id, req.SessionId, len(results), sq)
		allRawResults = append(allRawResults, results...)
	}

	// 3. Deduplicate and chunk context
	allChunks := h.chunkResults(ctx, allRawResults)

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
	metadataMap["contexts"] = flattenChunkContexts(allChunks)
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

func (h *Handler) chunkResults(ctx context.Context, rawResults []interface{}) [][]string {
	seenIDs := make(map[string]bool)
	type chunkInfo struct {
		content string
		index   int
	}
	files := make(map[string][]chunkInfo)
	var nonFileContexts []string
	pathsToFetch := make(map[string]bool)

	for _, it := range rawResults {
		m, ok := it.(map[string]interface{})
		if !ok {
			continue
		}

		// Deduplicate by Qdrant ID if available
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
		if path != "" {
			idxVal, _ := m["chunk"].(float64)
			idx := int(idxVal)
			files[path] = append(files[path], chunkInfo{content: content, index: idx})
			pathsToFetch[path] = true
		} else {
			nonFileContexts = append(nonFileContexts, content)
		}
	}

	// If we have paths, we should fetch ALL chunks for those paths to ensure "full files"
	if len(pathsToFetch) > 0 {
		pathList := make([]string, 0, len(pathsToFetch))
		for p := range pathsToFetch {
			pathList = append(pathList, p)
		}

		logging.Printf("Reassembling %d files from paths: %v", len(pathList), pathList)
		fullFileChunks, err := h.searcher.RetrieveByPaths(ctx, pathList)
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
				idxVal, _ := m["chunk"].(float64)
				idx := int(idxVal)

				if path != "" && content != "" {
					files[path] = append(files[path], chunkInfo{content: content, index: idx})
				}
			}
		} else {
			logging.Printf("Failed to fetch full file chunks: %v", err)
		}
	}

	var chunks [][]string
	currentChunk := []string{}
	currentChunkSize := 0
	limit := h.cfg.ChunkVectorLimit
	if limit <= 0 {
		limit = 50
	}

	// Sort paths
	pathKeys := make([]string, 0, len(files))
	for p := range files {
		pathKeys = append(pathKeys, p)
	}
	sort.Strings(pathKeys)

	// Process files
	for _, p := range pathKeys {
		fChunks := files[p]
		sort.Slice(fChunks, func(i, j int) bool {
			return fChunks[i].index < fChunks[j].index
		})

		numVectors := len(fChunks)
		if numVectors > limit {
			logging.Printf("ERROR: File %s too large (%d vectors), splitting into chunks of %d", p, numVectors, limit)
			// Close current chunk if not empty
			if len(currentChunk) > 0 {
				chunks = append(chunks, currentChunk)
				currentChunk = []string{}
				currentChunkSize = 0
			}
			// Split file
			for i := 0; i < numVectors; i += limit {
				end := i + limit
				if end > numVectors {
					end = numVectors
				}
				var sb strings.Builder
				sb.WriteString(fmt.Sprintf("--- File: %s (Part %d) ---\n", p, (i/limit)+1))
				for _, c := range fChunks[i:end] {
					sb.WriteString(c.content)
					if !strings.HasSuffix(c.content, "\n") {
						sb.WriteString("\n")
					}
				}
				if (end - i) == limit {
					chunks = append(chunks, []string{sb.String()})
				} else {
					// Last bit of the file starts the next currentChunk
					currentChunk = []string{sb.String()}
					currentChunkSize = (end - i)
				}
			}
		} else {
			if currentChunkSize+numVectors > limit {
				// New chunk
				if len(currentChunk) > 0 {
					chunks = append(chunks, currentChunk)
				}
				var sb strings.Builder
				sb.WriteString(fmt.Sprintf("--- File: %s ---\n", p))
				for _, c := range fChunks {
					sb.WriteString(c.content)
					if !strings.HasSuffix(c.content, "\n") {
						sb.WriteString("\n")
					}
				}
				currentChunk = []string{sb.String()}
				currentChunkSize = numVectors
			} else {
				// Append to current
				var sb strings.Builder
				sb.WriteString(fmt.Sprintf("--- File: %s ---\n", p))
				for _, c := range fChunks {
					sb.WriteString(c.content)
					if !strings.HasSuffix(c.content, "\n") {
						sb.WriteString("\n")
					}
				}
				currentChunk = append(currentChunk, sb.String())
				currentChunkSize += numVectors
			}
		}
	}

	// Process non-file contexts (each counts as 1 vector)
	for _, nfc := range nonFileContexts {
		if currentChunkSize+1 > limit {
			if len(currentChunk) > 0 {
				chunks = append(chunks, currentChunk)
			}
			currentChunk = []string{nfc}
			currentChunkSize = 1
		} else {
			currentChunk = append(currentChunk, nfc)
			currentChunkSize += 1
		}
	}

	if len(currentChunk) > 0 {
		chunks = append(chunks, currentChunk)
	}

	return chunks
}

func (h *Handler) handleExec(ctx context.Context, req *contracts.InternalRequest) (dlq.ProcessResult, error) {
	h.msg.SendStatus(ctx, req.Id, req.SessionId, "EXECUTING_TASK", "Generating response with specialized model")

	var history []interface{}
	metadata := contracts.FromStruct(req.Metadata)
	if hist, ok := metadata["history"].([]interface{}); ok {
		history = hist
	}

	// Get chunks from metadata
	var chunks [][]interface{}
	if c, ok := metadata["chunks"].([]interface{}); ok {
		for _, chunk := range c {
			if chunkList, ok := chunk.([]interface{}); ok {
				chunks = append(chunks, chunkList)
			}
		}
	}
	// Fallback to "contexts" (old format)
	if len(chunks) == 0 {
		if c, ok := metadata["contexts"].([]interface{}); ok {
			chunks = append(chunks, c)
		}
	}

	// Handle chunk pagination
	offset := 0
	if o, ok := metadata["chunk_offset"].(float64); ok {
		offset = int(o)
	}
	maxChunks := h.cfg.MaxChunksPerRecursion
	if maxChunks <= 0 {
		maxChunks = 10
	}

	end := offset + maxChunks
	if end > len(chunks) {
		end = len(chunks)
	}

	var chunksToProcess [][]interface{}
	if offset < len(chunks) {
		chunksToProcess = chunks[offset:end]
	}

	// Ensure at least one execution loop if no chunks are found and we are at start
	if len(chunksToProcess) == 0 && offset == 0 {
		chunksToProcess = append(chunksToProcess, []interface{}{})
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

	for i, chunk := range chunksToProcess {
		actualIndex := offset + i
		h.msg.SendStatus(ctx, req.Id, req.SessionId, "EXECUTING_TASK", fmt.Sprintf("Processing context chunk %d/%d (Total: %d)", actualIndex+1, end, len(chunks)))
		if req.Stream {
			h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, fmt.Sprintf("\n\u231B *Generating response (Context chunk %d/%d)*...", actualIndex+1, end))
		}

		// 1. Refine Plan with chunk context
		if planner != nil {
			refinedPlan, _, err := planner.Plan(ctx, req.Prompt, chunk, history)
			if err == nil && refinedPlan != nil && len(refinedPlan.SearchQueries) > 0 && h.cfg.StreamIntermediate {
				planningText := fmt.Sprintf("Refined sub-queries for chunk %d:\n", actualIndex+1)
				for _, sq := range refinedPlan.SearchQueries {
					planningText += fmt.Sprintf("- %s\n", sq)
				}
				h.msg.SendPlanningResponse(ctx, req.Id, req.SessionId, planningText)
			} else if err != nil && ollama.IsMissingModelError(err) {
				h.msg.SendError(ctx, req.Id, fmt.Sprintf("Planner model unavailable in Ollama: %s", plannerModelID), false)
				return dlq.PermanentFailure, fmt.Errorf("planner model unavailable: %w", err)
			}
		}

		// 2. Execute
		if req.Stream {
			if actualIndex == 0 {
				// Send Seq 0 with metadata only on first chunk of THIS recursion
				h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, "", 0, false, modelID, false, metadata)
			}

			stream, metaCh, errCh := executor.ExecuteStream(ctx, req.Prompt, chunk, history)
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
						logging.Printf("[%s] Execution stream failed on chunk %d: %v", req.Id, actualIndex+1, err)
						h.msg.SendError(ctx, req.Id, fmt.Sprintf("Chunk %d failed: %v", actualIndex+1, err), inConversation)
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
			fullAccumulatedResult += "\n"
			if !executor.IsInsufficientContext(currentChunkResult) {
				hasSubstantialResult = true
			}
		} else {
			res, rawMeta, err := executor.Execute(ctx, req.Prompt, chunk, history)
			if err != nil {
				logging.Printf("[%s] Execution failed on chunk %d: %v", req.Id, actualIndex+1, err)
				h.msg.SendError(ctx, req.Id, fmt.Sprintf("Chunk %d failed: %v", actualIndex+1, err), inConversation)
				if ollama.IsMissingModelError(err) {
					return dlq.PermanentFailure, fmt.Errorf("executor model unavailable: %w", err)
				}
				continue
			}
			fullAccumulatedResult += res + "\n"
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
				h.msg.SendStreamChunk(ctx, req.Id, req.SessionId, res+"\n", seq, false, modelID, inConversation, nil)
				seq++
			}
		}

		// If we found a substantial result and we are over some limit, maybe we could stop?
		// But let's process at least the current set of chunksToProcess.
	}

	// Record response size
	if responseSizeHist != nil {
		responseSizeHist.Record(ctx, int64(len(fullAccumulatedResult)), metric.WithAttributes(attribute.String("model", modelID), attribute.String("stage", "exec")))
	}

	// Final grounding and recursion check
	isInsufficient := executor.IsInsufficientContext(fullAccumulatedResult)
	budget, _ := metadata["recursion_budget"].(float64)
	recursionCount, _ := metadata["recursion_count"].(float64)
	totalChunks, _ := metadata["total_chunks_processed"].(float64)

	// Update total chunks processed
	totalChunks += float64(end - offset)
	metadata["total_chunks_processed"] = totalChunks

	logging.Printf("[%s][SID:%d] Exec Summary: Insufficient=%v, Substantial=%v, Budget=%v, Recursions=%v, TotalChunks=%v",
		req.Id, req.SessionId, isInsufficient, hasSubstantialResult, budget, recursionCount, totalChunks)

	// Decision Logic
	if end < len(chunks) && !hasSubstantialResult {
		// PAGINATION: Move to next batch of chunks within the same retrieval set
		if totalChunks >= float64(h.cfg.MaxTotalChunks) {
			logging.Printf("[%s][SID:%d] Max total chunks reached (%v), stopping pagination", req.Id, req.SessionId, totalChunks)
		} else if budget <= 0 {
			logging.Printf("[%s][SID:%d] Budget exhausted, stopping pagination", req.Id, req.SessionId)
		} else {
			logging.Printf("[%s][SID:%d] No substantial result in chunks %d-%d, paginating to next batch", req.Id, req.SessionId, offset+1, end)
			metadata["chunk_offset"] = float64(end)
			metadata["recursion_budget"] = budget - 0.1 // Small deduction for pagination
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
		// RECURSION: Trigger re-planning after exhausting all chunks
		if recursionCount >= float64(h.cfg.MaxRecursionCount) {
			logging.Printf("[%s][SID:%d] Max recursion count reached (%v), stopping", req.Id, req.SessionId, recursionCount)
		} else {
			logging.Printf("[%s][SID:%d] Context insufficient after all chunks, triggering re-plan", req.Id, req.SessionId)
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
	} else if end < len(chunks) && hasSubstantialResult {
		logging.Printf("[%s][SID:%d] Found substantial result, stopping chunk processing early at %d/%d", req.Id, req.SessionId, end, len(chunks))
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
