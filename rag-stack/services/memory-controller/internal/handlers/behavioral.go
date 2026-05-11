package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"app-builds/common/ent"
	"app-builds/memory-controller/internal/behavioral"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"app-builds/common/logging"
)

type BehavioralHandler struct {
	manager *behavioral.BehaviorManager
}

func NewBehavioralHandler(client *ent.Client) *BehavioralHandler {
	return &BehavioralHandler{
		manager: behavioral.NewBehaviorManager(client),
	}
}

func (h *BehavioralHandler) HandleRules(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.listRules(w, r)
	case http.MethodPost:
		h.createRule(w, r)
	case http.MethodPatch:
		h.updateRule(w, r)
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func (h *BehavioralHandler) listRules(w http.ResponseWriter, r *http.Request) {
	actionType := r.URL.Query().Get("action_type")
	rules, err := h.manager.ListRules(r.Context(), actionType)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(rules)
}

func (h *BehavioralHandler) createRule(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ActionType  string `json:"action_type"`
		RuleContent string `json:"rule_content"`
		Category    string `json:"category"`
		Priority    int    `json:"priority"`
		Scope       string `json:"scope"`
		State       string `json:"state"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Defaults
	if req.Scope == "" {
		req.Scope = "GLOBAL"
	}
	if req.State == "" {
		req.State = "ACTIVE"
	}

	rule, err := h.manager.CreateRule(r.Context(), req.ActionType, req.RuleContent, req.Category, req.Priority, req.Scope, req.State)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(rule)
}

func (h *BehavioralHandler) updateRule(w http.ResponseWriter, r *http.Request) {
	idStr := strings.TrimPrefix(r.URL.Path, "/behavior/rules/")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, "Invalid rule ID", http.StatusBadRequest)
		return
	}

	var req struct {
		RuleContent string `json:"rule_content"`
		Priority    int    `json:"priority"`
		State       string `json:"state"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	rule, err := h.manager.UpdateRule(r.Context(), id, req.RuleContent, req.Priority, req.State)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(rule)
}

func (h *BehavioralHandler) HandleAudit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		PromptID   string                 `json:"prompt_id"`
		RuleID     int64                  `json:"rule_id"`
		ActionType string                 `json:"action_type"`
		Context    map[string]interface{} `json:"context"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if err := h.manager.LogRuleApplication(r.Context(), req.PromptID, req.RuleID, req.ActionType, req.Context); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

func (h *BehavioralHandler) HandleIdentifiers(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	ids, err := h.manager.GetActionIdentifiers(r.Context())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ids)
}

func (h *BehavioralHandler) HandleLearn(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		Feedback   string `json:"feedback"`
		ActionType string `json:"action_type"`
		Category   string `json:"category"`
		Priority   int    `json:"priority"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	rule, err := h.manager.RecordLearning(r.Context(), req.Feedback, req.ActionType, req.Category, req.Priority)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	logging.Printf("[MEMCTRL] Recorded new learning for %s: %d (State: %s)", req.ActionType, rule.ID, rule.State)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(rule)
}

func (h *BehavioralHandler) HandleSessionOverride(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	ctx := r.Context()
	span := trace.SpanFromContext(ctx)
	var req struct {
		SessionID int64 `json:"session_id"`
		RuleID    int64 `json:"rule_id"`
		Priority  int   `json:"priority"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.SessionID > 0 {
		span.SetAttributes(attribute.Int64("session_id", req.SessionID))
	}
	if err := h.manager.SetSessionOverride(ctx, req.SessionID, req.RuleID, req.Priority); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

func (h *BehavioralHandler) HandleResetSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	ctx := r.Context()
	span := trace.SpanFromContext(ctx)
	var req struct {
		SessionID int64 `json:"session_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.SessionID > 0 {
		span.SetAttributes(attribute.Int64("session_id", req.SessionID))
	}
	if err := h.manager.ClearSessionOverrides(ctx, req.SessionID); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}
