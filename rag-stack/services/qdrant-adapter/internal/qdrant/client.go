package qdrant

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"

	"app-builds/common/contracts"
	"app-builds/common/logging"
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
		logging.Fatalf("Failed to create Qdrant HTTP client with TLS: %v", err)
	}
	return &QdrantClient{
		cfg:        cfg,
		httpClient: httpClient,
	}
}

func (q *QdrantClient) Search(collection string, embeddingModel string, vectorSize int, vector []float32, limit int, tags []int64, sessionID int64, includeGlobal bool) ([]interface{}, error) {
	if limit <= 0 {
		limit = 20 // Default limit
	}
	logging.Printf("[qdrant] search request collection=%q model=%q vector_dims=%d limit=%d tags=%v session_id=%d include_global=%v",
		collection, embeddingModel, len(vector), limit, tags, sessionID, includeGlobal)
	return q.searchWithRetry(collection, embeddingModel, vectorSize, vector, limit, tags, sessionID, includeGlobal, true)
}

func buildTagFilter(tags []int64) map[string]interface{} {
	filter := map[string]interface{}{}

	if len(tags) > 0 {
		filter["must"] = []map[string]interface{}{
			{
				"key": "tags",
				"match": map[string]interface{}{
					"any": tags,
				},
			},
		}
	}

	return filter
}

func resolveCollection(q *QdrantClient, collection, embeddingModel string, vectorSize int) string {
	resolved := contracts.BuildEmbeddingCollection(collection, embeddingModel, vectorSize)
	if q == nil || vectorSize > 0 {
		return resolved
	}

	prefix := contracts.BuildEmbeddingCollection(collection, embeddingModel, 0)
	names, err := q.listCollectionNames()
	if err != nil {
		return resolved
	}

	matches := make([]string, 0, 1)
	for _, name := range names {
		if name == prefix || strings.HasPrefix(name, prefix+"-") {
			matches = append(matches, name)
		}
	}
	if len(matches) == 0 {
		return resolved
	}

	sort.Slice(matches, func(i, j int) bool {
		return len(matches[i]) > len(matches[j])
	})
	return matches[0]
}

func (q *QdrantClient) searchWithRetry(collection string, embeddingModel string, vectorSize int, vector []float32, limit int, tags []int64, sessionID int64, includeGlobal bool, retry bool) ([]interface{}, error) {
	if len(vector) == 0 {
		if len(tags) > 0 {
			logging.Printf("[qdrant] empty vector with tags, using filter-only retrieval collection=%q model=%q vector_size=%d tags=%v session_id=%d include_global=%v limit=%d",
				collection, embeddingModel, vectorSize, tags, sessionID, includeGlobal, limit)
			return q.RetrieveByFilter(collection, embeddingModel, vectorSize, tags, sessionID, includeGlobal, limit)
		}
		logging.Printf("[qdrant] empty vector and no tags, returning no results collection=%q model=%q session_id=%d", collection, embeddingModel, sessionID)
		return nil, nil // Cannot search with empty vector and no tags
	}

	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := resolveCollection(q, collection, embeddingModel, vs)

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s/points/search", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	query := map[string]interface{}{
		"vector":       vector,
		"limit":        limit,
		"with_payload": true,
	}

	if filter := buildTagFilter(tags); len(filter) > 0 {
		query["filter"] = filter
		logging.Printf("[qdrant] search filter tags=%v filter=%+v", tags, query["filter"])
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
		return nil, fmt.Errorf("qdrant collection not found: %s", effectiveColl)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("qdrant (coll: %s) returned status %d", effectiveColl, resp.StatusCode)
	}

	var result struct {
		Result []struct {
			Id      interface{}            `json:"id"`
			Payload map[string]interface{} `json:"payload"`
		} `json:"result"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	var contexts []interface{}
	for _, r := range result.Result {
		payload := r.Payload
		if payload == nil {
			payload = make(map[string]interface{})
		}
		payload["_qdrant_id"] = fmt.Sprintf("%v", r.Id)
		contexts = append(contexts, payload)
	}
	logging.Printf("[qdrant] search response collection=%q model=%q vector_dims=%d tags=%v results=%d", effectiveColl, embeddingModel, len(vector), tags, len(contexts))

	return contexts, nil
}

func (q *QdrantClient) RetrieveByFilter(collection string, embeddingModel string, vectorSize int, tags []int64, sessionID int64, includeGlobal bool, limit int) ([]interface{}, error) {
	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := resolveCollection(q, collection, embeddingModel, vs)

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s/points/scroll", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	if limit <= 0 {
		limit = 100 // Default limit for scroll
	}

	query := map[string]interface{}{
		"limit":        limit,
		"with_payload": true,
	}

	if filter := buildTagFilter(tags); len(filter) > 0 {
		query["filter"] = filter
	}
	logging.Printf("[qdrant] filter-only retrieval request collection=%q model=%q vector_size=%d tags=%v session_id=%d include_global=%v limit=%d",
		effectiveColl, embeddingModel, vs, tags, sessionID, includeGlobal, limit)

	body, _ := json.Marshal(query)
	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := q.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("qdrant collection not found: %s", effectiveColl)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("qdrant scroll returned %d", resp.StatusCode)
	}

	var scrollResp struct {
		Result struct {
			Points []struct {
				Id      interface{}            `json:"id"`
				Payload map[string]interface{} `json:"payload"`
			} `json:"points"`
		} `json:"result"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&scrollResp); err != nil {
		return nil, err
	}

	var results []interface{}
	for _, p := range scrollResp.Result.Points {
		payload := p.Payload
		if payload == nil {
			payload = make(map[string]interface{})
		}
		payload["_qdrant_id"] = fmt.Sprintf("%v", p.Id)
		results = append(results, payload)
	}
	logging.Printf("[qdrant] filter-only retrieval response collection=%q model=%q vector_size=%d tags=%v results=%d", effectiveColl, embeddingModel, vs, tags, len(results))
	return results, nil
}

func (q *QdrantClient) RetrieveByPaths(collection string, embeddingModel string, vectorSize int, paths []string, limit int) ([]interface{}, error) {
	if len(paths) == 0 {
		return nil, nil
	}

	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := resolveCollection(q, collection, embeddingModel, vs)

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s/points/scroll", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	if limit <= 0 {
		limit = 1000 // Large default for full files
	}

	query := map[string]interface{}{
		"limit":        limit,
		"with_payload": true,
		"filter": map[string]interface{}{
			"must": []map[string]interface{}{
				{
					"key": "path",
					"match": map[string]interface{}{
						"any": paths,
					},
				},
			},
		},
	}

	body, _ := json.Marshal(query)
	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := q.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("qdrant collection not found: %s", effectiveColl)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("qdrant scroll by paths returned %d", resp.StatusCode)
	}

	var scrollResp struct {
		Result struct {
			Points []struct {
				Id      interface{}            `json:"id"`
				Payload map[string]interface{} `json:"payload"`
			} `json:"points"`
		} `json:"result"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&scrollResp); err != nil {
		return nil, err
	}

	var results []interface{}
	for _, p := range scrollResp.Result.Points {
		payload := p.Payload
		if payload == nil {
			payload = make(map[string]interface{})
		}
		payload["_qdrant_id"] = fmt.Sprintf("%v", p.Id)
		results = append(results, payload)
	}
	return results, nil
}

func (q *QdrantClient) CreateCollection(collection string, embeddingModel string, vectorSize int) error {
	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}
	effectiveColl := resolveCollection(q, collection, embeddingModel, vs)

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

func (q *QdrantClient) DeleteByFilter(collection string, embeddingModel string, vectorSize int, tags []int64, paths []string) error {
	if embeddingModel == "" && vectorSize <= 0 {
		return q.deleteAcrossMatchingCollections(collection, tags, paths)
	}

	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := resolveCollection(q, collection, embeddingModel, vs)

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

func (q *QdrantClient) deleteAcrossMatchingCollections(collection string, tags []int64, paths []string) error {
	names, err := q.listCollectionNames()
	if err != nil {
		return err
	}

	prefix := collection
	if prefix == "" {
		prefix = "vectors"
	}

	for _, name := range names {
		if name == prefix || strings.HasPrefix(name, prefix+"-") {
			if err := q.deleteFromCollection(name, tags, paths); err != nil {
				return err
			}
		}
	}
	return nil
}

func (q *QdrantClient) deleteFromCollection(effectiveColl string, tags []int64, paths []string) error {
	if len(tags) == 0 && len(paths) == 0 {
		return nil
	}

	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	url := fmt.Sprintf("%s://%s:%s/collections/%s/points/delete?wait=true", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

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

	body, err := json.Marshal(map[string]interface{}{
		"filter": map[string]interface{}{
			"must": mustFilters,
		},
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
		return nil
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

func (q *QdrantClient) listCollectionNames() ([]string, error) {
	raw, err := q.ListCollections()
	if err != nil {
		return nil, err
	}
	payload, ok := raw.(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected collections response")
	}
	result, _ := payload["result"].(map[string]interface{})
	rawCollections, _ := result["collections"].([]interface{})
	names := make([]string, 0, len(rawCollections))
	for _, item := range rawCollections {
		entry, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		name, _ := entry["name"].(string)
		if name != "" {
			names = append(names, name)
		}
	}
	return names, nil
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

func (q *QdrantClient) UpsertProto(collection string, embeddingModel string, vectorSize int, points []*contracts.QdrantPoint) error {
	qdrantPoints := make([]interface{}, len(points))
	for i, p := range points {
		qdrantPoints[i] = map[string]interface{}{
			"id":      p.Id,
			"vector":  p.Vector,
			"payload": contracts.FromStruct(p.Payload),
		}
	}
	return q.Upsert(collection, embeddingModel, vectorSize, qdrantPoints)
}

func (q *QdrantClient) Upsert(collection string, embeddingModel string, vectorSize int, points []interface{}) error {
	return q.upsertWithRetry(collection, embeddingModel, vectorSize, points, true)
}

func (q *QdrantClient) upsertWithRetry(collection string, embeddingModel string, vectorSize int, points []interface{}, retry bool) error {
	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := resolveCollection(q, collection, embeddingModel, vs)

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
		if err := q.CreateCollection(collection, embeddingModel, vs); err != nil {
			return fmt.Errorf("failed to auto-create collection %s: %v", effectiveColl, err)
		}
		return q.upsertWithRetry(collection, embeddingModel, vectorSize, points, false)
	}

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		fmt.Printf("ERROR: Qdrant (coll: %s) returned %d: %s\n", effectiveColl, resp.StatusCode, string(bodyBytes))
		return fmt.Errorf("qdrant (coll: %s) returned status %d", effectiveColl, resp.StatusCode)
	}

	fmt.Printf("DEBUG: Successfully upserted %d points into %s\n", len(points), effectiveColl)
	return nil
}

func (q *QdrantClient) MergeTags(collection string, embeddingModel string, vectorSize int, sourceTag, targetTag int64) error {
	vs := vectorSize
	if vs <= 0 {
		vs = q.cfg.DefaultVectorSize
	}

	effectiveColl := resolveCollection(q, collection, embeddingModel, vs)
	scheme := tlsutil.URLScheme(q.cfg.QdrantUseTLS)
	scrollURL := fmt.Sprintf("%s://%s:%s/collections/%s/points/scroll", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)
	setPayloadURL := fmt.Sprintf("%s://%s:%s/collections/%s/points/payload?wait=true", scheme, q.cfg.QdrantHost, q.cfg.QdrantPort, effectiveColl)

	sourceFilter := map[string]interface{}{
		"must": []map[string]interface{}{
			{
				"key": "tags",
				"match": map[string]interface{}{
					"any": []int64{sourceTag},
				},
			},
		},
	}

	// Step 1: Scroll all points that carry sourceTag, grouped by their resulting new tag set.
	// Grouping minimises the number of payload-update API calls.
	type pointGroup struct {
		newTags []int64
		ids     []interface{}
	}
	groups := make(map[string]*pointGroup)

	var nextOffset interface{}
	const pageSize = 1000
	for {
		query := map[string]interface{}{
			"limit":        pageSize,
			"with_payload": true,
			"filter":       sourceFilter,
		}
		if nextOffset != nil {
			query["offset"] = nextOffset
		}

		body, err := json.Marshal(query)
		if err != nil {
			return err
		}
		req, err := http.NewRequest("POST", scrollURL, bytes.NewBuffer(body))
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", "application/json")

		resp, err := q.httpClient.Do(req)
		if err != nil {
			return err
		}

		var scrollResp struct {
			Result struct {
				Points []struct {
					Id      interface{}            `json:"id"`
					Payload map[string]interface{} `json:"payload"`
				} `json:"points"`
				NextPageOffset interface{} `json:"next_page_offset"`
			} `json:"result"`
		}
		decodeErr := json.NewDecoder(resp.Body).Decode(&scrollResp)
		statusCode := resp.StatusCode
		resp.Body.Close()

		if statusCode != http.StatusOK {
			return fmt.Errorf("qdrant scroll for merge failed: status %d", statusCode)
		}
		if decodeErr != nil {
			return decodeErr
		}

		for _, p := range scrollResp.Result.Points {
			// Parse the point's current tags.
			var currentTags []int64
			if rawTags, ok := p.Payload["tags"]; ok {
				if tagSlice, ok := rawTags.([]interface{}); ok {
					for _, v := range tagSlice {
						switch n := v.(type) {
						case float64:
							currentTags = append(currentTags, int64(n))
						case int64:
							currentTags = append(currentTags, n)
						}
					}
				}
			}

			// Build new tags: drop sourceTag, ensure targetTag is present.
			hasTarget := false
			var newTags []int64
			for _, tag := range currentTags {
				if tag == sourceTag {
					continue
				}
				if tag == targetTag {
					hasTarget = true
				}
				newTags = append(newTags, tag)
			}
			if !hasTarget {
				newTags = append(newTags, targetTag)
			}

			// Sort for a stable grouping key.
			sort.Slice(newTags, func(i, j int) bool { return newTags[i] < newTags[j] })
			key := fmt.Sprintf("%v", newTags)

			if g, exists := groups[key]; exists {
				g.ids = append(g.ids, p.Id)
			} else {
				groups[key] = &pointGroup{newTags: newTags, ids: []interface{}{p.Id}}
			}
		}

		nextOffset = scrollResp.Result.NextPageOffset
		if nextOffset == nil {
			break
		}
	}

	if len(groups) == 0 {
		return nil
	}

	// Step 2: Apply updated tag arrays — one request per distinct resulting tag set.
	for _, group := range groups {
		body, err := json.Marshal(map[string]interface{}{
			"payload": map[string]interface{}{"tags": group.newTags},
			"points":  group.ids,
		})
		if err != nil {
			return err
		}
		resp, err := q.httpClient.Post(setPayloadURL, "application/json", bytes.NewBuffer(body))
		if err != nil {
			return err
		}
		statusCode := resp.StatusCode
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		if statusCode != http.StatusOK {
			return fmt.Errorf("qdrant set payload for merge failed: status %d", statusCode)
		}
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
