package health

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
)

// CheckFunc is a function that performs a health check and returns an error if unhealthy.
type CheckFunc func() error

// Server provides /healthz (liveness) and /readyz (readiness) endpoints.
// Liveness is always OK (process is running). Readiness checks registered dependencies.
type Server struct {
	mu     sync.RWMutex
	checks map[string]CheckFunc
}

// NewServer creates a new health check server.
func NewServer() *Server {
	return &Server{
		checks: make(map[string]CheckFunc),
	}
}

// RegisterCheck adds a named readiness check.
func (s *Server) RegisterCheck(name string, fn CheckFunc) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.checks[name] = fn
}

// RegisterRoutes adds health check endpoints to an existing ServeMux.
// Use this when you want to embed health checks in your main HTTP server.
func (s *Server) RegisterRoutes(mux *http.ServeMux) {
	// Liveness: always OK if process is running
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK"))
	})

	// Legacy /health endpoint maps to liveness
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK"))
	})

	// Readiness: checks all registered dependencies
	mux.HandleFunc("/readyz", s.readyzHandler)
}

// Start launches the health server on the given address in a background goroutine.
// It registers /healthz (liveness), /readyz (readiness), and /health (legacy, maps to liveness).
func (s *Server) Start(addr string) {
	mux := http.NewServeMux()
	s.RegisterRoutes(mux)

	go func() {
		if err := http.ListenAndServe(addr, mux); err != nil {
			log.Printf("Health server stopped: %v", err)
		}
	}()
}

func (s *Server) readyzHandler(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	errors := make(map[string]string)
	for name, check := range s.checks {
		if err := check(); err != nil {
			errors[name] = err.Error()
		}
	}

	if len(errors) > 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "not ready",
			"errors": errors,
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status": "ready",
	})
}
