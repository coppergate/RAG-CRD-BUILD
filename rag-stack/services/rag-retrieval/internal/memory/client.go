// Package memory folds memory-controller results into a retrieval response.
//
// Only the planner profile asks for these (§5.5): rules and prior decisions are
// architectural context, and an executor wanting a function body is not helped
// by them.
package memory

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"app-builds/common/tlsutil"
)

// Item is the trimmed projection the retrieval response exposes.
type Item struct {
	MemoryType string `json:"memory_type"`
	Summary    string `json:"summary"`
	Content    string `json:"content"`
}

type Client struct {
	baseURL string
	http    *http.Client
}

func NewClient(baseURL string, timeout time.Duration) (*Client, error) {
	useTLS := strings.HasPrefix(baseURL, "https://")
	httpClient, err := tlsutil.NewHTTPClient(useTLS, timeout)
	if err != nil {
		return nil, fmt.Errorf("memory: http client: %w", err)
	}
	return &Client{baseURL: strings.TrimSuffix(baseURL, "/"), http: httpClient}, nil
}

// Retrieve asks memory-controller for the memory pack scoped to a session.
// Errors are returned but callers are expected to treat them as "no memory".
func (c *Client) Retrieve(ctx context.Context, sessionID int64, query string, limit int) ([]Item, error) {
	if sessionID == 0 {
		return nil, nil
	}

	body, err := json.Marshal(map[string]any{
		"scope": map[string]any{"session_id": sessionID},
		"query": query,
		"limit": limit,
	})
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/retrieve", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("memory: retrieve: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("memory: memory-controller /retrieve returned %d", resp.StatusCode)
	}

	// memory-controller returns a MemoryPack; decode loosely so a contract
	// change there degrades to "no memory" rather than breaking retrieval.
	var pack struct {
		Items []struct {
			MemoryType string `json:"memory_type"`
			Summary    string `json:"summary"`
			Content    string `json:"content"`
		} `json:"items"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&pack); err != nil {
		return nil, fmt.Errorf("memory: decode: %w", err)
	}

	out := make([]Item, 0, len(pack.Items))
	for _, it := range pack.Items {
		if it.Content == "" && it.Summary == "" {
			continue
		}
		out = append(out, Item{MemoryType: it.MemoryType, Summary: it.Summary, Content: it.Content})
	}
	return out, nil
}
