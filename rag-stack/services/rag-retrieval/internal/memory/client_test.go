package memory

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestRetrieveMapsItems(t *testing.T) {
	var gotBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/retrieve" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		_, _ = w.Write([]byte(`{"items":[
			{"memory_type":"rule","summary":"s1","content":"c1"},
			{"memory_type":"decision","summary":"s2","content":"c2"}
		]}`))
	}))
	defer srv.Close()

	c, err := NewClient(srv.URL, 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	items, err := c.Retrieve(context.Background(), 1421, "why", 6)
	if err != nil {
		t.Fatalf("Retrieve: %v", err)
	}
	if len(items) != 2 || items[0].MemoryType != "rule" || items[1].Content != "c2" {
		t.Errorf("unexpected items: %+v", items)
	}

	// memory-controller keys on a scoped session id.
	scope, _ := gotBody["scope"].(map[string]any)
	if scope == nil || scope["session_id"].(float64) != 1421 {
		t.Errorf("expected a scoped session id, got %v", gotBody)
	}
}

// Without a session there is nothing to scope to, and no call should be made.
func TestZeroSessionSkipsCall(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("must not call memory-controller without a session id")
	}))
	defer srv.Close()

	c, _ := NewClient(srv.URL, 5*time.Second)
	items, err := c.Retrieve(context.Background(), 0, "q", 6)
	if err != nil || items != nil {
		t.Errorf("expected no items and no error, got %v / %v", items, err)
	}
}

func TestEmptyItemsAreDropped(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"items":[
			{"memory_type":"rule","summary":"","content":""},
			{"memory_type":"rule","summary":"keep","content":""}
		]}`))
	}))
	defer srv.Close()

	c, _ := NewClient(srv.URL, 5*time.Second)
	items, err := c.Retrieve(context.Background(), 1, "q", 6)
	if err != nil {
		t.Fatal(err)
	}
	// An item with neither summary nor content costs context and says nothing.
	if len(items) != 1 || items[0].Summary != "keep" {
		t.Errorf("expected only the non-empty item, got %+v", items)
	}
}

// The decode is deliberately loose: a contract change in memory-controller must
// degrade to "no memory", not break retrieval.
func TestUnknownFieldsTolerated(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"items":[{"memory_type":"rule","content":"c","future":1}],"extra":true}`))
	}))
	defer srv.Close()

	c, _ := NewClient(srv.URL, 5*time.Second)
	items, err := c.Retrieve(context.Background(), 1, "q", 6)
	if err != nil {
		t.Fatalf("unknown fields should be ignored, got %v", err)
	}
	if len(items) != 1 {
		t.Errorf("expected 1 item, got %d", len(items))
	}
}

func TestShapeChangeYieldsNoMemoryNotError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// "items" gone entirely.
		_, _ = w.Write([]byte(`{"pack":{"rules":[]}}`))
	}))
	defer srv.Close()

	c, _ := NewClient(srv.URL, 5*time.Second)
	items, err := c.Retrieve(context.Background(), 1, "q", 6)
	if err != nil {
		t.Errorf("a shape change should yield no memory, not an error: %v", err)
	}
	if len(items) != 0 {
		t.Errorf("expected no items, got %d", len(items))
	}
}

func TestUpstreamErrorIsReported(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	c, _ := NewClient(srv.URL, 5*time.Second)
	if _, err := c.Retrieve(context.Background(), 1, "q", 6); err == nil {
		t.Error("expected an error the handler can record as degraded")
	}
}

func TestMalformedJSONIsReported(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{items:`))
	}))
	defer srv.Close()

	c, _ := NewClient(srv.URL, 5*time.Second)
	if _, err := c.Retrieve(context.Background(), 1, "q", 6); err == nil {
		t.Error("expected a decode error")
	}
}
