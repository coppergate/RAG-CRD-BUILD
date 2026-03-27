package qdrant

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

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

func (q *QdrantClient) Search(collection string, vectorSize int, vector []float32, limit int, tags []string) ([]string, error) {
	return q.searchWithRetry(collection, vectorSize, vector, limit, tags, true)
}

func (q *QdrantClient) searchWithRetry(collection string, vectorSize int, vector []float32, limit int, tags []string, retry bool) ([]string, error) {
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

	if len(tags) > 0 {
		query["filter"] = map[string]interface{}{
			"must": []map[string]interface{}{
				{
					"key": "tags",
					"match": map[string]interface{}{
						"any": tags,
					},
				},
			},
		}
		log.Printf("DEBUG: Qdrant Search Filter (tags=%v): %+v", tags, query["filter"])
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
		return q.searchWithRetry(collection, vectorSize, vector, limit, tags, false)
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
		if text, ok := r.Payload["text"].(string); ok {
			contexts = append(contexts, text)
		}
	}

	return contexts, nil
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
		return fmt.Errorf("qdrant (coll: %s) returned status %d", effectiveColl, resp.StatusCode)
	}

	return nil
}

func (q *QdrantClient) CreateCollection(collection string, vectorSize int) error {
	effectiveColl := collection
	if vectorSize > 0 {
		effectiveColl = fmt.Sprintf("%s-%d", collection, vectorSize)
	}

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	body, err := json.Marshal(map[string]interface{}{
		"vectors": map[string]interface{}{
			"size":     vectorSize,
			"distance": "Cosine",
		},
	})
	if err != nil {
		return fmt.Errorf("failed to marshal collection config: %w", err)
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
		return fmt.Errorf("qdrant returned status %d", resp.StatusCode)
	}

	return nil
}
