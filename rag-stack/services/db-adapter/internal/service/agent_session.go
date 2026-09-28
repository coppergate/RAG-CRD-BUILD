package service

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/agentsession"
	"app-builds/common/ent/session"
	"app-builds/common/logging"
)

// AgentSessionService resolves the opaque session ids used by coding-agent
// clients (opencode's "ses_7f3a…") onto the int64 session identity the rest of
// the stack keys on. See infrastructure/timescaledb/iteration-12-agent-session.sql.
//
// This lives in db-adapter rather than in each caller so that rag-retrieval and
// any later rag-code-gateway share one implementation and one race resolution.
type AgentSessionService struct {
	client *ent.Client
}

func NewAgentSessionService(client *ent.Client) *AgentSessionService {
	return &AgentSessionService{client: client}
}

type agentSessionRequest struct {
	ExternalID string `json:"external_id"`
	Source     string `json:"source"`
}

type agentSessionResponse struct {
	ExternalID string `json:"external_id"`
	SessionID  int64  `json:"session_id"`
	Source     string `json:"source"`
	Created    bool   `json:"created"`
}

// HandleResolve implements POST /sessions/external — resolve-or-create.
//
// Idempotent: repeated calls with the same external_id return the same
// session_id and only bump last_seen_at.
func (s *AgentSessionService) HandleResolve(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req agentSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid payload"}`, http.StatusBadRequest)
		return
	}

	req.ExternalID = strings.TrimSpace(req.ExternalID)
	if req.ExternalID == "" {
		http.Error(w, `{"error":"external_id is required"}`, http.StatusBadRequest)
		return
	}
	if req.Source == "" {
		req.Source = "opencode"
	}

	sessionID, created, err := s.Resolve(r.Context(), req.ExternalID, req.Source)
	if err != nil {
		logging.Printf("[AGENT-SESSION] resolve failed external_id=%q source=%q: %v",
			req.ExternalID, req.Source, err)
		http.Error(w, `{"error":"failed to resolve agent session"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if created {
		w.WriteHeader(http.StatusCreated)
	}
	_ = json.NewEncoder(w).Encode(agentSessionResponse{
		ExternalID: req.ExternalID,
		SessionID:  sessionID,
		Source:     req.Source,
		Created:    created,
	})
}

// Resolve returns the session id mapped to externalID, creating both the
// underlying session and the mapping row on first sight.
//
// Concurrency: opencode can land two turns of a brand-new session at once. Two
// separate unique constraints can then fire -- sessions.name (we derive it from
// the external id, which usefully enforces one session per agent session) and
// agent_session.external_id. Either one means another writer won the race, so
// both are handled by re-reading rather than by surfacing an error.
func (s *AgentSessionService) Resolve(ctx context.Context, externalID, source string) (int64, bool, error) {
	externalID = strings.TrimSpace(externalID)
	if externalID == "" {
		// Not an error: callers pass through whatever the client sent, and a
		// session-less request retrieves perfectly well.
		return 0, false, nil
	}
	if source == "" {
		source = "opencode"
	}

	if id, ok, err := s.lookup(ctx, externalID); err != nil {
		return 0, false, err
	} else if ok {
		return id, false, nil
	}

	sess, err := s.client.Session.Create().
		SetName(sessionName(externalID)).
		SetLastActiveAt(time.Now()).
		Save(ctx)
	if err != nil {
		// Almost certainly the sessions.name unique constraint: either a
		// concurrent writer got here first, or a session from a previous run
		// survived its mapping.
		if id, ok := s.awaitMapping(ctx, externalID); ok {
			return id, false, nil
		}
		// No mapping appeared, so this is an orphaned session rather than a
		// race. Adopt it instead of failing -- the name already encodes this
		// external id, and creating a second session for it is not possible.
		if id, ok, aerr := s.adopt(ctx, externalID, source); aerr != nil {
			return 0, false, fmt.Errorf("adopt session for %q: %w", externalID, aerr)
		} else if ok {
			return id, true, nil
		}
		return 0, false, fmt.Errorf("create session for %q: %w", externalID, err)
	}

	if err := s.client.AgentSession.Create().
		SetExternalID(externalID).
		SetSource(source).
		SetSessionID(sess.ID).
		SetLastSeenAt(time.Now()).
		Exec(ctx); err != nil {
		// We created a session but could not attach the mapping. If another
		// writer already published one, use theirs and drop our orphan.
		if id, ok := s.awaitMapping(ctx, externalID); ok {
			if delErr := s.client.Session.DeleteOneID(sess.ID).Exec(ctx); delErr != nil {
				logging.Printf("[AGENT-SESSION] orphan session %d cleanup failed: %v", sess.ID, delErr)
			}
			return id, false, nil
		}
		return 0, false, fmt.Errorf("create mapping for %q: %w", externalID, err)
	}

	logging.Printf("[AGENT-SESSION] mapped external_id=%q source=%q -> session_id=%d",
		externalID, source, sess.ID)
	return sess.ID, true, nil
}

// sessionName derives the human-readable session name. It doubles as the
// natural key that makes a duplicate create fail loudly instead of silently
// producing two sessions for one agent session.
func sessionName(externalID string) string {
	return "agent:" + externalID
}

// lookup returns the mapped session id, bumping last_seen_at when found.
func (s *AgentSessionService) lookup(ctx context.Context, externalID string) (int64, bool, error) {
	row, err := s.client.AgentSession.Query().
		Where(agentsession.ExternalID(externalID)).
		WithSession().
		Only(ctx)
	if ent.IsNotFound(err) {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}

	// Best-effort liveness bump; failing it must not fail the lookup, because
	// the mapping it returns is already correct.
	if updErr := s.client.AgentSession.UpdateOne(row).
		SetLastSeenAt(time.Now()).
		Exec(ctx); updErr != nil {
		logging.Printf("[AGENT-SESSION] last_seen_at bump failed external_id=%q: %v", externalID, updErr)
	}

	if row.Edges.Session == nil {
		// The mapping outlived its session (the FK is NO ACTION, so this takes
		// a manual delete upstream). Treat it as absent and let the caller remap.
		logging.Printf("[AGENT-SESSION] mapping %q has no session; treating as unmapped", externalID)
		return 0, false, nil
	}
	return row.Edges.Session.ID, true, nil
}

// awaitMapping re-reads after a lost race. The winner creates the session and
// the mapping in two steps, so a loser can arrive between them and momentarily
// see neither; poll briefly rather than failing a turn over a microsecond gap.
// Bounded so it can never hang a request.
func (s *AgentSessionService) awaitMapping(ctx context.Context, externalID string) (int64, bool) {
	// Short: the gap being covered is two statements wide. Anything longer is
	// an orphan, which adopt() handles, not a race.
	const attempts = 5
	for i := 0; i < attempts; i++ {
		if id, ok, err := s.lookup(ctx, externalID); err == nil && ok {
			return id, true
		}
		select {
		case <-ctx.Done():
			return 0, false
		case <-time.After(20 * time.Millisecond):
		}
	}
	logging.Printf("[AGENT-SESSION] gave up awaiting a concurrent mapping for %q", externalID)
	return 0, false
}

// adopt attaches a mapping to a pre-existing session whose name already encodes
// externalID. Reached when the session outlived its mapping row.
func (s *AgentSessionService) adopt(ctx context.Context, externalID, source string) (int64, bool, error) {
	existing, err := s.client.Session.Query().
		Where(session.Name(sessionName(externalID))).
		Only(ctx)
	if ent.IsNotFound(err) {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}

	if err := s.client.AgentSession.Create().
		SetExternalID(externalID).
		SetSource(source).
		SetSessionID(existing.ID).
		SetLastSeenAt(time.Now()).
		Exec(ctx); err != nil {
		// Someone published the mapping while we were adopting; theirs wins.
		if id, ok := s.awaitMapping(ctx, externalID); ok {
			return id, true, nil
		}
		return 0, false, err
	}

	logging.Printf("[AGENT-SESSION] adopted orphaned session_id=%d for external_id=%q",
		existing.ID, externalID)
	return existing.ID, true, nil
}
