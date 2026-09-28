package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"app-builds/common/logging"
)

var validKinds = map[string]struct{}{
	"user_turn":      {},
	"tool_result":    {},
	"assistant_turn": {},
}

// HandleIngestTurn implements POST /v1/rag/ingest/turn.
//
// Fire-and-forget by contract: it publishes to Pulsar and returns 202 without
// waiting for anything downstream. The plugin calls this from hooks that must
// not block a coding turn, so a slow or dead consumer must not be felt here.
func (h *Handler) HandleIngestTurn(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "use POST")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, h.Cfg.MaxBodyBytes)
	var req IngestTurnRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "could not decode request body: "+err.Error())
		return
	}

	if v := r.Header.Get("X-RAG-Session"); v != "" {
		req.Session = v
	}
	if v := r.Header.Get("X-RAG-Project"); v != "" {
		req.Project = v
	}

	req.Text = strings.TrimSpace(req.Text)
	if req.Text == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "text is required")
		return
	}
	if req.Kind == "" {
		req.Kind = "user_turn"
	}
	if _, ok := validKinds[req.Kind]; !ok {
		writeError(w, http.StatusBadRequest, "invalid_request",
			"kind must be one of user_turn, tool_result, assistant_turn")
		return
	}

	if !h.Cfg.IngestEnabled || h.Publisher == nil {
		// Explicitly acknowledge that the turn was accepted and dropped, rather
		// than pretending it was stored.
		writeJSON(w, http.StatusAccepted, map[string]any{
			"accepted": false,
			"reason":   "turn ingest is disabled on this deployment (RAG_INGEST_ENABLED=false)",
		})
		return
	}

	// Resolve the session id so the downstream consumer does not have to. This
	// is the one blocking call here, and it is cached after first sight.
	var sessionID int64
	if req.Session != "" {
		ctx, cancel := context.WithTimeout(r.Context(), h.Cfg.MemoryTimeout)
		id, err := h.Sessions.Resolve(ctx, req.Session, "opencode")
		cancel()
		if err != nil {
			// Publish anyway, carrying the external id. A turn without an int64
			// session is still useful; losing it is not.
			logging.Printf("[retrieval/ingest] session mapping failed session=%q: %v", req.Session, err)
		}
		sessionID = id
	}

	payload := map[string]any{
		"external_session": req.Session,
		"session_id":       sessionID,
		"project":          req.Project,
		"kind":             req.Kind,
		"tool":             req.Tool,
		"text":             req.Text,
		"metadata":         req.Metadata,
		"received_at":      time.Now().UTC().Format(time.RFC3339Nano),
	}

	if err := h.Publisher.Publish(h.Cfg.IngestTurnTopic, payload); err != nil {
		logging.Printf("[retrieval/ingest] publish failed topic=%q kind=%q: %v",
			h.Cfg.IngestTurnTopic, req.Kind, err)
		writeError(w, http.StatusServiceUnavailable, "publish_failed", "could not enqueue turn")
		return
	}

	logging.Printf("[retrieval/ingest] accepted kind=%q tool=%q session=%q session_id=%d chars=%d",
		req.Kind, req.Tool, req.Session, sessionID, len(req.Text))

	writeJSON(w, http.StatusAccepted, map[string]any{
		"accepted":   true,
		"session_id": sessionID,
	})
}
