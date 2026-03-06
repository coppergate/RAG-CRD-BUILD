package handlers

import (
    "database/sql"
    "encoding/json"
    "log"
    "net/http"
    "time"

   	"app-builds/llm-gateway/internal/pulsar"
   	"app-builds/common/telemetry"
   	"github.com/google/uuid"
   	"go.opentelemetry.io/otel"
   	"go.opentelemetry.io/otel/attribute"
   	"go.opentelemetry.io/otel/metric"
   )

   var (
   	meter          = telemetry.Meter("llm-gateway")
   	requestCounter, _ = meter.Int64Counter("gateway_requests_total")
   	errorCounter, _   = meter.Int64Counter("gateway_errors_total")
   	latencyHist, _    = meter.Float64Histogram("gateway_request_duration_ms", metric.WithUnit("ms"))
   )

type OpenAIHandler struct {
	Pulsar *pulsar.PulsarClient
	DB     *sql.DB
}

type ChatCompletionRequest struct {
	Model     string `json:"model"`
	SessionID string `json:"session_id,omitempty"` // Added for session tracking
	Messages  []struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	} `json:"messages"`
}

func (h *OpenAIHandler) HandleChatCompletions(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	ctx := r.Context()
	tracer := otel.Tracer("llm-gateway")
	ctx, span := tracer.Start(ctx, "HandleChatCompletions")
	defer span.End()

	attrs := []attribute.KeyValue{
		attribute.String("method", r.Method),
		attribute.String("path", "/v1/chat/completions"),
	}

	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		latencyHist.Record(ctx, duration, metric.WithAttributes(attrs...))
	}()

	requestCounter.Add(ctx, 1, metric.WithAttributes(attrs...))

	if r.Method != http.MethodPost {
		log.Printf("Method not allowed: %s %s", r.Method, r.URL.Path)
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ChatCompletionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Bad request: %v", err)
		http.Error(w, "Bad request: "+err.Error(), http.StatusBadRequest)
		return
	}

	// 1. Session tracking
	sessionID := req.SessionID
	if sessionID == "" {
		sessionID = uuid.New().String()
	}

	// Ensure session exists and update last_active_at
	// (Session management might be moved to a dedicated service, but keeping for now)
	_, err := h.DB.Exec(`
		INSERT INTO sessions (name, last_active_at) 
		VALUES ($1, now()) 
		ON CONFLICT (name) DO UPDATE SET last_active_at = now()`,
		sessionID)
	if err != nil {
		log.Printf("Failed to ensure session exists: %v", err)
	}

	// Get the actual UUID for the session
	var actualSessionID string
	err = h.DB.QueryRow("SELECT session_id FROM sessions WHERE name = $1 LIMIT 1", sessionID).Scan(&actualSessionID)
	if err == nil {
		sessionID = actualSessionID
	}

	correlationID := uuid.New().String()

	// Save user message to DB via Pulsar event
	if len(req.Messages) > 0 {
		userMsg := req.Messages[len(req.Messages)-1].Content
		if err := h.Pulsar.SendPromptEvent(ctx, correlationID, sessionID, userMsg); err != nil {
			log.Printf("[%s] Failed to send prompt event for session %s: %v", correlationID, sessionID, err)
		}
	}

	// Wrap the request for Pulsar
	pulsarPayload := map[string]interface{}{
		"id":         correlationID,
		"session_id": sessionID,
		"type":       "chat_completion",
		"payload":    req,
		"timestamp":  time.Now().Format(time.RFC3339),
	}

	result, err := h.Pulsar.SendRequest(ctx, correlationID, pulsarPayload)
	if err != nil {
		errorCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("type", "pulsar_send")))
		log.Printf("[%s] Pulsar request failed for session %s: %v", correlationID, sessionID, err)
		http.Error(w, "Service unavailable: "+err.Error(), http.StatusServiceUnavailable)
		return
	}

	// For simplicity, we assume 'result' is already the raw content or a JSON we can proxy
	w.Header().Set("Content-Type", "application/json")

	// Minimal OpenAI-like response
	response := map[string]interface{}{
		"id":         "chatcmpl-" + correlationID,
		"object":     "chat.completion",
		"created":    time.Now().Unix(),
		"model":      req.Model,
		"session_id": sessionID,
		"choices": []map[string]interface{}{
			{
				"index": 0,
				"message": map[string]string{
					"role":    "assistant",
					"content": result,
				},
				"finish_reason": "stop",
			},
		},
	}
	json.NewEncoder(w).Encode(response)
}
