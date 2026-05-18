package handlers

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"app-builds/rag-admin-api/internal/config"
)

func TestProxyTo(t *testing.T) {
	// 1. Create a backend server that we will proxy to
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/test" {
			t.Errorf("Expected path /test, got %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("proxied"))
	}))
	defer backend.Close()

	// 2. Setup AdminHandler
	h := &AdminHandler{
		Cfg: &config.Config{},
	}

	// 3. Create the proxy handler
	proxyHandler := h.ProxyTo(backend.URL, "/api/v1")

	// 4. Create a request to the proxy
	req := httptest.NewRequest(http.MethodGet, "/api/v1/test", nil)
	w := httptest.NewRecorder()

	// 5. Serve the request
	proxyHandler.ServeHTTP(w, req)

	// 6. Assertions
	resp := w.Result()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK, got %v", resp.StatusCode)
	}

	body, _ := io.ReadAll(resp.Body)
	if string(body) != "proxied" {
		t.Errorf("Expected body 'proxied', got %s", string(body))
	}
}

func TestHandleHealthAggregation(t *testing.T) {
	// Create mock backend services
	ts1 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status": "UP"}`))
	}))
	defer ts1.Close()

	ts2 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(`{"status": "DOWN"}`))
	}))
	defer ts2.Close()

	cfg := &config.Config{
		DBAdapterURL:        ts1.URL,
		S3ManagerURL:        ts2.URL,
		QdrantAdapterURL:    "http://non-existent",
		LLMGatewayURL:       ts1.URL,
		MemoryControllerURL: ts1.URL,
	}

	h := &AdminHandler{Cfg: cfg}

	req := httptest.NewRequest(http.MethodGet, "/health/aggregate", nil)
	w := httptest.NewRecorder()

	h.HandleHealthAggregation(w, req)

	resp := w.Result()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK, got %v", resp.StatusCode)
	}

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	// Verify some results
	if db, ok := result["db-adapter"].(map[string]interface{}); ok {
		if db["status"] != "UP" {
			t.Errorf("Expected db-adapter status UP, got %v", db["status"])
		}
	} else {
		t.Errorf("Expected db-adapter result to be a map, got %T", result["db-adapter"])
	}

	if qdrant, ok := result["qdrant-adapter"].(map[string]interface{}); ok {
		if qdrant["status"] != "DOWN" {
			t.Errorf("Expected qdrant-adapter status DOWN, got %v", qdrant["status"])
		}
	}
}
