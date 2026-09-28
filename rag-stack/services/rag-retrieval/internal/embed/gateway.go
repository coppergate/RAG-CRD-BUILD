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

// GatewayClient calls embed-gateway's synchronous /embed route, which in turn
// dispatches to a node-local Ollama pod with re-discovery and fallback.
type GatewayClient struct {
	baseURL      string
	defaultModel string
	http         *http.Client
}

func NewGatewayClient(cfg *config.Config) (*GatewayClient, error) {
	useTLS := strings.HasPrefix(cfg.EmbedGatewayURL, "https://")
	httpClient, err := tlsutil.NewHTTPClient(useTLS, cfg.EmbedTimeout)
	if err != nil {
		return nil, fmt.Errorf("embed: gateway http client: %w", err)
	}
	return &GatewayClient{
		baseURL:      strings.TrimSuffix(cfg.EmbedGatewayURL, "/"),
		defaultModel: cfg.EmbeddingModel,
		http:         httpClient,
	}, nil
}

func (c *GatewayClient) Transport() string { return string(config.TransportGateway) }

func (c *GatewayClient) Embed(ctx context.Context, text, model string) ([]float32, error) {
	if model == "" {
		model = c.defaultModel
	}

	body, err := json.Marshal(map[string]any{"text": text, "model": model})
	if err != nil {
		return nil, fmt.Errorf("embed: marshal request: %w", err)
	}

	url := c.baseURL + "/embed"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("embed: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("embed: gateway request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("embed: gateway %s returned %d: %s",
			url, resp.StatusCode, strings.TrimSpace(string(snippet)))
	}

	var out struct {
		Vector []float32 `json:"vector"`
		Error  string    `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("embed: decode response: %w", err)
	}
	if out.Error != "" {
		return nil, fmt.Errorf("embed: gateway reported: %s", out.Error)
	}
	if len(out.Vector) == 0 {
		return nil, fmt.Errorf("embed: gateway returned an empty vector for model %q", model)
	}
	return out.Vector, nil
}
