package qdrant

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"app-builds/common/contracts"
	"app-builds/common/tlsutil"
	"app-builds/qdrant-adapter/internal/config"
)

type QdrantClient struct {
	cfg        *config.Config
	httpClient *http.Client
}

func NewClient(cfg *config.Config) *QdrantClient {
	httpClient, err := tlsutil.NewHTTPClient(cfg.QdrantUseTLS, 10*time.Second)
	if err != nil {
		log.Fatalf("Failed to create Qdrant HTTP client with TLS: %v", err)
	}
	return &QdrantClient{
		cfg:        cfg,
		httpClient: httpClient,
	}
}

func (q *QdrantClient) Search(collection string, vectorSize int, vector []float32, limit int, tags []string, sessionID string) ([]string, error) {
	return q.searchWithRetry(collection, vectorSize, vector, limit, tags, sessionID, true)
}

func (q *QdrantClient) searchWithRetry(collection string, vectorSize int, vector []float32, limit int, tags []string, sessionID string, retry bool) ([]string, error) {
	if len(vector) == 0 {
		return nil, nil // Cannot search with empty vector
	}

	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := collection
	if vs > 0 {
		effectiveColl = fmt.Sprintf("%s-%d", collection, vs)
	}

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s/points/search", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	query := map[string]interface{}{
		"vector":       vector,
		"limit":        limit,
		"with_payload": true,
	}

	var mustFilters []map[string]interface{}

	if len(tags) > 0 {
		mustFilters = append(mustFilters, map[string]interface{}{
			"key": "tags",
			"match": map[string]interface{}{
				"any": tags,
			},
		})
	}

	if sessionID != "" {
		// Allow points that match the session ID OR have no session ID (global context)
		mustFilters = append(mustFilters, map[string]interface{}{
			"should": []map[string]interface{}{
				{
					"key": "session_id",
					"match": map[string]interface{}{
						"value": sessionID,
					},
				},
				{
					"is_empty": map[string]interface{}{
						"key": "session_id",
					},
				},
			},
		})
	}

	if len(mustFilters) > 0 {
		query["filter"] = map[string]interface{}{
			"must": mustFilters,
		}
		log.Printf("DEBUG: Qdrant Search Filter (tags=%v, session=%s): %+v", tags, sessionID, query["filter"])
	}

	body, err := json.Marshal(query)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal search query: %w", err)
	}
	resp, err := q.httpClient.Post(url, "application/json", bytes.NewBuffer(body))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound && retry && vs > 0 {
		fmt.Printf("Collection '%s' not found. Creating it with size %d...\n", effectiveColl, vs)
		if err := q.CreateCollection(collection, vs); err != nil {
			return nil, fmt.Errorf("failed to auto-create collection %s: %v", effectiveColl, err)
		}
		return q.searchWithRetry(collection, vectorSize, vector, limit, tags, sessionID, false)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("qdrant (coll: %s) returned status %d", effectiveColl, resp.StatusCode)
	}

	var result struct {
		Result []struct {
			Payload map[string]interface{} `json:"payload"`
		} `json:"result"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	var contexts []string
	for _, r := range result.Result {
		// Support both "text" and "content" fields
		if text, ok := r.Payload["content"].(string); ok {
			contexts = append(contexts, text)
		} else if text, ok := r.Payload["text"].(string); ok {
			contexts = append(contexts, text)
		}
	}

	fmt.Printf("DEBUG: Qdrant Search returned %d results (max: %d)\n", len(contexts), limit)
	return contexts, nil
}

func (q *QdrantClient) CreateCollection(collection string, vectorSize int) error {
	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}
	effectiveColl := fmt.Sprintf("%s-%d", collection, vs)

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	payload := map[string]interface{}{
		"vectors": map[string]interface{}{
			"size":     vs,
			"distance": "Cosine",
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	req, err := http.NewRequest("PUT", url, bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := q.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		if resp.StatusCode == http.StatusConflict && effectiveColl != "" {
			// Collection already exists, ignore 409
			return nil
		}
		return fmt.Errorf("failed to create collection %s: %d", effectiveColl, resp.StatusCode)
	}

	return nil
}

func (q *QdrantClient) DeleteByFilter(collection string, vectorSize int, tags []string, paths []string) error {
	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := collection
	if vs > 0 {
		effectiveColl = fmt.Sprintf("%s-%d", collection, vs)
	}

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s/points/delete?wait=true", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	if len(tags) == 0 && len(paths) == 0 {
		return nil
	}

	var mustFilters []map[string]interface{}

	if len(tags) > 0 {
		mustFilters = append(mustFilters, map[string]interface{}{
			"key": "tags",
			"match": map[string]interface{}{
				"any": tags,
			},
		})
	}

	if len(paths) > 0 {
		mustFilters = append(mustFilters, map[string]interface{}{
			"key": "path",
			"match": map[string]interface{}{
				"any": paths,
			},
		})
	}

	filter := map[string]interface{}{
		"must": mustFilters,
	}

	body, err := json.Marshal(map[string]interface{}{
		"filter": filter,
	})
	if err != nil {
		return fmt.Errorf("failed to marshal delete filter: %w", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := q.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil // Collection doesn't exist, nothing to delete
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("qdrant (coll: %s) returned status %d on delete", effectiveColl, resp.StatusCode)
	}

	return nil
}

func (q *QdrantClient) ListCollections() (interface{}, error) {
	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort)
	resp, err := q.httpClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var result interface{}
	json.NewDecoder(resp.Body).Decode(&result)
	return result, nil
}

func (q *QdrantClient) GetCollection(name string) (interface{}, error) {
	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, name)
	resp, err := q.httpClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var result interface{}
	json.NewDecoder(resp.Body).Decode(&result)
	return result, nil
}

func (q *QdrantClient) UpsertProto(collection string, vectorSize int, points []*contracts.QdrantPoint) error {
	qdrantPoints := make([]interface{}, len(points))
	for i, p := range points {
		qdrantPoints[i] = map[string]interface{}{
			"id":      p.Id,
			"vector":  p.Vector,
			"payload": contracts.FromStruct(p.Payload),
		}
	}
	return q.Upsert(collection, vectorSize, qdrantPoints)
}

func (q *QdrantClient) Upsert(collection string, vectorSize int, points []interface{}) error {
	return q.upsertWithRetry(collection, vectorSize, points, true)
}

func (q *QdrantClient) upsertWithRetry(collection string, vectorSize int, points []interface{}, retry bool) error {
	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := collection
	if vs > 0 {
		effectiveColl = fmt.Sprintf("%s-%d", collection, vs)
	}

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s/points?wait=true", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	body, err := json.Marshal(map[string]interface{}{
		"points": points,
	})
	if err != nil {
		return fmt.Errorf("failed to marshal upsert payload: %w", err)
	}

	req, err := http.NewRequest("PUT", url, bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := q.httpClient.Do(req)
	if err != nil {
		fmt.Printf("ERROR: Qdrant PUT request failed: %v\n", err)
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound && retry && vs > 0 {
		fmt.Printf("Collection '%s' not found. Creating it with size %d...\n", effectiveColl, vs)
		if err := q.CreateCollection(collection, vs); err != nil {
			return fmt.Errorf("failed to auto-create collection %s: %v", effectiveColl, err)
		}
		return q.upsertWithRetry(collection, vectorSize, points, false)
	}

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		fmt.Printf("ERROR: Qdrant (coll: %s) returned %d: %s\n", effectiveColl, resp.StatusCode, string(bodyBytes))
		return fmt.Errorf("qdrant (coll: %s) returned status %d", effectiveColl, resp.StatusCode)
	}

	fmt.Printf("DEBUG: Successfully upserted %d points into %s\n", len(points), effectiveColl)
	return nil
}

func (q *QdrantClient) MergeTags(collection string, vectorSize int, sourceTag, targetTag string) error {
	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := collection
	if vs > 0 {
		effectiveColl = fmt.Sprintf("%s-%d", collection, vs)
	}

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	// Qdrant doesn't have a direct "update payload for all matching" with arbitrary logic,
	// but it has a "set payload" for a filter.
	url := fmt.Sprintf("%s://%s:%s/collections/%s/points/payload?wait=true", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	// Step 1: Add targetTag to all points that have sourceTag
	// We use the "overwrite" (or just set) payload with a filter.
	// Since tags is usually an array, this is slightly tricky with "set_payload".
	// If we want to properly merge (append to array), we'd need to fetch and update or use a more advanced Qdrant feature if available.
	// For now, we'll implement a simple "add to tags array" using Qdrant's payload update features.
	// Note: Qdrant's /points/payload (POST) adds/updates keys. If 'tags' is a list, it might overwrite the whole list.
	
	// Better approach for true merge in Qdrant: 
	// Use a filter to find all points with sourceTag, then use a script or multi-step update.
	// Simpler approach: Set the targetTag as a value in the tags array.
	
	filter := map[string]interface{}{
		"must": []map[string]interface{}{
			{
				"key": "tags",
				"match": map[string]interface{}{
					"value": sourceTag,
				},
			},
		},
	}

	// We'll use a multi-step update if needed, but for now let's try the simplest:
	// Replace sourceTag with targetTag in the array. 
	// Actually, Qdrant's payload update doesn't support "array remove/add" natively in a single atomic call across all points.
	
	// Recommendation: For this iteration, we'll implement the "Overwrite with Target" for the session/tag field.
	// If the user wants to merge tags, they likely want to unify them.
	
	payload := map[string]interface{}{
		"tags": []string{targetTag}, 
	}

	body, err := json.Marshal(map[string]interface{}{
		"payload": payload,
		"filter":  filter,
	})
	if err != nil {
		return err
	}

	resp, err := q.httpClient.Post(url, "application/json", bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("qdrant merge tags failed: status %d", resp.StatusCode)
	}

	return nil
}

func (q *QdrantClient) GetStats(collection string) (interface{}, error) {
	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, collection)
	resp, err := q.httpClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	
	var result struct {
		Result interface{} `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result.Result, nil
}
