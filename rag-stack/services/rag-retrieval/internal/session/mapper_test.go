package session

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestResolveReturnsID(t *testing.T) {
	var gotBody map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/sessions/external" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		_, _ = w.Write([]byte(`{"session_id":1421}`))
	}))
	defer srv.Close()

	m, err := NewMapper(srv.URL, 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	id, err := m.Resolve(context.Background(), "ses_7f3a", "opencode")
	if err != nil {
		t.Fatalf("Resolve: %v", err)
	}
	if id != 1421 {
		t.Errorf("expected 1421, got %d", id)
	}
	if gotBody["external_id"] != "ses_7f3a" || gotBody["source"] != "opencode" {
		t.Errorf("unexpected request body: %v", gotBody)
	}
}

func TestResolveAccepts201(t *testing.T) {
	// db-adapter returns 201 on first sight.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"session_id":7}`))
	}))
	defer srv.Close()

	m, _ := NewMapper(srv.URL, 5*time.Second)
	id, err := m.Resolve(context.Background(), "ses_new", "opencode")
	if err != nil || id != 7 {
		t.Errorf("expected 7 with no error, got %d / %v", id, err)
	}
}

func TestResolveCachesAfterFirstSight(t *testing.T) {
	var calls int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&calls, 1)
		_, _ = w.Write([]byte(`{"session_id":99}`))
	}))
	defer srv.Close()

	m, _ := NewMapper(srv.URL, 5*time.Second)
	for i := 0; i < 4; i++ {
		if _, err := m.Resolve(context.Background(), "ses_same", "opencode"); err != nil {
			t.Fatal(err)
		}
	}
	// Retrieval calls this on every turn; without caching it is an extra
	// round-trip against the 800ms budget each time.
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Errorf("expected 1 upstream call, got %d", got)
	}
}

func TestEmptyExternalIDIsNoopNotError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("must not call db-adapter for an empty session id")
	}))
	defer srv.Close()

	m, _ := NewMapper(srv.URL, 5*time.Second)
	for _, in := range []string{"", "   "} {
		id, err := m.Resolve(context.Background(), in, "opencode")
		if err != nil || id != 0 {
			t.Errorf("input %q: expected 0 with no error, got %d / %v", in, id, err)
		}
	}
}

func TestSourceDefaults(t *testing.T) {
	var gotBody map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		_, _ = w.Write([]byte(`{"session_id":1}`))
	}))
	defer srv.Close()

	m, _ := NewMapper(srv.URL, 5*time.Second)
	if _, err := m.Resolve(context.Background(), "ses_x", ""); err != nil {
		t.Fatal(err)
	}
	if gotBody["source"] != "opencode" {
		t.Errorf("expected source to default, got %q", gotBody["source"])
	}
}

func TestUpstreamErrorIsReported(t *testing.T) {
	// The caller treats this as degraded, but the mapper must not invent an id.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	m, _ := NewMapper(srv.URL, 5*time.Second)
	id, err := m.Resolve(context.Background(), "ses_bad", "opencode")
	if err == nil {
		t.Error("expected an error")
	}
	if id != 0 {
		t.Errorf("expected 0 on failure, got %d", id)
	}
}

func TestZeroSessionIDIsRejected(t *testing.T) {
	// A 0 would silently disable memory lookups; treat it as a bug upstream.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"session_id":0}`))
	}))
	defer srv.Close()

	m, _ := NewMapper(srv.URL, 5*time.Second)
	if _, err := m.Resolve(context.Background(), "ses_zero", "opencode"); err == nil {
		t.Error("expected an error for session_id 0")
	}
}

func TestFailureIsNotCached(t *testing.T) {
	var calls int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if atomic.AddInt32(&calls, 1) == 1 {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		_, _ = w.Write([]byte(`{"session_id":55}`))
	}))
	defer srv.Close()

	m, _ := NewMapper(srv.URL, 5*time.Second)
	if _, err := m.Resolve(context.Background(), "ses_retry", "opencode"); err == nil {
		t.Fatal("expected the first call to fail")
	}
	// A transient failure must not poison the session for the rest of the run.
	id, err := m.Resolve(context.Background(), "ses_retry", "opencode")
	if err != nil || id != 55 {
		t.Errorf("expected recovery on the next call, got %d / %v", id, err)
	}
}
