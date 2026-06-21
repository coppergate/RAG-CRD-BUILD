package pipeline

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"app-builds/common/logging"
)

type coverageResult struct {
	TagID          int64      `json:"tag_id"`
	Tag            string     `json:"tag"`
	Status         string     `json:"status"`
	VectorCount    int64      `json:"vector_count"`
	FileCount      int        `json:"file_count"`
	LastEmbeddedAt *time.Time `json:"last_embedded_at"`
}

// checkEmbeddingCoverage queries the db-adapter for tag coverage status for the
// given embedding model. Returns nil slice on error (non-fatal: caller falls back
// to searching all tags).
func (h *Handler) checkEmbeddingCoverage(ctx context.Context, tagIDs []int64, embeddingModel string) []coverageResult {
	baseURL := strings.TrimRight(h.cfg.DBAdapterURL, "/")
	if baseURL == "" || len(tagIDs) == 0 || embeddingModel == "" {
		return nil
	}

	body, _ := json.Marshal(map[string]interface{}{
		"tag_ids":         tagIDs,
		"embedding_model": embeddingModel,
	})

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost,
		baseURL+"/embeddings/coverage", bytes.NewReader(body))
	if err != nil {
		logging.Printf("checkEmbeddingCoverage: failed to build request: %v", err)
		return nil
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := h.httpClient.Do(httpReq)
	if err != nil {
		logging.Printf("checkEmbeddingCoverage: HTTP error: %v", err)
		return nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		logging.Printf("checkEmbeddingCoverage: unexpected status %d", resp.StatusCode)
		return nil
	}

	var results []coverageResult
	if err := json.NewDecoder(resp.Body).Decode(&results); err != nil {
		logging.Printf("checkEmbeddingCoverage: decode error: %v", err)
		return nil
	}
	return results
}

// triggerAsyncIngest fires a fire-and-forget ingest request for the given tag
// and embedding model. The bucket is omitted; the ingest service will use its
// default BUCKET_NAME environment variable.
func (h *Handler) triggerAsyncIngest(tagID int64, tagName, embeddingModel string) {
	baseURL := strings.TrimRight(h.cfg.IngestionURL, "/")
	if baseURL == "" {
		return
	}
	go func() {
		body, _ := json.Marshal(map[string]interface{}{
			"tag_ids":         []int64{tagID},
			"tag_names":       []string{tagName},
			"embedding_model": embeddingModel,
		})
		req, err := http.NewRequest(http.MethodPost, baseURL+"/ingest", bytes.NewReader(body))
		if err != nil {
			logging.Printf("triggerAsyncIngest: build request error: %v", err)
			return
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := h.httpClient.Do(req)
		if err != nil {
			logging.Printf("triggerAsyncIngest tag_id=%d model=%q: HTTP error: %v", tagID, embeddingModel, err)
			return
		}
		resp.Body.Close()
		logging.Printf("triggerAsyncIngest tag_id=%d model=%q: status=%d", tagID, embeddingModel, resp.StatusCode)
	}()
}
