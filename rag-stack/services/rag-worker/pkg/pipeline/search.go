package pipeline

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"

	"app-builds/common/contracts"
	"app-builds/common/logging"
	"app-builds/rag-worker/internal/models"
	"app-builds/rag-worker/internal/ollama"
	"app-builds/rag-worker/pkg/embed"
)

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

// embedQueryResult pairs an embedding vector with its sub-query index.
type embedQueryResult struct {
	index  int
	vector []float32
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

	if h.cfg.EmbedFanoutEnabled && h.embedProducer != nil && h.resultDispatcher != nil {
		fanoutResults, err := h.embedFanout(ctx, req.Id, embeddingModel, subQueries)
		if err != nil {
			logging.Printf("[%s][SID:%d] embed fanout failed model=%q: %v — falling back to serial HTTP embedding",
				req.Id, req.SessionId, embeddingModel, err)
			// Fall through to serial path below.
		} else {
			for _, fr := range fanoutResults {
				sq := subQueries[fr.index]
				vs := len(fr.vector)
				logging.Printf("[%s][SID:%d] qdrant search (fanout) model=%q vector_dims=%d tags=%v limit=%d query=%q",
					req.Id, req.SessionId, embeddingModel, vs, tags, h.cfg.QdrantSearchLimit, sq)
				results, err := h.searcher.Search(ctx, embeddingModel, fr.vector, tags, req.SessionId, req.IncludeGlobal, h.cfg.QdrantSearchLimit)
				if err != nil {
					if isMissingCollectionError(err) {
						missingCollection = true
						continue
					}
					logging.Printf("[%s][SID:%d] Qdrant search failed (fanout) model=%s query=%q dims=%d: %v",
						req.Id, req.SessionId, embeddingModel, sq, vs, err)
					continue
				}
				logging.Printf("[%s][SID:%d] Retrieved %d items (fanout) model=%s query=%q", req.Id, req.SessionId, len(results), embeddingModel, sq)
				allRawResults = append(allRawResults, results...)
			}
			return allRawResults, missingCollection, nil
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

		resp, err := h.hydrationClient.Do(httpReq)
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

// embedFanout fans out embedding calls for all subQueries to the Pulsar embed/jobs
// topic and gathers results via the per-worker ResultDispatcher.
// Returns results in sub-query index order. On any error the caller falls back to
// the serial HTTP path and logs the reason.
//
// Only callable when h.embedProducer and h.resultDispatcher are non-nil.
func (h *Handler) embedFanout(
	ctx context.Context,
	reqID string,
	embeddingModel string,
	subQueries []string,
) ([]embedQueryResult, error) {
	n := len(subQueries)

	// Register BEFORE publishing to avoid a race where a fast gateway publishes
	// results before the dispatcher is ready to receive them.
	resultCh := h.resultDispatcher.Register(reqID, n)
	defer h.resultDispatcher.Deregister(reqID)

	deadline := time.Now().Add(h.cfg.EmbedFanoutTimeout)

	for i, sq := range subQueries {
		job := embed.EmbedJob{
			RequestID:        reqID,
			SubQueryIndex:    i,
			SubQuery:         sq,
			EmbeddingModel:   embeddingModel,
			WorkerInstanceID: h.cfg.WorkerInstanceID,
			DeadlineUnix:     deadline.Unix(),
		}
		payload, _ := json.Marshal(job)
		if _, err := h.embedProducer.Send(ctx, &pulsar.ProducerMessage{
			Payload: payload,
			Properties: map[string]string{
				"request_id": reqID,
				"worker_id":  h.cfg.WorkerInstanceID,
				"model":      embeddingModel,
			},
		}); err != nil {
			return nil, fmt.Errorf("embed fanout: publish sub-query %d: %w", i, err)
		}
	}
	logging.Printf("[%s] embed fanout: published %d jobs model=%s timeout=%s",
		reqID, n, embeddingModel, h.cfg.EmbedFanoutTimeout)

	// Gather results with deadline.
	results := make([]embedQueryResult, n)
	gathered := 0
	gatherCtx, cancel := context.WithDeadline(ctx, deadline)
	defer cancel()

	for gathered < n {
		select {
		case r := <-resultCh:
			if r.Error != "" {
				return nil, fmt.Errorf("embed fanout: sub-query %d failed on gateway %s: %s",
					r.SubQueryIndex, r.GatewayID, r.Error)
			}
			if r.SubQueryIndex < 0 || r.SubQueryIndex >= n {
				logging.Printf("[%s] embed fanout: unexpected sub_query_index %d (expected 0-%d) — skipping",
					reqID, r.SubQueryIndex, n-1)
				continue
			}
			results[r.SubQueryIndex] = embedQueryResult{
				index:  r.SubQueryIndex,
				vector: r.Vector,
			}
			gathered++
		case <-gatherCtx.Done():
			return nil, fmt.Errorf("embed fanout: timeout waiting for results (%d/%d received) after %s",
				gathered, n, h.cfg.EmbedFanoutTimeout)
		}
	}

	logging.Printf("[%s] embed fanout: gathered %d/%d results model=%s", reqID, gathered, n, embeddingModel)
	return results, nil
}

func isMissingCollectionError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "collection not found") || strings.Contains(msg, "status 404")
}
