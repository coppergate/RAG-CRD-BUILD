package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/session"
	"app-builds/common/logging"
	"app-builds/common/telemetry"
	"app-builds/llm-gateway/internal/pulsar"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true
		}
		// Allow configured internal domain (env: WEBSOCKET_ORIGIN_DOMAIN, default: .hierocracy.home)
		domain := os.Getenv("WEBSOCKET_ORIGIN_DOMAIN")
		if domain == "" {
			domain = ".hierocracy.home"
		}
		if strings.HasSuffix(origin, domain) {
			return true
		}
		// Allow localhost for debugging
		if strings.HasPrefix(origin, "http://localhost") || strings.HasPrefix(origin, "http://127.0.0.1") {
			return true
		}
		return false
	},
}

var (
	meter          = telemetry.Meter("llm-gateway")
	requestCounter metric.Int64Counter
	errorCounter   metric.Int64Counter
	latencyHist    metric.Float64Histogram
	promptSizeHist metric.Int64Histogram
)

func init() {
	var err error
	requestCounter, err = meter.Int64Counter("gateway_requests_total")
	if err != nil {
		logging.Printf("Warning: failed to create request counter metric: %v", err)
	}
	errorCounter, err = meter.Int64Counter("gateway_errors_total")
	if err != nil {
		logging.Printf("Warning: failed to create error counter metric: %v", err)
	}
	latencyHist, err = meter.Float64Histogram("gateway_request_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		logging.Printf("Warning: failed to create latency histogram metric: %v", err)
	}
	promptSizeHist, err = meter.Int64Histogram("gateway_prompt_size_bytes", metric.WithUnit("By"))
	if err != nil {
		logging.Printf("Warning: failed to create prompt size histogram: %v", err)
	}
}

type OpenAIHandler struct {
	Pulsar        pulsar.Client
	Ent           *ent.Client
	StreamTimeout time.Duration
}

type ChatCompletionRequest struct {
	Model          string  `json:"model"`
	SessionId      int64   `json:"session_id,omitempty"`   // Changed to int64
	SessionName    string  `json:"session_name,omitempty"` // Added for friendly name
	Tags           []int64 `json:"tags,omitempty"`         // Changed to int64
	EmbeddingModel string  `json:"embedding_model,omitempty"`
	IncludeGlobal  bool    `json:"include_global,omitempty"`
	Messages       []struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	} `json:"messages"`
}

type GenericChatRequest struct {
	SessionId      int64   `json:"session_id"` // Changed to int64
	SessionName    string  `json:"session_name,omitempty"`
	Prompt         string  `json:"prompt"`
	Planner        string  `json:"planner"`
	Executor       string  `json:"executor"`
	EmbeddingModel string  `json:"embedding_model,omitempty"`
	Tags           []int64 `json:"tags"` // Changed to int64
	IncludeGlobal  bool    `json:"include_global,omitempty"`
}

func validateChatCompletionRequest(req ChatCompletionRequest) error {
	if strings.TrimSpace(req.Model) == "" {
		return fmt.Errorf("model is required")
	}
	if len(req.Messages) == 0 {
		return fmt.Errorf("messages are required")
	}
	lastMessage := req.Messages[len(req.Messages)-1]
	if strings.TrimSpace(lastMessage.Content) == "" {
		return fmt.Errorf("messages must include non-empty content")
	}
	return nil
}

func (h *OpenAIHandler) ensureSession(ctx context.Context, sessionID int64, sessionName string, tags []int64) (*ent.Session, error) {
	if sessionName == "" {
		if sessionID > 0 {
			sessionName = fmt.Sprintf("Session %d", sessionID)
		} else {
			sessionName = fmt.Sprintf("Chat %s %s", time.Now().Format("15:04:05"), uuid.New().String()[:4])
		}
	}

	builder := h.Ent.Session.Create().
		SetName(sessionName).
		SetLastActiveAt(time.Now())

	if sessionID > 0 {
		builder.SetID(sessionID)
	}

	id, err := builder.OnConflictColumns(session.FieldID).
		UpdateLastActiveAt().
		UpdateName().
		ID(ctx)

	if err != nil {
		return nil, err
	}

	// If tags provided, associate them with the session
	if len(tags) > 0 {
		err = h.Ent.Session.UpdateOneID(id).
			AddTagIDs(tags...).
			Exec(ctx)
		if err != nil {
			logging.Printf("Warning: failed to associate tags with session %d: %v", id, err)
		}
	}

	// Return session with tags
	return h.Ent.Session.Query().
		Where(session.ID(id)).
		WithTags().
		Only(ctx)
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

	if r.Method != http.MethodPost {
		logging.Printf("Method not allowed: %s %s", r.Method, r.URL.Path)
		requestCounter.Add(ctx, 1, metric.WithAttributes(attrs...))
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MiB
	var req ChatCompletionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logging.Printf("Bad request: %v", err)
		requestCounter.Add(ctx, 1, metric.WithAttributes(attrs...))
		http.Error(w, "Bad request: "+err.Error(), http.StatusBadRequest)
		return
	}
	if err := validateChatCompletionRequest(req); err != nil {
		logging.Printf("Bad request: %v", err)
		requestCounter.Add(ctx, 1, metric.WithAttributes(attrs...))
		http.Error(w, "Bad request: "+err.Error(), http.StatusBadRequest)
		return
	}

	logging.Printf(
		"[chat-completions] session_id=%d session_name=%q tags=%v include_global=%v",
		req.SessionId,
		req.SessionName,
		req.Tags,
		req.IncludeGlobal,
	)

	// 1. Session tracking
	sess, err := h.ensureSession(ctx, req.SessionId, req.SessionName, req.Tags)
	if err != nil {
		logging.Printf("Failed to ensure session exists: %v", err)
		errorCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("type", "session_ensure")))
		http.Error(w, fmt.Sprintf("Failed to ensure session: %v", err), http.StatusInternalServerError)
		return
	}
	sessionID := sess.ID

	// Add session_id to telemetry
	attrs = append(attrs, attribute.Int64("session_id", sessionID))
	span.SetAttributes(attribute.Int64("session_id", sessionID))

	requestCounter.Add(ctx, 1, metric.WithAttributes(attrs...))

	// Fetch all tags for the session and preserve the request tags if the
	// session association has not been materialized yet.
	var sessionTags []int64
	for _, t := range sess.Edges.Tags {
		sessionTags = append(sessionTags, t.ID)
	}
	effectiveTags := sessionTags
	if len(effectiveTags) == 0 && len(req.Tags) > 0 {
		effectiveTags = req.Tags
	}

	// Record prompt size
	var prompt string
	if len(req.Messages) > 0 {
		prompt = req.Messages[len(req.Messages)-1].Content
	}
	promptSizeHist.Record(ctx, int64(len(prompt)), metric.WithAttributes(attrs...))

	correlationID := uuid.New().String()

	// Save user message to DB via Pulsar event
	if len(req.Messages) > 0 {
		userMsg := req.Messages[len(req.Messages)-1].Content
		if err := h.Pulsar.SendPromptEvent(ctx, correlationID, sessionID, userMsg, effectiveTags); err != nil {
			logging.Printf("[%s][SID:%d] Failed to send prompt event: %v", correlationID, sessionID, err)
		}
	}

	internalReq := &contracts.InternalRequest{
		Id:             correlationID,
		SessionId:      sessionID,
		SessionName:    req.SessionName,
		Prompt:         prompt,
		PlannerModel:   req.Model,
		ExecutorModel:  req.Model,
		EmbeddingModel: req.EmbeddingModel,
		Tags:           effectiveTags,
		IncludeGlobal:  req.IncludeGlobal,
		Timestamp:      time.Now().Format(time.RFC3339),
		Metadata: contracts.ToStruct(map[string]interface{}{
			"source":        "openai-api",
			"selected_tags": effectiveTags,
			"session_tags":  sessionTags,
		}),
	}

	logging.Printf(
		"[chat-completions] correlation_id=%s session_id=%d effective_tags=%v prompt_len=%d",
		correlationID,
		sessionID,
		effectiveTags,
		len(prompt),
	)

	result, err := h.Pulsar.SendRequest(ctx, correlationID, internalReq)
	if err != nil {
		errorCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("type", "pulsar_send")))
		logging.Printf("[%s][SID:%d] Pulsar request failed: %v", correlationID, sessionID, err)
		http.Error(w, "Service unavailable: "+err.Error(), http.StatusServiceUnavailable)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	response := map[string]interface{}{
		"id":         "chatcmpl-" + correlationID,
		"object":     "chat.completion",
		"created":    time.Now().Unix(),
		"model":      req.Model,
		"session_id": sessionID,
		"choices": []map[string]interface{}{
			{
				"index": 0,
				"message": map[string]interface{}{
					"role":              "assistant",
					"content":           result.Result,
					"planning_response": result.PlanningResponse,
				},
				"finish_reason": "stop",
			},
		},
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(response); err != nil {
		logging.Printf("[%s][SID:%d] Failed to encode response: %v", correlationID, sessionID, err)
	}
}

func (h *OpenAIHandler) HandleStreamingChat(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		logging.Printf("Failed to upgrade to WebSocket: %v", err)
		return
	}
	defer conn.Close()

	ctx := r.Context()
	telemetry.RecordSessionStart(ctx)
	defer telemetry.RecordSessionEnd(ctx)

	var req GenericChatRequest
	if err := conn.ReadJSON(&req); err != nil {
		logging.Printf("Failed to read JSON from WebSocket: %v", err)
		return
	}

	logging.Printf(
		"[chat-stream] session_id=%d session_name=%q tags=%v include_global=%v planner=%q executor=%q",
		req.SessionId,
		req.SessionName,
		req.Tags,
		req.IncludeGlobal,
		req.Planner,
		req.Executor,
	)

	sess, err := h.ensureSession(ctx, req.SessionId, req.SessionName, req.Tags)
	if err != nil {
		logging.Printf("Failed to ensure session: %v", err)
		return
	}
	sessionID := sess.ID

	// Fetch all tags for the session and fall back to the request tags if the
	// session association has not been persisted yet.
	var sessionTags []int64
	for _, t := range sess.Edges.Tags {
		sessionTags = append(sessionTags, t.ID)
	}
	effectiveTags := sessionTags
	if len(effectiveTags) == 0 && len(req.Tags) > 0 {
		effectiveTags = req.Tags
	}

	// Record prompt size
	promptSizeHist.Record(ctx, int64(len(req.Prompt)), metric.WithAttributes(attribute.String("method", "WS"), attribute.String("path", "/v1/rag/stream")))

	correlationID := uuid.New().String()

	// Save user message to DB via Pulsar event
	if err := h.Pulsar.SendPromptEvent(ctx, correlationID, sessionID, req.Prompt, effectiveTags); err != nil {
		logging.Printf("[%s] Failed to send prompt event for session %d: %v", correlationID, sessionID, err)
	}

	internalReq := &contracts.InternalRequest{
		Id:             correlationID,
		SessionId:      sessionID,
		SessionName:    req.SessionName,
		Prompt:         req.Prompt,
		PlannerModel:   req.Planner,
		ExecutorModel:  req.Executor,
		EmbeddingModel: req.EmbeddingModel,
		Tags:           effectiveTags,
		IncludeGlobal:  req.IncludeGlobal,
		Timestamp:      time.Now().Format(time.RFC3339),
		Stream:         true,
		Metadata: contracts.ToStruct(map[string]interface{}{
			"source":        "websocket-api",
			"selected_tags": effectiveTags,
			"session_tags":  sessionTags,
		}),
	}

	logging.Printf(
		"[chat-stream] correlation_id=%s session_id=%d effective_tags=%v prompt_len=%d",
		correlationID,
		sessionID,
		effectiveTags,
		len(req.Prompt),
	)

	// Channel to receive chunks from Pulsar
	chunkChan := make(chan *contracts.StreamChunk, 10)
	h.Pulsar.SubscribeStream(correlationID, chunkChan)
	defer h.Pulsar.UnsubscribeStream(correlationID)

	// Send initial request
	if err := h.Pulsar.SendRawRequest(ctx, internalReq); err != nil {
		logging.Printf("Failed to send request to Pulsar: %v", err)
		conn.WriteJSON(map[string]string{"error": "Failed to send request to backend"})
		return
	}

	// Stream chunks to WebSocket
	for {
		select {
		case chunk, ok := <-chunkChan:
			if !ok {
				return
			}
			if chunk.SequenceNumber == 0 {
				logging.Printf("[%s] Forwarding Seq 0, has metadata: %v", correlationID, chunk.Metadata != nil)
			}
			if err := conn.WriteJSON(chunk); err != nil {
				logging.Printf("Failed to write to WebSocket: %v", err)
				return
			}
			if chunk.IsLast {
				return
			}
		case <-ctx.Done():
			return
		case <-time.After(h.StreamTimeout):
			logging.Printf("[%s] WebSocket stream timed out after %v", correlationID, h.StreamTimeout)
			conn.WriteJSON(map[string]interface{}{"error": "stream timeout", "is_last": true})
			return
		}
	}
}

func (h *OpenAIHandler) HandleGenericChat(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	ctx := r.Context()
	tracer := otel.Tracer("llm-gateway")
	ctx, span := tracer.Start(ctx, "HandleGenericChat")
	defer span.End()

	attrs := []attribute.KeyValue{
		attribute.String("method", r.Method),
		attribute.String("path", "/v1/rag/chat"),
	}

	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		latencyHist.Record(ctx, duration, metric.WithAttributes(attrs...))
	}()

	requestCounter.Add(ctx, 1, metric.WithAttributes(attrs...))

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MiB
	var req GenericChatRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad request: "+err.Error(), http.StatusBadRequest)
		return
	}

	logging.Printf(
		"[generic-chat] session_id=%d session_name=%q tags=%v include_global=%v planner=%q executor=%q",
		req.SessionId,
		req.SessionName,
		req.Tags,
		req.IncludeGlobal,
		req.Planner,
		req.Executor,
	)

	// 1. Session tracking
	sess, err := h.ensureSession(ctx, req.SessionId, req.SessionName, req.Tags)
	if err != nil {
		logging.Printf("Failed to ensure session exists: %v", err)
		errorCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("type", "session_ensure")))
		http.Error(w, fmt.Sprintf("Failed to ensure session: %v", err), http.StatusInternalServerError)
		return
	}
	sessionID := sess.ID

	logging.Printf("Ensured session id : %d", sessionID)

	// Fetch all tags for the session and preserve the request tags if the
	// session association has not been materialized yet.
	var sessionTags []int64
	for _, t := range sess.Edges.Tags {
		sessionTags = append(sessionTags, t.ID)
	}

	logging.Printf("got session tags: %v", sessionTags)

	effectiveTags := sessionTags
	if len(effectiveTags) == 0 && len(req.Tags) > 0 {
		effectiveTags = req.Tags
	}

	logging.Printf("setting effective tags: %v", effectiveTags)

	// Record prompt size
	promptSizeHist.Record(ctx, int64(len(req.Prompt)), metric.WithAttributes(attrs...))

	correlationID := uuid.New().String()

	// Save user message to DB via Pulsar event
	if err := h.Pulsar.SendPromptEvent(ctx, correlationID, sessionID, req.Prompt, effectiveTags); err != nil {
		logging.Printf("[%s] Failed to send prompt event for session %d: %v", correlationID, sessionID, err)
	}

	logging.Printf("sent the prompt event for session %d with correlation ID %s", sessionID, correlationID)

	if req.Planner == "" {
		req.Planner = "llama3.1:latest"
	}
	if req.Executor == "" {
		req.Executor = "llama3.1:latest"
	}
	logging.Printf("have set planner and executor to %s and %s", req.Planner, req.Executor)

	internalReq := &contracts.InternalRequest{
		Id:             correlationID,
		SessionId:      sessionID,
		SessionName:    req.SessionName,
		Prompt:         req.Prompt,
		PlannerModel:   req.Planner,
		ExecutorModel:  req.Executor,
		EmbeddingModel: req.EmbeddingModel,
		Tags:           effectiveTags,
		IncludeGlobal:  req.IncludeGlobal,
		Timestamp:      time.Now().Format(time.RFC3339),
		Metadata: contracts.ToStruct(map[string]interface{}{
			"source":        "generic-api",
			"selected_tags": effectiveTags,
			"session_tags":  sessionTags,
		}),
	}

	logging.Printf(
		"[generic-chat] correlation_id=%s session_id=%d effective_tags=%v prompt_len=%d",
		correlationID,
		sessionID,
		effectiveTags,
		len(req.Prompt),
	)

	result, err := h.Pulsar.SendRequest(ctx, correlationID, internalReq)
	if err != nil {
		errorCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("type", "pulsar_send")))
		http.Error(w, "Service unavailable: "+err.Error(), http.StatusServiceUnavailable)
		return
	}
	logging.Printf("sent the request to pulsar for session %d with correlation ID %s", sessionID, correlationID)

	w.Header().Set("Content-Type", "application/json")
	response := map[string]interface{}{
		"id":                correlationID,
		"session_id":        sessionID,
		"result":            result.Result,
		"planning_response": result.PlanningResponse,
	}
	if err := json.NewEncoder(w).Encode(response); err != nil {
		logging.Printf("[%s] Failed to encode response: %v", correlationID, err)
	}
}
