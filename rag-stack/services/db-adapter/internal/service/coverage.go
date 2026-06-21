package service

import (
	"encoding/json"
	"net/http"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/tag"
	"app-builds/common/ent/tagembeddingcoverage"
	"app-builds/common/logging"
)

// CoverageService handles embedding coverage queries.
type CoverageService struct {
	client *ent.Client
}

func NewCoverageService(client *ent.Client) *CoverageService {
	return &CoverageService{client: client}
}

type coverageRequest struct {
	TagIDs         []int64 `json:"tag_ids"`
	EmbeddingModel string  `json:"embedding_model"`
}

// CoverageEntry is the per-tag coverage result returned to callers.
type CoverageEntry struct {
	TagID          int64      `json:"tag_id"`
	Tag            string     `json:"tag"`
	Status         string     `json:"status"`
	VectorCount    int64      `json:"vector_count"`
	FileCount      int        `json:"file_count"`
	LastEmbeddedAt *time.Time `json:"last_embedded_at"`
}

// GetCoverage handles POST /embeddings/coverage.
//
// For each requested tag_id + embedding_model combination it returns the
// coverage status. Tags with no row in tag_embedding_coverage are synthesised
// as "pending" with zero counts.
func (s *CoverageService) GetCoverage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req coverageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body: "+err.Error(), http.StatusBadRequest)
		return
	}
	if len(req.TagIDs) == 0 || req.EmbeddingModel == "" {
		http.Error(w, "tag_ids and embedding_model are required", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	// Fetch coverage rows that exist for the requested tag_ids + model.
	rows, err := s.client.TagEmbeddingCoverage.Query().
		Where(
			tagembeddingcoverage.TagIDIn(req.TagIDs...),
			tagembeddingcoverage.EmbeddingModelEQ(req.EmbeddingModel),
		).
		WithTag().
		All(ctx)
	if err != nil {
		logging.Error("coverage query failed", "error", err)
		http.Error(w, "database error", http.StatusInternalServerError)
		return
	}

	// Index existing rows by tag_id for O(1) lookup.
	found := make(map[int64]*ent.TagEmbeddingCoverage, len(rows))
	for _, row := range rows {
		found[row.TagID] = row
	}

	// For tag_ids with no coverage row we need the tag name — fetch them.
	var missingIDs []int64
	for _, id := range req.TagIDs {
		if _, ok := found[id]; !ok {
			missingIDs = append(missingIDs, id)
		}
	}
	tagNames := make(map[int64]string)
	if len(missingIDs) > 0 {
		tags, err := s.client.Tag.Query().
			Where(tag.IDIn(missingIDs...)).
			All(ctx)
		if err != nil {
			logging.Warn("failed to fetch tag names for missing coverage", "error", err)
		}
		for _, t := range tags {
			tagNames[t.ID] = t.Name
		}
	}

	// Build response, preserving request order.
	results := make([]CoverageEntry, 0, len(req.TagIDs))
	for _, id := range req.TagIDs {
		if row, ok := found[id]; ok {
			entry := CoverageEntry{
				TagID:       row.TagID,
				Status:      row.Status,
				VectorCount: row.VectorCount,
				FileCount:   row.FileCount,
			}
			if row.Edges.Tag != nil {
				entry.Tag = row.Edges.Tag.Name
			}
			if row.LastEmbeddedAt != nil {
				t := *row.LastEmbeddedAt
				entry.LastEmbeddedAt = &t
			}
			results = append(results, entry)
		} else {
			// Synthesise pending entry.
			results = append(results, CoverageEntry{
				TagID:       id,
				Tag:         tagNames[id],
				Status:      "pending",
				VectorCount: 0,
				FileCount:   0,
			})
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(results)
}
