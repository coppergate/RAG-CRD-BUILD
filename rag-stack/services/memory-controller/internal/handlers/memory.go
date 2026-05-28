package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/session"
	"app-builds/common/logging"
	"app-builds/memory-controller/internal/logic"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"strings"
	"time"
)

type SessionResponse struct {
	ID           int64                  `json:"id"`
	Name         string                 `json:"name,omitempty"`
	Description  string                 `json:"description,omitempty"`
	Metadata     map[string]interface{} `json:"metadata,omitempty"`
	CreatedAt    time.Time              `json:"created_at"`
	LastActiveAt time.Time              `json:"last_active_at"`
	Tags         []TagResponse          `json:"tags,omitempty"`
}

type TagResponse struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

func toSessionResponse(s *ent.Session) SessionResponse {
	resp := SessionResponse{
		ID:           s.ID,
		Name:         s.Name,
		Description:  s.Description,
		Metadata:     s.Metadata,
		CreatedAt:    s.CreatedAt,
		LastActiveAt: s.LastActiveAt,
		Tags:         []TagResponse{},
	}
	if s.Edges.Tags != nil {
		for _, t := range s.Edges.Tags {
			resp.Tags = append(resp.Tags, TagResponse{
				ID:   t.ID,
				Name: t.Name,
			})
		}
	}
	return resp
}

type MemoryHandler struct {
	client  *ent.Client
	manager *logic.MemoryManager
}

func NewMemoryHandler(client *ent.Client) *MemoryHandler {
	return &MemoryHandler{
		client:  client,
		manager: logic.NewMemoryManager(client),
	}
}

func (h *MemoryHandler) HandleItems(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.listItems(w, r)
	case http.MethodPost:
		h.writeItems(w, r)
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func (h *MemoryHandler) listItems(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	span := trace.SpanFromContext(ctx)

	sessionIDStr := r.URL.Query().Get("session_id")
	var sessionID int64
	if sessionIDStr != "" {
		sessionID, _ = strconv.ParseInt(sessionIDStr, 10, 64)
	}

	if sessionID > 0 {
		span.SetAttributes(attribute.Int64("session_id", sessionID))
	}

	items, err := h.manager.ListItems(ctx, sessionID)
	if err != nil {
		logging.Printf("[MEMCTRL][SID:%d] Error listing items: %v", sessionID, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(items)
}

func (h *MemoryHandler) writeItems(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	span := trace.SpanFromContext(ctx)
	var req contracts.MemoryWriteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.Scope != nil && req.Scope.SessionId > 0 {
		span.SetAttributes(attribute.Int64("session_id", req.Scope.SessionId))
	}

	if err := h.manager.WriteItems(ctx, &req); err != nil {
		logging.Printf("[MEMCTRL][SID:%d] Failed to write items: %v", req.Scope.SessionId, err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
func (h *MemoryHandler) HandleSessions(w http.ResponseWriter, r *http.Request) {
	logging.Printf("[MEMCTRL] %s %s (session.FieldID=%s)", r.Method, r.URL.Path, session.FieldID)
	switch r.Method {
	case http.MethodGet:
		h.listSessions(w, r)
	case http.MethodPost:
		h.createSession(w, r)
	case http.MethodDelete:
		h.deleteSession(w, r)
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func (h *MemoryHandler) listSessions(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	sessions, err := h.manager.ListSessions(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	resp := make([]SessionResponse, 0, len(sessions))
	for _, s := range sessions {
		resp = append(resp, toSessionResponse(s))
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func (h *MemoryHandler) createSession(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var req struct {
		Id   int64  `json:"id"`
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	s, err := h.manager.CreateSession(ctx, req.Id, req.Name)
	if err != nil {
		logging.Printf("[MEMCTRL] Error creating/updating session: %v", err)
		if strings.Contains(err.Error(), "already exists") {
			http.Error(w, err.Error(), http.StatusConflict)
		} else {
			http.Error(w, "Failed to create/update session: "+err.Error(), http.StatusInternalServerError)
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(toSessionResponse(s))
}

func (h *MemoryHandler) deleteSession(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	idStr := strings.TrimPrefix(r.URL.Path, "/sessions/")
	if idStr == "" || idStr == r.URL.Path {
		idStr = r.URL.Query().Get("id")
	}

	if idStr == "" {
		http.Error(w, "Session ID required", http.StatusBadRequest)
		return
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, "Invalid Session ID", http.StatusBadRequest)
		return
	}

	if err := h.manager.DeleteSession(ctx, id); err != nil {
		logging.Printf("[MEMCTRL] Error deleting session: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *MemoryHandler) HandleRetrieve(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ctx := r.Context()
	span := trace.SpanFromContext(ctx)
	var req struct {
		contracts.MemoryRetrieveRequest
		ActionType string `json:"action_type"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.Scope != nil && req.Scope.SessionId > 0 {
		span.SetAttributes(attribute.Int64("session_id", req.Scope.SessionId))
	}

	pack, err := h.manager.Retrieve(ctx, &req.MemoryRetrieveRequest, req.ActionType)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(pack)
}
