// Package qdrant performs vector search directly against Qdrant's HTTP API.
//
// It deliberately does not reuse qdrant-adapter: that client decodes only `id`
// and `payload` and drops the similarity `score`
// (services/qdrant-adapter/internal/qdrant/client.go:139-158), which a
// retrieval primitive has to return. The collection-resolution logic below is
// ported from that same file so the two agree on which collection to read.
package qdrant

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"app-builds/common/contracts"
	"app-builds/common/logging"
	"app-builds/common/tlsutil"
)

// ErrCollectionMissing means the derived collection does not exist. That is the
// normal state of an un-ingested corpus and must surface as "empty", never as a
// server error — spec §10.4.
var ErrCollectionMissing = errors.New("qdrant: collection does not exist")

// Chunk is one retrieved chunk. Field names follow what rag-ingestion actually
// writes (service.py:583) rather than the spec's aspirational shape: `path` not
// `source`, and `tags` as int64 ids not a single tag name.
type Chunk struct {
	ID       string  `json:"id"`
	Score    float32 `json:"score"`
	Path     string  `json:"path"`
	ChunkIdx int     `json:"chunk"`
	Text     string  `json:"text"`
	Tags     []int64 `json:"tags,omitempty"`
	TagNames []string `json:"tag_names,omitempty"`

	// Present only for chunks ingested after line-range support was added to
	// rag-ingestion. Omitted rather than zeroed for older chunks, so a consumer
	// can tell "line 0" from "unknown".
	StartLine *int `json:"start_line,omitempty"`
	EndLine   *int `json:"end_line,omitempty"`

	EmbeddingModel string `json:"embedding_model,omitempty"`
	IngestionID    any    `json:"ingestion_id,omitempty"`
}

type Client struct {
	baseURL string
	http    *http.Client

	// collection name cache, since resolution may cost a list call
	mu       sync.RWMutex
	resolved map[string]string
}

func NewClient(baseURL string, timeout time.Duration) (*Client, error) {
	useTLS := strings.HasPrefix(baseURL, "https://")
	httpClient, err := tlsutil.NewHTTPClient(useTLS, timeout)
	if err != nil {
		return nil, fmt.Errorf("qdrant: http client: %w", err)
	}
	return &Client{
		baseURL:  strings.TrimSuffix(baseURL, "/"),
		http:     httpClient,
		resolved: make(map[string]string),
	}, nil
}

type SearchParams struct {
	Collection     string
	EmbeddingModel string
	VectorSize     int
	Vector         []float32
	Limit          int
	Tags           []int64
}

// Search runs a vector search and returns chunks ordered by descending score.
func (c *Client) Search(ctx context.Context, p SearchParams) ([]Chunk, string, error) {
	if len(p.Vector) == 0 {
		return nil, "", errors.New("qdrant: refusing to search with an empty vector")
	}
	if p.Limit <= 0 {
		p.Limit = 10
	}

	coll, err := c.resolveCollection(ctx, p.Collection, p.EmbeddingModel, p.VectorSize)
	if err != nil {
		return nil, "", err
	}

	query := map[string]any{
		"vector":       p.Vector,
		"limit":        p.Limit,
		"with_payload": true,
	}
	// Same filter shape as qdrant-adapter's buildTagFilter, so tag semantics do
	// not diverge between the pipeline and retrieval.
	if len(p.Tags) > 0 {
		query["filter"] = map[string]any{
			"must": []map[string]any{{
				"key":   "tags",
				"match": map[string]any{"any": p.Tags},
			}},
		}
	}

	body, err := json.Marshal(query)
	if err != nil {
		return nil, coll, fmt.Errorf("qdrant: marshal query: %w", err)
	}

	url := fmt.Sprintf("%s/collections/%s/points/search", c.baseURL, coll)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, coll, fmt.Errorf("qdrant: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, coll, fmt.Errorf("qdrant: search request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, coll, fmt.Errorf("%w: %s", ErrCollectionMissing, coll)
	}
	if resp.StatusCode != http.StatusOK {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, coll, fmt.Errorf("qdrant: search %s returned %d: %s",
			url, resp.StatusCode, strings.TrimSpace(string(snippet)))
	}

	var out struct {
		Result []struct {
			ID      any            `json:"id"`
			Score   float32        `json:"score"`
			Payload map[string]any `json:"payload"`
		} `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, coll, fmt.Errorf("qdrant: decode response: %w", err)
	}

	chunks := make([]Chunk, 0, len(out.Result))
	for _, r := range out.Result {
		chunks = append(chunks, chunkFromPayload(fmt.Sprintf("%v", r.ID), r.Score, r.Payload))
	}
	sort.SliceStable(chunks, func(i, j int) bool { return chunks[i].Score > chunks[j].Score })

	logging.Printf("[retrieval/qdrant] collection=%q dims=%d limit=%d tags=%v results=%d",
		coll, len(p.Vector), p.Limit, p.Tags, len(chunks))
	return chunks, coll, nil
}

func chunkFromPayload(id string, score float32, payload map[string]any) Chunk {
	c := Chunk{ID: id, Score: score}
	if payload == nil {
		return c
	}

	c.Path, _ = payload["path"].(string)
	if c.Path == "" {
		// Tolerate the alternate key some older writers used.
		c.Path, _ = payload["source"].(string)
	}
	if t, ok := payload["text"].(string); ok {
		c.Text = t
	} else if t, ok := payload["content"].(string); ok {
		// context_builder.go accepts either; mirror that tolerance.
		c.Text = t
	}
	c.ChunkIdx = intFrom(payload["chunk"])
	c.EmbeddingModel, _ = payload["embedding_model"].(string)
	c.IngestionID = payload["ingestion_id"]

	if raw, ok := payload["tags"].([]any); ok {
		for _, v := range raw {
			if f, ok := v.(float64); ok {
				c.Tags = append(c.Tags, int64(f))
			}
		}
	}

	// Only set when the key is actually present, so callers can distinguish
	// "chunk starts at line 0" from "this chunk predates line ranges".
	if _, ok := payload["start_line"]; ok {
		v := intFrom(payload["start_line"])
		c.StartLine = &v
	}
	if _, ok := payload["end_line"]; ok {
		v := intFrom(payload["end_line"])
		c.EndLine = &v
	}
	return c
}

func intFrom(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case int64:
		return int(n)
	}
	return 0
}

// resolveCollection derives the collection name, falling back to a prefix match
// against the live collection list when VectorSize is unknown. Ported from
// qdrant-adapter's resolveCollection (internal/qdrant/client.go:61-87).
func (c *Client) resolveCollection(ctx context.Context, prefix, model string, vectorSize int) (string, error) {
	exact := contracts.BuildEmbeddingCollection(prefix, model, vectorSize)
	if vectorSize > 0 {
		return exact, nil
	}

	cacheKey := prefix + "|" + model
	c.mu.RLock()
	cached, ok := c.resolved[cacheKey]
	c.mu.RUnlock()
	if ok {
		return cached, nil
	}

	base := contracts.BuildEmbeddingCollection(prefix, model, 0)
	names, err := c.listCollectionNames(ctx)
	if err != nil {
		// Cannot list: fall back to the derived name and let the search itself
		// report a missing collection.
		logging.Printf("[retrieval/qdrant] collection list failed, using derived name %q: %v", exact, err)
		return exact, nil
	}

	matches := make([]string, 0, 1)
	for _, n := range names {
		if n == base || strings.HasPrefix(n, base+"-") {
			matches = append(matches, n)
		}
	}
	if len(matches) == 0 {
		return exact, fmt.Errorf("%w: no collection matching %q (have %d collections)",
			ErrCollectionMissing, base+"-*", len(names))
	}

	// Longest name wins, matching qdrant-adapter's tie-break.
	sort.Slice(matches, func(i, j int) bool { return len(matches[i]) > len(matches[j]) })
	chosen := matches[0]

	c.mu.Lock()
	c.resolved[cacheKey] = chosen
	c.mu.Unlock()
	return chosen, nil
}

func (c *Client) listCollectionNames(ctx context.Context) ([]string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/collections", nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("qdrant: list collections returned %d", resp.StatusCode)
	}

	var out struct {
		Result struct {
			Collections []struct {
				Name string `json:"name"`
			} `json:"collections"`
		} `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	names := make([]string, 0, len(out.Result.Collections))
	for _, c := range out.Result.Collections {
		names = append(names, c.Name)
	}
	return names, nil
}

// Ping reports whether Qdrant is reachable, for /readyz.
func (c *Client) Ping(ctx context.Context) error {
	_, err := c.listCollectionNames(ctx)
	return err
}
