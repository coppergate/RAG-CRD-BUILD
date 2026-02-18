package qdrant

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
	"app-builds/qdrant-adapter/internal/config"
)

type QdrantClient struct {
	cfg        *config.Config
	httpClient *http.Client
}

func NewClient(cfg *config.Config) *QdrantClient {
	return &QdrantClient{
		cfg:        cfg,
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

func (q *QdrantClient) Search(collection string, vector []float32, limit int, tags []string) ([]string, error) {
	url := fmt.Sprintf("http://%s:%s/collections/%s/points/search", q.cfg.QdrantHost, q.cfg.QdrantPort, collection)
	
	query := map[string]interface{}{
		"vector": vector,
		"limit":  limit,
		"with_payload": true,
	}

	if len(tags) > 0 {
		query["filter"] = map[string]interface{}{
			"should": []map[string]interface{}{
				{
					"key": "tags",
					"match": map[string]interface{}{
						"any": tags,
					},
				},
			},
		}
	}
	
	body, _ := json.Marshal(query)
	resp, err := q.httpClient.Post(url, "application/json", bytes.NewBuffer(body))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("qdrant returned status %d", resp.StatusCode)
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

func (q *QdrantClient) Upsert(collection string, points []interface{}) error {
	url := fmt.Sprintf("http://%s:%s/collections/%s/points?wait=true", q.cfg.QdrantHost, q.cfg.QdrantPort, collection)
	
	body, _ := json.Marshal(map[string]interface{}{
		"points": points,
	})
	
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

func (q *QdrantClient) CreateCollection(collection string, vectorSize int) error {
	url := fmt.Sprintf("http://%s:%s/collections/%s", q.cfg.QdrantHost, q.cfg.QdrantPort, collection)
	
	body, _ := json.Marshal(map[string]interface{}{
		"vectors": map[string]interface{}{
			"size":     vectorSize,
			"distance": "Cosine",
		},
	})
	
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
