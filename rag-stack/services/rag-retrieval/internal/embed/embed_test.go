package embed

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"app-builds/rag-retrieval/internal/config"
)

func baseCfg() *config.Config {
	return &config.Config{EmbeddingModel: "all-minilm:l6-v2", EmbedTimeout: 5 * time.Second}
}

// The legacy /api/embeddings route with a "prompt" field is what ingestion
// used, so retrieval must use it too or the vectors will not be comparable.
func TestOllamaUsesLegacyEmbeddingsRoute(t *testing.T) {
	var path string
	var body map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		_ = json.NewDecoder(r.Body).Decode(&body)
		_, _ = w.Write([]byte(`{"embedding":[0.1,0.2,0.3]}`))
	}))
	defer srv.Close()

	cfg := baseCfg()
	cfg.OllamaEmbedURL = srv.URL
	c, err := NewOllamaClient(cfg)
	if err != nil {
		t.Fatal(err)
	}

	vec, err := c.Embed(context.Background(), "hello", "")
	if err != nil {
		t.Fatalf("Embed: %v", err)
	}
	if path != "/api/embeddings" {
		t.Errorf("expected /api/embeddings, got %q", path)
	}
	if _, ok := body["prompt"]; !ok {
		t.Errorf("expected a 'prompt' field, got %v", body)
	}
	if body["model"] != "all-minilm:l6-v2" {
		t.Errorf("expected the configured default model, got %v", body["model"])
	}
	if len(vec) != 3 {
		t.Errorf("expected 3 dims, got %d", len(vec))
	}
}

func TestOllamaModelOverride(t *testing.T) {
	var body map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&body)
		_, _ = w.Write([]byte(`{"embedding":[1]}`))
	}))
	defer srv.Close()

	cfg := baseCfg()
	cfg.OllamaEmbedURL = srv.URL
	c, _ := NewOllamaClient(cfg)
	if _, err := c.Embed(context.Background(), "x", "nomic-embed-text"); err != nil {
		t.Fatal(err)
	}
	if body["model"] != "nomic-embed-text" {
		t.Errorf("override ignored, got %v", body["model"])
	}
}

// An empty vector is a failure, not a valid answer: searching with it would
// either error or silently scroll the collection.
func TestEmptyVectorIsAnError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"embedding":[]}`))
	}))
	defer srv.Close()

	cfg := baseCfg()
	cfg.OllamaEmbedURL = srv.URL
	c, _ := NewOllamaClient(cfg)
	if _, err := c.Embed(context.Background(), "x", ""); err == nil {
		t.Error("expected an error for an empty vector")
	}
}

func TestOllamaNonOKIncludesBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`model not found`))
	}))
	defer srv.Close()

	cfg := baseCfg()
	cfg.OllamaEmbedURL = srv.URL
	c, _ := NewOllamaClient(cfg)
	_, err := c.Embed(context.Background(), "x", "")
	if err == nil {
		t.Fatal("expected an error")
	}
	// The upstream message is the whole diagnostic value here.
	if !strings.Contains(err.Error(), "model not found") {
		t.Errorf("expected the upstream body in the error, got %v", err)
	}
}

func TestGatewayTransport(t *testing.T) {
	var path string
	var body map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		_ = json.NewDecoder(r.Body).Decode(&body)
		_, _ = w.Write([]byte(`{"vector":[0.5,0.6]}`))
	}))
	defer srv.Close()

	cfg := baseCfg()
	cfg.EmbedGatewayURL = srv.URL
	c, err := NewGatewayClient(cfg)
	if err != nil {
		t.Fatal(err)
	}
	vec, err := c.Embed(context.Background(), "hello", "")
	if err != nil {
		t.Fatalf("Embed: %v", err)
	}
	if path != "/embed" {
		t.Errorf("expected /embed, got %q", path)
	}
	if body["text"] != "hello" {
		t.Errorf("expected a 'text' field, got %v", body)
	}
	if len(vec) != 2 {
		t.Errorf("expected 2 dims, got %d", len(vec))
	}
}

func TestGatewayInBandErrorIsSurfaced(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"error":"all ollama pods unreachable"}`))
	}))
	defer srv.Close()

	cfg := baseCfg()
	cfg.EmbedGatewayURL = srv.URL
	c, _ := NewGatewayClient(cfg)
	_, err := c.Embed(context.Background(), "x", "")
	if err == nil || !strings.Contains(err.Error(), "unreachable") {
		t.Errorf("expected the in-band error surfaced, got %v", err)
	}
}

func TestTransportSelection(t *testing.T) {
	cfg := baseCfg()
	cfg.OllamaEmbedURL = "http://o"
	cfg.EmbedGatewayURL = "http://g"

	cfg.EmbedTransport = config.TransportOllama
	c, err := New(cfg)
	if err != nil || c.Transport() != "ollama" {
		t.Errorf("expected the ollama transport, got %v / %v", c, err)
	}

	cfg.EmbedTransport = config.TransportGateway
	c, err = New(cfg)
	if err != nil || c.Transport() != "gateway" {
		t.Errorf("expected the gateway transport, got %v / %v", c, err)
	}
}

