package service

import (
	"encoding/json"
	"log"
	"net/http"
	"sort"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/prompt"
	"app-builds/common/ent/response"
	"app-builds/common/ent/session"
	"github.com/google/uuid"
)

type SessionService struct {
	client *ent.Client
}

func NewSessionService(client *ent.Client) *SessionService {
	return &SessionService{client: client}
}

type ChatMessage struct {
	Role             string                 `json:"role"`
	Content          string                 `json:"content"`
	PlanningResponse string                 `json:"planning_response,omitempty"`
	Timestamp        time.Time              `json:"timestamp"`
	Model            string                 `json:"model,omitempty"`
	Metadata         map[string]interface{} `json:"metadata,omitempty"`
}

func (s *SessionService) GetMessages(w http.ResponseWriter, r *http.Request, sessionIDStr string) {
	ctx := r.Context()
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		http.Error(w, "Invalid session ID", http.StatusBadRequest)
		return
	}

	prompts, err := s.client.Prompt.Query().
		Where(prompt.SessionID(sessionID)).
		Order(ent.Asc(prompt.FieldCreatedAt)).
		All(ctx)
	if err != nil {
		http.Error(w, "Failed to query prompts: "+err.Error(), http.StatusInternalServerError)
		return
	}

	responses, err := s.client.Response.Query().
		Where(response.SessionID(sessionID)).
		Order(ent.Asc(response.FieldCreatedAt)).
		All(ctx)
	if err != nil {
		http.Error(w, "Failed to query responses: "+err.Error(), http.StatusInternalServerError)
		return
	}

	var messages []ChatMessage
	for _, p := range prompts {
		messages = append(messages, ChatMessage{
			Role:      "user",
			Content:   p.Content,
			Timestamp: p.CreatedAt,
		})
	}

	// Group responses by prompt_id to handle legacy duplicates/chunks
	responsesByPrompt := make(map[int64]*ent.Response)
	for _, res := range responses {
		if res.PromptID == 0 {
			continue
		}
		pid := res.PromptID
		if existing, ok := responsesByPrompt[pid]; ok {
			// Take the longest content (likely the final aggregated result)
			if len(res.Content) > len(existing.Content) {
				// Preserve planning response if it was in an earlier chunk but missing here
				if (res.PlanningResponse == nil || *res.PlanningResponse == "") && 
				   (existing.PlanningResponse != nil && *existing.PlanningResponse != "") {
					res.PlanningResponse = existing.PlanningResponse
				}
				responsesByPrompt[pid] = res
			} else if (res.PlanningResponse != nil && *res.PlanningResponse != "") && 
			          (existing.PlanningResponse == nil || *existing.PlanningResponse == "") {
				existing.PlanningResponse = res.PlanningResponse
			}
		} else {
			responsesByPrompt[pid] = res
		}
	}

	for _, res := range responsesByPrompt {
		model := ""
		if res.ModelName != nil {
			model = *res.ModelName
		}
		planningResponse := ""
		if res.PlanningResponse != nil {
			planningResponse = *res.PlanningResponse
		}
		messages = append(messages, ChatMessage{
			Role:             "assistant",
			Content:          res.Content,
			PlanningResponse: planningResponse,
			Timestamp:        res.CreatedAt,
			Model:            model,
			Metadata:         res.Metadata,
		})
	}

	sort.SliceStable(messages, func(i, j int) bool {
		return messages[i].Timestamp.Before(messages[j].Timestamp)
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(messages)
}

func (s *SessionService) ListSessions(w http.ResponseWriter, r *http.Request) {
	sessions, err := s.client.Session.Query().
		WithTags().
		Order(ent.Desc(session.FieldLastActiveAt)).
		All(r.Context())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sessions)
}

func (s *SessionService) UpdateSessionTags(w http.ResponseWriter, r *http.Request) {
	sessionIDStr := r.URL.Query().Get("session_id")
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		http.Error(w, "Invalid session ID", http.StatusBadRequest)
		return
	}

	var payload struct {
		TagIDs []string `json:"tag_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, "Invalid payload", http.StatusBadRequest)
		return
	}

	var tagUUIDs []uuid.UUID
	for _, idStr := range payload.TagIDs {
		id, err := uuid.Parse(idStr)
		if err == nil {
			tagUUIDs = append(tagUUIDs, id)
		}
	}

	// Update session tags (replace existing)
	err = s.client.Session.UpdateOneID(sessionID).
		ClearTags().
		AddTagIDs(tagUUIDs...).
		Exec(r.Context())

	if err != nil {
		http.Error(w, "Failed to update tags: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (s *SessionService) DeleteSession(w http.ResponseWriter, r *http.Request, sessionIDStr string) {
	ctx := r.Context()
	log.Printf("[SESSION] Deleting session ID: %s", sessionIDStr)
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		http.Error(w, "Invalid session ID", http.StatusBadRequest)
		return
	}

	// Delete associated metrics first (if not handled by cascade)
	// Based on schema.sql, sessions have ON DELETE CASCADE for prompts, responses, session_tag.
	// We'll just delete the session and let the DB handle cascades.
	err = s.client.Session.DeleteOneID(sessionID).Exec(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			w.WriteHeader(http.StatusNoContent) // Already gone
			return
		}
		http.Error(w, "Failed to delete session: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
