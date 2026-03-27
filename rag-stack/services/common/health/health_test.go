package health

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthzAlwaysOK(t *testing.T) {
	srv := NewServer()
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)

	req := httptest.NewRequest("GET", "/healthz", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("GET /healthz = %d, want %d", w.Code, http.StatusOK)
	}
	if w.Body.String() != "OK" {
		t.Errorf("GET /healthz body = %q, want %q", w.Body.String(), "OK")
	}
}

func TestLegacyHealthAlwaysOK(t *testing.T) {
	srv := NewServer()
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)

	req := httptest.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("GET /health = %d, want %d", w.Code, http.StatusOK)
	}
}

func TestReadyzAllChecksPass(t *testing.T) {
	srv := NewServer()
	srv.RegisterCheck("db", func() error { return nil })
	srv.RegisterCheck("pulsar", func() error { return nil })

	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)

	req := httptest.NewRequest("GET", "/readyz", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("GET /readyz = %d, want %d", w.Code, http.StatusOK)
	}

	var body map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("Failed to parse response body: %v", err)
	}
	if body["status"] != "ready" {
		t.Errorf("status = %q, want %q", body["status"], "ready")
	}
}

func TestReadyzWithFailingCheck(t *testing.T) {
	srv := NewServer()
	srv.RegisterCheck("db", func() error { return fmt.Errorf("connection refused") })
	srv.RegisterCheck("pulsar", func() error { return nil })

	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)

	req := httptest.NewRequest("GET", "/readyz", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("GET /readyz = %d, want %d", w.Code, http.StatusServiceUnavailable)
	}

	var body map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("Failed to parse response body: %v", err)
	}
	if body["status"] != "not ready" {
		t.Errorf("status = %q, want %q", body["status"], "not ready")
	}
	errors, ok := body["errors"].(map[string]interface{})
	if !ok {
		t.Fatal("expected errors map in response")
	}
	if errors["db"] != "connection refused" {
		t.Errorf("errors[db] = %q, want %q", errors["db"], "connection refused")
	}
	if _, hasP := errors["pulsar"]; hasP {
		t.Error("pulsar should not be in errors (it passed)")
	}
}

func TestReadyzNoChecksIsReady(t *testing.T) {
	srv := NewServer()
	mux := http.NewServeMux()
	srv.RegisterRoutes(mux)

	req := httptest.NewRequest("GET", "/readyz", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("GET /readyz = %d, want %d", w.Code, http.StatusOK)
	}
}
