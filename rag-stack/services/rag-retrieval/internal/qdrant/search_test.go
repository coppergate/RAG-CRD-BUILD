package qdrant

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func newTestClient(t *testing.T, h http.Handler) (*Client, *httptest.Server) {
	t.Helper()
	srv := httptest.NewServer(h)
	c, err := NewClient(srv.URL, 5*time.Second)
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	return c, srv
}

// The whole reason this package exists rather than reusing qdrant-adapter.
func TestSearchPreservesScore(t *testing.T) {
	c, srv := newTestClient(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"result":[
			{"id":"p1","score":0.83,"payload":{"path":"a.go","chunk":2,"text":"hello","tags":[7]}},
			{"id":"p2","score":0.42,"payload":{"path":"b.go","chunk":0,"text":"world","tags":[7,9]}}
		]}`))
	}))
	defer srv.Close()

	got, _, err := c.Search(context.Background(), SearchParams{
		Collection: "vectors", EmbeddingModel: "all-minilm:l6-v2", VectorSize: 384,
		Vector: []float32{0.1, 0.2}, Limit: 5,
	})
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("want 2 chunks, got %d", len(got))
	}
	if got[0].Score != 0.83 {
		t.Errorf("score dropped: got %v want 0.83", got[0].Score)
	}
	if got[0].Path != "a.go" || got[0].ChunkIdx != 2 || got[0].Text != "hello" {
		t.Errorf("payload mapped wrong: %+v", got[0])
	}
	if len(got[1].Tags) != 2 || got[1].Tags[0] != 7 {
		t.Errorf("tags mapped wrong: %+v", got[1].Tags)
	}
}

func TestSearchSortsByScoreDescending(t *testing.T) {
	c, srv := newTestClient(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"result":[
			{"id":"low","score":0.1,"payload":{"path":"low.go","text":"l"}},
			{"id":"high","score":0.9,"payload":{"path":"high.go","text":"h"}}
		]}`))
	}))
	defer srv.Close()

	got, _, err := c.Search(context.Background(), SearchParams{
		Vector: []float32{1}, VectorSize: 384, Limit: 5,
	})
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if got[0].Path != "high.go" {
		t.Errorf("expected score-descending order, got %q first", got[0].Path)
	}
}

// A 404 is the normal state of an un-ingested corpus, not a server error.
func TestMissingCollectionIsTyped(t *testing.T) {
	c, srv := newTestClient(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	_, _, err := c.Search(context.Background(), SearchParams{
		Vector: []float32{1}, VectorSize: 384, Limit: 5,
	})
	if !errors.Is(err, ErrCollectionMissing) {
		t.Errorf("expected ErrCollectionMissing, got %v", err)
	}
}

func TestEmptyVectorIsRefused(t *testing.T) {
	c, srv := newTestClient(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("must not reach Qdrant with an empty vector")
	}))
	defer srv.Close()

	if _, _, err := c.Search(context.Background(), SearchParams{Limit: 5}); err == nil {
		t.Error("expected an error for an empty vector")
	}
}

func TestLineRangeAbsentStaysNil(t *testing.T) {
	c, srv := newTestClient(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"result":[
			{"id":"old","score":0.5,"payload":{"path":"a.go","text":"t"}},
			{"id":"new","score":0.4,"payload":{"path":"b.go","text":"t","start_line":10,"end_line":20}}
		]}`))
	}))
	defer srv.Close()

	got, _, err := c.Search(context.Background(), SearchParams{Vector: []float32{1}, VectorSize: 384, Limit: 5})
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if got[0].StartLine != nil {
		t.Error("pre-line-range chunk must leave StartLine nil, not 0")
	}
	if got[1].StartLine == nil || *got[1].StartLine != 10 || *got[1].EndLine != 20 {
		t.Errorf("line range not mapped: %+v", got[1])
	}
}

func TestTagFilterShapeMatchesAdapter(t *testing.T) {
	var body map[string]any
	c, srv := newTestClient(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&body)
		_, _ = w.Write([]byte(`{"result":[]}`))
	}))
	defer srv.Close()

	if _, _, err := c.Search(context.Background(), SearchParams{
		Vector: []float32{1}, VectorSize: 384, Limit: 5, Tags: []int64{3, 4},
	}); err != nil {
		t.Fatalf("Search: %v", err)
	}

	filter, ok := body["filter"].(map[string]any)
	if !ok {
		t.Fatalf("no filter sent: %v", body)
	}
	must, ok := filter["must"].([]any)
	if !ok || len(must) != 1 {
		t.Fatalf("unexpected must clause: %v", filter)
	}
	clause := must[0].(map[string]any)
	if clause["key"] != "tags" {
		t.Errorf("expected key=tags, got %v", clause["key"])
	}
	if _, ok := clause["match"].(map[string]any)["any"]; !ok {
		t.Errorf("expected match.any, got %v", clause["match"])
	}
}

// With no VectorSize, the collection is discovered by prefix match.
func TestCollectionResolvedByPrefixMatch(t *testing.T) {
	var searched string
	c, srv := newTestClient(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/collections" {
			_, _ = w.Write([]byte(`{"result":{"collections":[
				{"name":"vectors-all-minilm-l6-v2-384"},
				{"name":"other"}
			]}}`))
			return
		}
		searched = r.URL.Path
		_, _ = w.Write([]byte(`{"result":[]}`))
	}))
	defer srv.Close()

	_, coll, err := c.Search(context.Background(), SearchParams{
		Collection: "vectors", EmbeddingModel: "all-minilm:l6-v2", VectorSize: 0,
		Vector: []float32{1}, Limit: 5,
	})
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if coll != "vectors-all-minilm-l6-v2-384" {
		t.Errorf("resolved to %q", coll)
	}
	if searched != "/collections/vectors-all-minilm-l6-v2-384/points/search" {
		t.Errorf("searched wrong path: %q", searched)
	}
}

func TestNoMatchingCollectionIsMissing(t *testing.T) {
	c, srv := newTestClient(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"result":{"collections":[{"name":"unrelated"}]}}`))
	}))
	defer srv.Close()

	_, _, err := c.Search(context.Background(), SearchParams{
		Collection: "vectors", EmbeddingModel: "nomic-embed-text", VectorSize: 0,
		Vector: []float32{1}, Limit: 5,
	})
	if !errors.Is(err, ErrCollectionMissing) {
		t.Errorf("expected ErrCollectionMissing, got %v", err)
	}
}
