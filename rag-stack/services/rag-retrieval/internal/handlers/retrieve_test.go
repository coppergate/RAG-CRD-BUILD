package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"app-builds/rag-retrieval/internal/config"
	"app-builds/rag-retrieval/internal/memory"
	"app-builds/rag-retrieval/internal/qdrant"
	"app-builds/rag-retrieval/internal/session"
	"app-builds/rag-retrieval/internal/tags"
)

type stubEmbedder struct {
	vector []float32
	err    error
	calls  int
}

func (s *stubEmbedder) Embed(ctx context.Context, text, model string) ([]float32, error) {
	s.calls++
	if s.err != nil {
		return nil, s.err
	}
	if s.vector == nil {
		return []float32{0.1, 0.2, 0.3}, nil
	}
	return s.vector, nil
}
func (s *stubEmbedder) Transport() string { return "stub" }

// harness wires a Handler against stub upstreams. qdrantBody is what the fake
// Qdrant returns for a search.
type harness struct {
	h         *Handler
	embedder  *stubEmbedder
	published []any
}

type stubPublisher struct{ got *[]any; err error }

func (p stubPublisher) Publish(topic string, payload any) error {
	if p.err != nil {
		return p.err
	}
	*p.got = append(*p.got, payload)
	return nil
}

func newHarness(t *testing.T, qdrantHandler, dbHandler, memHandler http.HandlerFunc) *harness {
	t.Helper()

	qsrv := httptest.NewServer(qdrantHandler)
	t.Cleanup(qsrv.Close)
	dbsrv := httptest.NewServer(dbHandler)
	t.Cleanup(dbsrv.Close)
	msrv := httptest.NewServer(memHandler)
	t.Cleanup(msrv.Close)

	cfg := &config.Config{
		MaxBodyBytes: 1 << 20, DefaultTopK: 6, PlannerTopK: 10, ExecutorTopK: 4,
		MaxTopK: 50, DefaultMaxTokens: 4096, Collection: "vectors",
		EmbeddingModel: "all-minilm:l6-v2", VectorSize: 384,
		EmbedTimeout: 5 * time.Second, SearchTimeout: 5 * time.Second,
		MemoryTimeout: 5 * time.Second, TagCacheTTL: time.Minute,
		PlannerTags: []string{"stack-docs"}, ExecutorTags: []string{"stack-go"},
		IngestEnabled: true, IngestTurnTopic: "persistent://t/t/t",
	}

	qc, err := qdrant.NewClient(qsrv.URL, cfg.SearchTimeout)
	if err != nil {
		t.Fatal(err)
	}
	tr, err := tags.NewResolver(dbsrv.URL, cfg.TagCacheTTL, cfg.MemoryTimeout)
	if err != nil {
		t.Fatal(err)
	}
	mc, err := memory.NewClient(msrv.URL, cfg.MemoryTimeout)
	if err != nil {
		t.Fatal(err)
	}
	sm, err := session.NewMapper(dbsrv.URL, cfg.MemoryTimeout)
	if err != nil {
		t.Fatal(err)
	}

	hr := &harness{embedder: &stubEmbedder{}}
	hr.h = &Handler{
		Cfg: cfg, Embedder: hr.embedder, Qdrant: qc, Tags: tr,
		Memory: mc, Sessions: sm,
		Publisher: stubPublisher{got: &hr.published},
	}
	return hr
}

func okQdrant(body string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/collections" {
			_, _ = w.Write([]byte(`{"result":{"collections":[{"name":"vectors-all-minilm-l6-v2-384"}]}}`))
			return
		}
		_, _ = w.Write([]byte(body))
	}
}

func tagsDB(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/tags":
		_, _ = w.Write([]byte(`[{"id":1,"name":"stack-docs"},{"id":2,"name":"stack-go"}]`))
	case r.URL.Path == "/sessions/external":
		_, _ = w.Write([]byte(`{"session_id":1421}`))
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

func noMemory(w http.ResponseWriter, r *http.Request) {
	_, _ = w.Write([]byte(`{"items":[]}`))
}

func post(t *testing.T, h *Handler, body string, headers map[string]string) (*httptest.ResponseRecorder, RetrieveResponse) {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/rag/retrieve", bytes.NewBufferString(body))
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.HandleRetrieve(rec, req)

	var out RetrieveResponse
	if rec.Code == http.StatusOK {
		if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
			t.Fatalf("decode response: %v (body %s)", err, rec.Body.String())
		}
	}
	return rec, out
}

func TestRetrieveHappyPath(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[
		{"id":"p1","score":0.9,"payload":{"path":"a.go","chunk":1,"text":"body","tags":[2]}}
	]}`), tagsDB, noMemory)

	rec, out := post(t, hr.h, `{"query":"how does chunking work","top_k":3}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	if len(out.Chunks) != 1 || out.Chunks[0].Score != 0.9 {
		t.Fatalf("unexpected chunks: %+v", out.Chunks)
	}
	if out.Chunks[0].TagNames[0] != "stack-go" {
		t.Errorf("tag id not resolved to a name: %+v", out.Chunks[0].TagNames)
	}
	if out.Block == "" {
		t.Error("expected an assembled block by default")
	}
	if out.CorrelationID == "" {
		t.Error("expected a correlation id")
	}
	if rec.Header().Get("X-RAG-Retrieved") != "1" {
		t.Errorf("X-RAG-Retrieved = %q", rec.Header().Get("X-RAG-Retrieved"))
	}
	if out.Timings.Total < 0 {
		t.Error("expected timings to be populated")
	}
}

// §10.4: an un-ingested corpus must read as empty-and-explained, never as 5xx.
func TestMissingCollectionReturns200AndExplains(t *testing.T) {
	hr := newHarness(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/collections" {
			_, _ = w.Write([]byte(`{"result":{"collections":[]}}`))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}, tagsDB, noMemory)

	rec, out := post(t, hr.h, `{"query":"anything"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for a missing collection, got %d", rec.Code)
	}
	if !out.CollectionMissing {
		t.Error("expected collection_missing=true")
	}
	if len(out.Degraded) == 0 || !strings.Contains(strings.Join(out.Degraded, " "), "not ingested") {
		t.Errorf("expected an explanatory degraded entry, got %v", out.Degraded)
	}
	if len(out.Chunks) != 0 {
		t.Error("expected no chunks")
	}
}

// Chunks must be a [] in JSON, never null: the plugin branches on length.
func TestEmptyResultIsArrayNotNull(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	rec, _ := post(t, hr.h, `{"query":"nothing matches"}`, nil)

	var raw map[string]json.RawMessage
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	if string(raw["chunks"]) != "[]" {
		t.Errorf("chunks must serialise as [], got %s", raw["chunks"])
	}
}

// A dead memory-controller degrades; it does not fail the request.
func TestMemoryFailureDegrades(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[
		{"id":"p1","score":0.9,"payload":{"path":"a.go","text":"b"}}
	]}`), tagsDB, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})

	rec, out := post(t, hr.h, `{"query":"q","session":"ses_1","include_memory":true}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 despite memory failure, got %d", rec.Code)
	}
	if len(out.Chunks) != 1 {
		t.Error("chunks should still be returned")
	}
	if !strings.Contains(strings.Join(out.Degraded, " "), "memory") {
		t.Errorf("expected a memory degradation note, got %v", out.Degraded)
	}
}

// An unresolvable session degrades too — retrieval does not need one.
func TestSessionFailureDegrades(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/tags" {
			_, _ = w.Write([]byte(`[]`))
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	}, noMemory)

	rec, out := post(t, hr.h, `{"query":"q","session":"ses_broken"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if out.SessionID != 0 {
		t.Errorf("expected no session id, got %d", out.SessionID)
	}
	if !strings.Contains(strings.Join(out.Degraded, " "), "session") {
		t.Errorf("expected a session degradation note, got %v", out.Degraded)
	}
}

// profile=none short-circuits before any upstream is touched (§5.5 titles).
func TestProfileNoneSkipsRetrievalEntirely(t *testing.T) {
	hr := newHarness(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("must not reach Qdrant when the profile is none")
	}, tagsDB, noMemory)

	rec, out := post(t, hr.h, `{"query":"name this chat","profile":"none"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d", rec.Code)
	}
	if hr.embedder.calls != 0 {
		t.Error("must not embed when the profile is none")
	}
	if out.Profile != "none" || len(out.Chunks) != 0 {
		t.Errorf("unexpected response %+v", out)
	}
}

func TestModeOffHeaderKillsRetrieval(t *testing.T) {
	hr := newHarness(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("must not reach Qdrant when X-RAG-Mode is off")
	}, tagsDB, noMemory)

	_, out := post(t, hr.h, `{"query":"q"}`, map[string]string{"X-RAG-Mode": "off"})
	if out.Profile != "none" {
		t.Errorf("expected profile none, got %q", out.Profile)
	}
}

// Headers are the control surface (§A.4) and must beat body fields.
func TestHeadersOverrideBody(t *testing.T) {
	var sentLimit float64
	hr := newHarness(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/collections" {
			_, _ = w.Write([]byte(`{"result":{"collections":[{"name":"vectors-all-minilm-l6-v2-384"}]}}`))
			return
		}
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		sentLimit, _ = body["limit"].(float64)
		_, _ = w.Write([]byte(`{"result":[]}`))
	}, tagsDB, noMemory)

	_, out := post(t, hr.h, `{"query":"q","top_k":3,"profile":"planner"}`, map[string]string{
		"X-RAG-Top-K":   "9",
		"X-RAG-Profile": "executor",
	})
	if out.Profile != "executor" {
		t.Errorf("header profile should win, got %q", out.Profile)
	}
	if sentLimit != 9 {
		t.Errorf("header top_k should win, Qdrant saw limit=%v", sentLimit)
	}
}

func TestUnknownTagIsReportedNotSwallowed(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)

	_, out := post(t, hr.h, `{"query":"q","tags":["stack-go","typo-tag"]}`, nil)
	if len(out.UnknownTags) != 1 || out.UnknownTags[0] != "typo-tag" {
		t.Errorf("expected typo-tag reported as unknown, got %v", out.UnknownTags)
	}
}

// A scoped request whose tags all fail to resolve must not silently widen to
// the whole corpus.
func TestUnresolvableTagsWithoutGlobalReturnsEmpty(t *testing.T) {
	hr := newHarness(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("must not search unfiltered when include_global=false")
	}, tagsDB, noMemory)

	_, out := post(t, hr.h, `{"query":"q","tags":["nope"],"include_global":false}`, nil)
	if len(out.Chunks) != 0 {
		t.Error("expected no chunks")
	}
	if len(out.Degraded) == 0 {
		t.Error("expected a degraded explanation")
	}
}

func TestEmbedFailureIsAnError(t *testing.T) {
	// Unlike memory/session, a failed embed means we genuinely cannot answer.
	// The plugin's job is to treat any non-200 as passthrough.
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	hr.embedder.err = errors.New("ollama down")

	rec, _ := post(t, hr.h, `{"query":"q"}`, nil)
	if rec.Code != http.StatusBadGateway {
		t.Errorf("expected 502, got %d", rec.Code)
	}
	var body errorBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Error.Code != "embed_failed" {
		t.Errorf("expected a typed error code, got %q", body.Error.Code)
	}
}

func TestMissingQueryIsRejected(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	for _, body := range []string{`{}`, `{"query":"   "}`} {
		rec, _ := post(t, hr.h, body, nil)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("body %s: expected 400, got %d", body, rec.Code)
		}
	}
}

// §2.2: unknown fields are ignored, not 400'd.
func TestUnknownFieldsIgnored(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	rec, _ := post(t, hr.h, `{"query":"q","future_knob":true,"nested":{"a":1}}`, nil)
	if rec.Code != http.StatusOK {
		t.Errorf("expected unknown fields to be ignored, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestFormatChunksSkipsBlock(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[
		{"id":"p1","score":0.9,"payload":{"path":"a.go","text":"b"}}
	]}`), tagsDB, noMemory)

	_, out := post(t, hr.h, `{"query":"q","format":"chunks"}`, nil)
	if out.Block != "" {
		t.Error("format=chunks must not assemble a block")
	}
	if len(out.Chunks) != 1 {
		t.Error("format=chunks must still return chunks")
	}
}

func TestTopKClampedToMax(t *testing.T) {
	var sentLimit float64
	hr := newHarness(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/collections" {
			_, _ = w.Write([]byte(`{"result":{"collections":[{"name":"vectors-all-minilm-l6-v2-384"}]}}`))
			return
		}
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		sentLimit, _ = body["limit"].(float64)
		_, _ = w.Write([]byte(`{"result":[]}`))
	}, tagsDB, noMemory)

	_, _ = post(t, hr.h, `{"query":"q","top_k":100000}`, nil)
	if sentLimit != 50 {
		t.Errorf("expected top_k clamped to MaxTopK=50, Qdrant saw %v", sentLimit)
	}
}

func TestGetIsRejected(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	req := httptest.NewRequest(http.MethodGet, "/v1/rag/retrieve", nil)
	rec := httptest.NewRecorder()
	hr.h.HandleRetrieve(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("expected 405, got %d", rec.Code)
	}
}
