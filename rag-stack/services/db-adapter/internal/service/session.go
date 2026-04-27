package service

import (
	"encoding/json"
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
	Role      string                 `json:"role"`
	Content   string                 `json:"content"`
	Timestamp time.Time              `json:"timestamp"`
	Model     string                 `json:"model,omitempty"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
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
	for _, res := range responses {
		model := ""
		if res.ModelName != nil {
			model = *res.ModelName
		}
		messages = append(messages, ChatMessage{
			Role:      "assistant",
			Content:   res.Content,
			Timestamp: res.CreatedAt,
			Model:     model,
			Metadata:  res.Metadata,
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
		Order(ent.Desc(session.FieldLastActiveAt)).
		All(r.Context())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sessions)
}
