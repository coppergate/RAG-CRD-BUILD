package handlers

import (
	"net/http"

	"app-builds/common/logging"
	"app-builds/rag-retrieval/internal/tags"
)

// HandleTags implements GET /v1/rag/tags — the tag inventory, for UI and for
// checking that a configured tag name actually exists before relying on it.
func (h *Handler) HandleTags(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "use GET")
		return
	}

	all, err := h.Tags.All(r.Context())
	if err != nil {
		logging.Printf("[retrieval/tags] listing failed: %v", err)
		writeError(w, http.StatusBadGateway, "tags_unavailable", "could not list tags: "+err.Error())
		return
	}
	// A nil slice marshals to null; clients branch on length, so keep it [].
	if all == nil {
		all = []tags.Tag{}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"tags":  all,
		"count": len(all),
		// The convention from spec §10.5, echoed so a client can see which tags
		// this deployment will reach for by default per profile.
		"profile_defaults": map[string]any{
			"planner":  h.Cfg.PlannerTags,
			"executor": h.Cfg.ExecutorTags,
		},
	})
}
