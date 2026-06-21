package pipeline

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"unicode"

	"app-builds/common/contracts"
	"app-builds/common/logging"
	"app-builds/rag-worker/internal/config"
)

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

// chunkProcessor encapsulates the vector-result chunking and file-reassembly
// logic, keeping it independent of the full Handler.
type chunkProcessor struct {
	cfg      *config.Config
	searcher QdrantSearcher
}

// newChunkProcessor creates a chunkProcessor from the Handler's config and searcher.
func (h *Handler) newChunkProcessor() *chunkProcessor {
	return &chunkProcessor{cfg: h.cfg, searcher: h.searcher}
}

// chunkResults is a Handler-level wrapper kept for backward compatibility
// (e.g. tests that call it directly on *Handler).
func (h *Handler) chunkResults(ctx context.Context, rawResults []interface{}) [][]string {
	return h.newChunkProcessor().chunkResults(ctx, rawResults)
}

func (cp *chunkProcessor) chunkResults(ctx context.Context, rawResults []interface{}) [][]string {
	return chunkGroupTexts(cp.chunkResultsDetailed(ctx, rawResults))
}

func (cp *chunkProcessor) chunkResultsDetailed(ctx context.Context, rawResults []interface{}) []chunkGroupDetail {
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
			fullFileChunks, err := cp.searcher.RetrieveByPaths(ctx, embeddingModel, pathList)
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
	limit := cp.cfg.ChunkVectorLimit
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

func buildPlanStepContexts(plan *contracts.PlannerTaskPlan, groups []chunkGroupDetail, originalPrompt string) []map[string]interface{} {
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

		// Always use the original user question as the executor prompt so the
		// extraction instruction ("return the exact answer") is never replaced by
		// the planner's decomposed step objective. Step objectives are useful for
		// scoring/ranking context groups but must not reach the executor model.
		stepPrompt := strings.TrimSpace(originalPrompt)
		if stepPrompt == "" {
			stepPrompt = strings.TrimSpace(plan.Objective)
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
