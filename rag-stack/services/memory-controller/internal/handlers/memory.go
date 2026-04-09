package handlers

import (
	"encoding/json"
	"net/http"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/memoryitem"
	"app-builds/common/ent/session"
	"github.com/google/uuid"
	"strings"
	"time"
)

type MemoryHandler struct {
	client *ent.Client
}

func NewMemoryHandler(client *ent.Client) *MemoryHandler {
	return &MemoryHandler{client: client}
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
	
	sessionIDStr := r.URL.Query().Get("session_id")
	query := h.client.MemoryItem.Query()
	
	if sessionIDStr != "" {
		sessionID, err := uuid.Parse(sessionIDStr)
		if err == nil {
			query = query.Where(memoryitem.SessionID(sessionID))
		}
	}
	
	items, err := query.All(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(items)
}

func (h *MemoryHandler) writeItems(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var req contracts.MemoryWriteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	
	tx, err := h.client.Tx(ctx)
	if err != nil {
		http.Error(w, "Failed to start transaction", http.StatusInternalServerError)
		return
	}
	
	for _, item := range req.Writes {
		builder := tx.MemoryItem.Create().
			SetType(item.MemoryType).
			SetSummary(item.Summary).
			SetContent(item.Content).
			SetSalience(item.SalienceHint).
			SetRetentionScore(item.RetentionHint).
			SetPinning(item.Pinned).
			SetMetadata(item.Metadata)
		
		if req.Scope.SessionID != "" {
			sid, _ := uuid.Parse(req.Scope.SessionID)
			builder = builder.SetSessionID(sid)
		}
		
		mi, err := builder.Save(ctx)
		if err != nil {
			tx.Rollback()
			http.Error(w, "Failed to save memory item: "+err.Error(), http.StatusInternalServerError)
			return
		}
		
		// Create links
		for _, ref := range item.SourceRefs {
			tx.MemoryLink.Create().
				SetMemoryItemID(mi.ID).
				SetTags(req.Scope.Tags).
				// Store extra data in Metadata if needed
				SetMetadata(map[string]interface{}{
					"source_kind":   ref.SourceKind,
					"source_id":     ref.SourceID,
					"relation_type": ref.RelationType,
				}).
				SaveX(ctx)
		}
		
		// Log event
		tx.MemoryEvent.Create().
			SetMemoryItemID(mi.ID).
			SetEventType("write").
			SetEventData(map[string]interface{}{
				"request_id": req.RequestID,
				"correlation_id": req.CorrelationID,
			}).
			SaveX(ctx)
	}
	
	if err := tx.Commit(); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}
	
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
func (h *MemoryHandler) HandleSessions(w http.ResponseWriter, r *http.Request) {
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
	sessions, err := h.client.Session.Query().
		Order(ent.Desc(session.FieldLastActiveAt)).
		All(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sessions)
}

func (h *MemoryHandler) createSession(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var req struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Check if name already exists for a DIFFERENT session ID
	if req.Name != "" {
		existing, err := h.client.Session.Query().
			Where(session.Name(req.Name)).
			First(ctx)
		if err == nil && existing != nil {
			// If name exists and ID is either not provided or different from existing
			if req.ID == "" || existing.ID.String() != req.ID {
				http.Error(w, "Session name already exists", http.StatusConflict)
				return
			}
		}
	}

	builder := h.client.Session.Create().
		SetName(req.Name).
		SetLastActiveAt(time.Now())

	if req.ID != "" {
		if sid, err := uuid.Parse(req.ID); err == nil {
			builder.SetID(sid)
		}
	}

	// Use upsert to be safe for ID conflict
	upserter := builder.OnConflictColumns(session.FieldID).
		UpdateLastActiveAt().
		UpdateName()

	s, err := upserter.ID(ctx)
	if err != nil {
		http.Error(w, "Failed to create/update session: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Fetch the full session to return
	fullSession, err := h.client.Session.Get(ctx, s)
	if err != nil {
		http.Error(w, "Failed to fetch created session: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(fullSession)
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

	id, err := uuid.Parse(idStr)
	if err != nil {
		http.Error(w, "Invalid Session ID", http.StatusBadRequest)
		return
	}

	// Delete session and its items
	tx, err := h.client.Tx(ctx)
	if err != nil {
		http.Error(w, "Failed to start transaction", http.StatusInternalServerError)
		return
	}

	_, err = tx.MemoryItem.Delete().
		Where(memoryitem.SessionID(id)).
		Exec(ctx)
	if err != nil {
		tx.Rollback()
		http.Error(w, "Failed to delete memory items: "+err.Error(), http.StatusInternalServerError)
		return
	}

	err = tx.Session.DeleteOneID(id).Exec(ctx)
	if err != nil {
		tx.Rollback()
		http.Error(w, "Failed to delete session: "+err.Error(), http.StatusInternalServerError)
		return
	}

	if err := tx.Commit(); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
