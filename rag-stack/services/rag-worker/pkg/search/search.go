package search

import (
	"context"
	"fmt"
	"log"
	"time"

	"app-builds/common/clients"
	"app-builds/common/contracts"
	"app-builds/rag-worker/internal/config"
)

// QdrantSearcher handles Qdrant search operations via direct HTTP calls.
type QdrantSearcher struct {
	cfg    *config.Config
	client *clients.QdrantHTTPClient
}

// NewQdrantSearcher creates a new Qdrant searcher that sends search requests
// via the given HTTP client.
func NewQdrantSearcher(cfg *config.Config, client *clients.QdrantHTTPClient) *QdrantSearcher {
	return &QdrantSearcher{
		cfg:    cfg,
		client: client,
	}
}

// Search sends a search request to Qdrant via HTTP and waits for the result.
func (s *QdrantSearcher) Search(ctx context.Context, vector []float32, tags []int64, sessionID int64, includeGlobal bool, limit int) ([]interface{}, error) {
	if len(vector) == 0 && len(tags) == 0 {
		log.Printf("DEBUG: Skipping Qdrant search for session %d - empty vector and no tags", sessionID)
		return nil, nil
	}

	effectiveLimit := limit
	if effectiveLimit <= 0 {
		effectiveLimit = s.cfg.QdrantSearchLimit
	}

	op := &contracts.QdrantOp{
		Id:            fmt.Sprintf("search-%d", time.Now().UnixNano()),
		Action:        "search",
		Collection:    s.cfg.QdrantCollection,
		VectorSize:    int32(len(vector)),
		Vector:        vector,
		Limit:         int32(effectiveLimit),
		Tags:          tags,
		SessionId:     sessionID,
		IncludeGlobal: includeGlobal,
	}

	resp, err := s.client.Search(ctx, op)
	if err != nil {
		return nil, fmt.Errorf("qdrant search failed: %w", err)
	}

	if resp.Error != "" {
		return nil, fmt.Errorf("qdrant search returned error: %s", resp.Error)
	}

	val := contracts.FromValue(resp.Result)
	res, ok := val.([]interface{})
	if !ok {
		return nil, fmt.Errorf("qdrant search result was not a list: %T", val)
	}

	log.Printf("[%s] Qdrant search returned %d items", resp.Id, len(res))
	return res, nil
}

// RetrieveByPaths fetches all points for the given paths.
func (s *QdrantSearcher) RetrieveByPaths(ctx context.Context, paths []string) ([]interface{}, error) {
	if len(paths) == 0 {
		return nil, nil
	}

	op := &contracts.QdrantOp{
		Id:         fmt.Sprintf("paths-%d", time.Now().UnixNano()),
		Action:     "retrieve_paths",
		Collection: s.cfg.QdrantCollection,
		Paths:      paths,
		Limit:      int32(1000), // Default limit for full files
	}

	// We use the search endpoint for now as it handles QdrantOp generically
	// but we should probably add a dedicated RetrieveByPaths method to the client if needed.
	// For now, executeOp in qdrant-adapter handles it.
	
	// I'll add a generic Do method to QdrantHTTPClient or just use Search if it just executes op.
	// Actually QdrantHTTPClient.Search calls doRequest("/search", op).
	// executeOp in adapter handles "retrieve_paths".
	
	resp, err := s.client.Search(ctx, op) // Uses /search endpoint which handles any action in executeOp
	if err != nil {
		return nil, fmt.Errorf("qdrant paths retrieval failed: %w", err)
	}

	if resp.Error != "" {
		return nil, fmt.Errorf("qdrant paths retrieval returned error: %s", resp.Error)
	}

	val := contracts.FromValue(resp.Result)
	res, ok := val.([]interface{})
	if !ok {
		return nil, fmt.Errorf("qdrant paths retrieval result was not a list: %T", val)
	}

	return res, nil
}
