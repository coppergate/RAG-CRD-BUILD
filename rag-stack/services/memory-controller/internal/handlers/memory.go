package handlers

import (
	"encoding/json"
	"net/http"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/memoryitem"
	"github.com/google/uuid"
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
