package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/memoryitem"
	"app-builds/common/ent/prompt"
	"app-builds/common/ent/response"
	"app-builds/common/ent/session"
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
		sessionID, err := strconv.ParseInt(sessionIDStr, 10, 64)
		if err == nil {
			query = query.Where(memoryitem.SessionID(sessionID))
		}
	}
	
	items, err := query.All(ctx)
	if err != nil {
		log.Printf("[MEMCTRL] Error listing items: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if items == nil {
		items = []*ent.MemoryItem{}
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
			SetMemoryType(item.MemoryType).
			SetSummary(item.Summary).
			SetContent(item.Content).
			SetSalience(item.SalienceHint).
			SetRetentionScore(item.RetentionHint).
			SetPinned(item.Pinned).
			SetMetadata(contracts.FromStruct(item.Metadata))
		
		if req.Scope.SessionId > 0 {
			builder = builder.SetSessionID(req.Scope.SessionId)
		}

		if req.Scope.ProjectId > 0 {
			builder = builder.SetProjectID(req.Scope.ProjectId)
		}
		
		mi, err := builder.Save(ctx)
		if err != nil {
			log.Printf("[MEMCTRL] Failed to save memory item: %v", err)
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
					"source_id":     ref.SourceId,
					"relation_type": ref.RelationType,
				}).
				SaveX(ctx)
		}
		
		// Log event
		tx.MemoryEvent.Create().
			SetMemoryItemID(mi.ID).
			SetEventType("write").
			SetEventData(map[string]interface{}{
				"request_id":     req.RequestId,
				"correlation_id": req.CorrelationId,
			}).
			SaveX(ctx)
	}
	
	if err := tx.Commit(); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
func (h *MemoryHandler) HandleSessions(w http.ResponseWriter, r *http.Request) {
	log.Printf("[MEMCTRL] %s %s (session.FieldID=%s)", r.Method, r.URL.Path, session.FieldID)
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
	if sessions == nil {
		sessions = []*ent.Session{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sessions)
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

	// Check if name already exists for a DIFFERENT session ID
	if req.Name != "" {
		existing, err := h.client.Session.Query().
			Where(session.Name(req.Name)).
			First(ctx)
		if err == nil && existing != nil {
			// If name exists and ID is either not provided or different from existing
			if req.Id == 0 || existing.ID != req.Id {
				http.Error(w, "Session name already exists", http.StatusConflict)
				return
			}
		}
	}

	builder := h.client.Session.Create().
		SetName(req.Name).
		SetLastActiveAt(time.Now())

	if req.Id > 0 {
		builder.SetID(req.Id)
	}

	// Use upsert to be safe for ID conflict
	s, err := builder.OnConflictColumns(session.FieldID).
		UpdateLastActiveAt().
		UpdateName().
		ID(ctx)
	if err != nil {
		log.Printf("[MEMCTRL] Error creating/updating session: %v", err)
		if strings.Contains(err.Error(), "unique constraint") || strings.Contains(err.Error(), "duplicate key") {
			http.Error(w, "Session name already exists", http.StatusConflict)
		} else {
			http.Error(w, "Failed to create/update session: "+err.Error(), http.StatusInternalServerError)
		}
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

	id, err := strconv.ParseInt(idStr, 10, 64)
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

func (h *MemoryHandler) HandleRetrieve(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ctx := r.Context()
	var req contracts.MemoryRetrieveRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	sessionID := req.Scope.SessionId
	if sessionID == 0 {
		http.Error(w, "Session ID required in scope", http.StatusBadRequest)
		return
	}

	limit := req.Limit
	if limit <= 0 {
		limit = 10
	}

	// 1. Fetch relevant MemoryItems
	mItems, err := h.client.MemoryItem.Query().
		Where(memoryitem.SessionID(sessionID)).
		Order(ent.Desc(memoryitem.FieldCreatedAt)).
		Limit(int(limit)).
		All(ctx)
	if err != nil {
		log.Printf("[MEMCTRL] Error fetching memory items: %v", err)
	}

	// 2. Fetch Chat History (Prompts and Responses)
	prompts, err := h.client.Prompt.Query().
		Where(prompt.SessionID(sessionID)).
		Order(ent.Desc(prompt.FieldCreatedAt)).
		Limit(int(limit)).
		All(ctx)
	if err != nil {
		log.Printf("[MEMCTRL] Error fetching prompts: %v", err)
	}

	// Fetch responses for these prompts
	var promptIDs []int64
	for _, p := range prompts {
		promptIDs = append(promptIDs, p.ID)
	}

	responses, err := h.client.Response.Query().
		Where(response.PromptIDIn(promptIDs...)).
		All(ctx)
	if err != nil {
		log.Printf("[MEMCTRL] Error fetching responses: %v", err)
	}

	respMap := make(map[int64]*ent.Response)
	for _, res := range responses {
		if res.PromptID != 0 {
			respMap[res.PromptID] = res
		}
	}

	// 3. Assemble MemoryPack
	pack := &contracts.MemoryPack{
		Items: []*contracts.MemoryWriteItem{},
	}

	// Add MemoryItems
	for _, mi := range mItems {
		pack.Items = append(pack.Items, &contracts.MemoryWriteItem{
			MemoryId:      mi.ID,
			MemoryType:    mi.MemoryType,
			Summary:       mi.Summary,
			Content:       mi.Content,
			SalienceHint:  mi.Salience,
			RetentionHint: mi.RetentionScore,
			Pinned:        mi.Pinned,
			Metadata:      contracts.ToStruct(mi.Metadata),
		})
	}

	// Add History (interleaved if possible, but simplest is just pairs)
	// We want to return them in chronological order for the LLM
	for i := len(prompts) - 1; i >= 0; i-- {
		p := prompts[i]
		pack.Items = append(pack.Items, &contracts.MemoryWriteItem{
			MemoryType: "chat_history",
			Content:    p.Content,
			Metadata: contracts.ToStruct(map[string]interface{}{
				"role":      "user",
				"timestamp": p.CreatedAt.Format(time.RFC3339),
				"id":        p.PromptID.String(),
			}),
		})

		if res, ok := respMap[p.ID]; ok {
			pack.Items = append(pack.Items, &contracts.MemoryWriteItem{
				MemoryType: "chat_history",
				Content:    res.Content,
				Metadata: contracts.ToStruct(map[string]interface{}{
					"role":      "assistant",
					"timestamp": res.CreatedAt.Format(time.RFC3339),
					"id":        res.ResponseID.String(),
				}),
			})
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(pack)
}
