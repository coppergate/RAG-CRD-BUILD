package gateway

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"app-builds/embed-gateway/internal/config"
	"app-builds/embed-gateway/internal/discovery"
)

// newTestGateway builds a Gateway with only the fields HandleEmbed touches.
// Pulsar is deliberately absent: the synchronous route never publishes, and
// requiring a broker to test it would defeat the point.
func newTestGateway(ollamaURL string) *Gateway {
	cfg := &config.Config{GatewayID: "test-gw", OllamaTimeout: 5 * time.Second}
	return &Gateway{
		cfg:        cfg,
		discover:   discovery.NewFallback(ollamaURL),
		httpClient: &http.Client{Timeout: cfg.OllamaTimeout},
	}
}

func postEmbed(g *Gateway, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/embed", strings.NewReader(body))
	rec := httptest.NewRecorder()
	g.HandleEmbed(rec, req)
	return rec
}

func TestEmbedHappyPath(t *testing.T) {
	var gotPath string
	var gotBody map[string]any
	ollama := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		_, _ = w.Write([]byte(`{"embedding":[0.1,0.2,0.3,0.4]}`))
	}))
	defer ollama.Close()

	rec := postEmbed(newTestGateway(ollama.URL), `{"text":"hello world","model":"all-minilm:l6-v2"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var out EmbedHTTPResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out.Dims != 4 || len(out.Vector) != 4 {
		t.Errorf("expected 4 dims, got dims=%d len=%d", out.Dims, len(out.Vector))
	}
	if out.GatewayID != "test-gw" {
		t.Errorf("expected the gateway id echoed, got %q", out.GatewayID)
	}
	if out.Error != "" {
		t.Errorf("unexpected error field: %q", out.Error)
	}

	// Must reuse the same Ollama contract the Pulsar path uses, or the two
	// transports would produce different vectors for the same text.
	if gotPath != "/api/embeddings" {
		t.Errorf("expected /api/embeddings, got %q", gotPath)
	}
	if gotBody["model"] != "all-minilm:l6-v2" {
		t.Errorf("model not forwarded: %v", gotBody["model"])
	}
	if gotBody["prompt"] != "hello world" {
		t.Errorf("expected the text in 'prompt', got %v", gotBody)
	}
}

func TestEmbedRequiresTextAndModel(t *testing.T) {
	g := newTestGateway("http://127.0.0.1:1")
	for _, body := range []string{`{}`, `{"text":"x"}`, `{"model":"m"}`, `{"text":"","model":"m"}`} {
		if rec := postEmbed(g, body); rec.Code != http.StatusBadRequest {
			t.Errorf("body %s: expected 400, got %d", body, rec.Code)
		}
	}
}

func TestEmbedRejectsBadJSON(t *testing.T) {
	if rec := postEmbed(newTestGateway("http://127.0.0.1:1"), `{not json`); rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", rec.Code)
	}
}

func TestEmbedRejectsGET(t *testing.T) {
	g := newTestGateway("http://127.0.0.1:1")
	req := httptest.NewRequest(http.MethodGet, "/embed", nil)
	rec := httptest.NewRecorder()
	g.HandleEmbed(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("expected 405, got %d", rec.Code)
	}
}

// An upstream Ollama failure is 502, not 500: the request was fine.
func TestEmbedUpstreamFailureIs502WithReason(t *testing.T) {
	ollama := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte("model not found"))
	}))
	defer ollama.Close()

	rec := postEmbed(newTestGateway(ollama.URL), `{"text":"x","model":"missing:1b"}`)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("expected 502, got %d", rec.Code)
	}

	var out EmbedHTTPResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out.Error == "" {
		t.Error("expected the upstream reason surfaced, so a caller can tell why")
	}
	if len(out.Vector) != 0 {
		t.Error("expected no vector on failure")
	}
}

func TestEmbedUnreachableOllamaIs502(t *testing.T) {
	rec := postEmbed(newTestGateway("http://127.0.0.1:1"), `{"text":"x","model":"m"}`)
	if rec.Code != http.StatusBadGateway {
		t.Errorf("expected 502, got %d", rec.Code)
	}
}

func TestEmbedReportsDuration(t *testing.T) {
	ollama := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"embedding":[1]}`))
	}))
	defer ollama.Close()

	rec := postEmbed(newTestGateway(ollama.URL), `{"text":"x","model":"m"}`)
	var out EmbedHTTPResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	// This is the number measurement M3 compares across transports, so it has
	// to actually be populated.
	if out.DurationMs < 0 {
		t.Errorf("duration_ms should be reported, got %d", out.DurationMs)
	}
}
