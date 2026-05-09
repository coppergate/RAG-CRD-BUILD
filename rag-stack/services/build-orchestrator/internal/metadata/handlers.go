package metadata

import (
	"encoding/json"
	"net/http"
	"strings"
)

func (s *Service) RegisterHandlers(mux *http.ServeMux) {
	mux.HandleFunc("/api/build/versions", s.handleVersions)
	mux.HandleFunc("/api/build/versions/", s.handleVersion)
	mux.HandleFunc("/api/build/locks/acquire", s.handleAcquireLock)
	mux.HandleFunc("/api/build/locks/release/", s.handleReleaseLock)
	mux.HandleFunc("/api/build/locks/check/", s.handleCheckLock)
	mux.HandleFunc("/api/build/locks/heartbeat/", s.handleHeartbeat)
	mux.HandleFunc("/api/build/locks/reset", s.handleResetLocks)
	mux.HandleFunc("/api/build/journals/", s.handleJournal)
}

func (s *Service) handleVersions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	versions, err := s.GetVersions(r.Context())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(versions)
}

func (s *Service) handleVersion(w http.ResponseWriter, r *http.Request) {
	serviceName := strings.TrimPrefix(r.URL.Path, "/api/build/versions/")
	if serviceName == "" {
		http.Error(w, "Service name required", http.StatusBadRequest)
		return
	}

	switch r.Method {
	case http.MethodGet:
		v, err := s.GetVersion(r.Context(), serviceName)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if v == nil {
			http.Error(w, "Not found", http.StatusNotFound)
			return
		}
		json.NewEncoder(w).Encode(v)
	case http.MethodPut, http.MethodPatch, http.MethodPost:
		var req struct {
			Version string `json:"version"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := s.UpdateVersion(r.Context(), serviceName, req.Version); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *Service) handleAcquireLock(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		ServiceName string `json:"service_name"`
		Owner       string `json:"owner"`
		Host        string `json:"host"`
		PID         int    `json:"pid"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	success, lock, err := s.AcquireLock(r.Context(), req.ServiceName, req.Owner, req.Host, req.PID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	if success {
		w.WriteHeader(http.StatusCreated)
	} else {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(lock)
	}
}

func (s *Service) handleReleaseLock(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodDelete {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	serviceName := strings.TrimPrefix(r.URL.Path, "/api/build/locks/release/")
	if err := s.ReleaseLock(r.Context(), serviceName); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Service) handleCheckLock(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	serviceName := strings.TrimPrefix(r.URL.Path, "/api/build/locks/check/")
	lock, err := s.CheckLock(r.Context(), serviceName)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if lock == nil {
		http.Error(w, "Not found", http.StatusNotFound)
		return
	}
	json.NewEncoder(w).Encode(lock)
}

func (s *Service) handleHeartbeat(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	serviceName := strings.TrimPrefix(r.URL.Path, "/api/build/locks/heartbeat/")
	if err := s.Heartbeat(r.Context(), serviceName); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Service) handleResetLocks(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := s.ResetLocks(r.Context()); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Service) handleJournal(w http.ResponseWriter, r *http.Request) {
	serviceName := strings.TrimPrefix(r.URL.Path, "/api/build/journals/")
	if serviceName == "" {
		http.Error(w, "Service name required", http.StatusBadRequest)
		return
	}

	switch r.Method {
	case http.MethodGet:
		hash, err := s.GetJournal(r.Context(), serviceName)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"last_hash": hash})
	case http.MethodPut, http.MethodPost:
		var req struct {
			LastHash string `json:"last_hash"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := s.UpdateJournal(r.Context(), serviceName, req.LastHash); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}
