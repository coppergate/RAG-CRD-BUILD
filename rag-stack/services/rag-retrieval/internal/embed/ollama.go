package embed

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"app-builds/common/tlsutil"
	"app-builds/rag-retrieval/internal/config"
)

// OllamaClient calls Ollama's embeddings endpoint directly.
//
// It uses the legacy /api/embeddings route with a "prompt" field rather than
// /api/embed with "input". That is deliberate: it is what rag-ingestion
// (service.py) and rag-worker (internal/ollama/client.go:255) use, and the
// corpus was embedded through that path. Changing route here without changing
// ingestion risks a different vector for the same text.
type OllamaClient struct {
	baseURL      string
	defaultModel string
	http         *http.Client
}

func NewOllamaClient(cfg *config.Config) (*OllamaClient, error) {
	useTLS := strings.HasPrefix(cfg.OllamaEmbedURL, "https://")
	httpClient, err := tlsutil.NewHTTPClient(useTLS, cfg.EmbedTimeout)
	if err != nil {
		return nil, fmt.Errorf("embed: ollama http client: %w", err)
	}
	return &OllamaClient{
		baseURL:      strings.TrimSuffix(cfg.OllamaEmbedURL, "/"),
		defaultModel: cfg.EmbeddingModel,
		http:         httpClient,
	}, nil
}

func (c *OllamaClient) Transport() string { return string(config.TransportOllama) }

func (c *OllamaClient) Embed(ctx context.Context, text, model string) ([]float32, error) {
	if model == "" {
		model = c.defaultModel
	}

	body, err := json.Marshal(map[string]any{
		"model":  model,
		"prompt": text,
		// Hold the embed model resident between queries; retrieval sits on the
		// critical path of every user turn and cannot afford a cold load.
		"keep_alive": -1,
	})
	if err != nil {
		return nil, fmt.Errorf("embed: marshal request: %w", err)
	}

	url := c.baseURL + "/api/embeddings"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("embed: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("embed: ollama request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("embed: ollama %s returned %d: %s",
			url, resp.StatusCode, strings.TrimSpace(string(snippet)))
	}

	var out struct {
		Embedding []float32 `json:"embedding"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("embed: decode response: %w", err)
	}
	if len(out.Embedding) == 0 {
		return nil, fmt.Errorf("embed: ollama returned an empty vector for model %q", model)
	}
	return out.Embedding, nil
}
