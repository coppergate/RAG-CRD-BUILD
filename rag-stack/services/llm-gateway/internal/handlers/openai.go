package handlers
 
import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/session"
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
		return true // Adjust as needed for security
	},
}

var (
	meter          = telemetry.Meter("llm-gateway")
	requestCounter metric.Int64Counter
	errorCounter   metric.Int64Counter
	latencyHist    metric.Float64Histogram
)

func init() {
	var err error
	requestCounter, err = meter.Int64Counter("gateway_requests_total")
	if err != nil {
		log.Printf("Warning: failed to create request counter metric: %v", err)
	}
	errorCounter, err = meter.Int64Counter("gateway_errors_total")
	if err != nil {
		log.Printf("Warning: failed to create error counter metric: %v", err)
	}
	latencyHist, err = meter.Float64Histogram("gateway_request_duration_ms", metric.WithUnit("ms"))
	if err != nil {
		log.Printf("Warning: failed to create latency histogram metric: %v", err)
	}
}

type OpenAIHandler struct {
	Pulsar pulsar.Client
	Ent    *ent.Client
}

type ChatCompletionRequest struct {
	Model     string   `json:"model"`
	SessionID string   `json:"session_id,omitempty"` // Added for session tracking
	Tags      []string `json:"tags,omitempty"`       // Added for RAG isolation
	Messages  []struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	} `json:"messages"`
}

type GenericChatRequest struct {
	SessionID string   `json:"session_id"`
	Prompt    string   `json:"prompt"`
	Planner   string   `json:"planner"`
	Executor  string   `json:"executor"`
	Tags      []string `json:"tags"`
}

func (h *OpenAIHandler) ensureSession(ctx context.Context, sessionID string) (string, error) {
	if sessionID == "" {
		sessionID = uuid.New().String()
	}

	builder := h.Ent.Session.Create().
		SetName(sessionID).
		SetLastActiveAt(time.Now())

	var upserter *ent.SessionUpsertOne
	if u, err := uuid.Parse(sessionID); err == nil {
		builder.SetID(u)
		upserter = builder.OnConflictColumns(session.FieldID).UpdateLastActiveAt()
	} else {
		upserter = builder.OnConflictColumns(session.FieldName).UpdateLastActiveAt()
	}

	id, err := upserter.ID(ctx)
	if err != nil {
		return sessionID, err
	}
	return id.String(), nil
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
	sessionID, err := h.ensureSession(ctx, req.SessionID)
	if err != nil {
		log.Printf("Failed to ensure session exists: %v", err)
		errorCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("type", "session_ensure")))
		http.Error(w, fmt.Sprintf("Failed to ensure session: %v", err), http.StatusInternalServerError)
		return
	}

	correlationID := uuid.New().String()

	// Save user message to DB via Pulsar event
	if len(req.Messages) > 0 {
		userMsg := req.Messages[len(req.Messages)-1].Content
		if err := h.Pulsar.SendPromptEvent(ctx, correlationID, sessionID, userMsg); err != nil {
			log.Printf("[%s] Failed to send prompt event for session %s: %v", correlationID, sessionID, err)
		}
	}

	// Map to InternalRequest for Pulsar
	var prompt string
	if len(req.Messages) > 0 {
		prompt = req.Messages[len(req.Messages)-1].Content
	}

	internalReq := contracts.InternalRequest{
		ID:            correlationID,
		SessionID:     sessionID,
		Prompt:        prompt,
		PlannerModel:  req.Model,
		ExecutorModel: req.Model,
		Tags:          req.Tags,
		Timestamp:     time.Now().Format(time.RFC3339),
		Metadata: map[string]interface{}{
			"source": "openai-api",
		},
	}

	result, err := h.Pulsar.SendRequest(ctx, correlationID, internalReq)
	if err != nil {
		errorCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("type", "pulsar_send")))
		log.Printf("[%s] Pulsar request failed for session %s: %v", correlationID, sessionID, err)
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
				"message": map[string]string{
					"role":    "assistant",
					"content": result,
				},
				"finish_reason": "stop",
			},
		},
	}
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("[%s] Failed to encode response: %v", correlationID, err)
	}
}

func (h *OpenAIHandler) HandleStreamingChat(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Failed to upgrade to WebSocket: %v", err)
		return
	}
	defer conn.Close()

	ctx := r.Context()
	var req GenericChatRequest
	if err := conn.ReadJSON(&req); err != nil {
		log.Printf("Failed to read JSON from WebSocket: %v", err)
		return
	}

	sessionID, err := h.ensureSession(ctx, req.SessionID)
	if err != nil {
		log.Printf("Failed to ensure session: %v", err)
		return
	}

	correlationID := uuid.New().String()

	// Save user message to DB via Pulsar event
	if err := h.Pulsar.SendPromptEvent(ctx, correlationID, sessionID, req.Prompt); err != nil {
		log.Printf("[%s] Failed to send prompt event for session %s: %v", correlationID, sessionID, err)
	}

	internalReq := contracts.InternalRequest{
		ID:            correlationID,
		SessionID:     sessionID,
		Prompt:        req.Prompt,
		PlannerModel:  req.Planner,
		ExecutorModel: req.Executor,
		Tags:          req.Tags,
		Timestamp:     time.Now().Format(time.RFC3339),
		Stream:        true,
		Metadata: map[string]interface{}{
			"source": "websocket-api",
		},
	}

	// Channel to receive chunks from Pulsar
	chunkChan := make(chan pulsar.StreamChunk, 10)
	h.Pulsar.SubscribeStream(correlationID, chunkChan)
	defer h.Pulsar.UnsubscribeStream(correlationID)

	// Send initial request
	if err := h.Pulsar.SendRawRequest(ctx, internalReq); err != nil {
		log.Printf("Failed to send request to Pulsar: %v", err)
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
			if err := conn.WriteJSON(chunk); err != nil {
				log.Printf("Failed to write to WebSocket: %v", err)
				return
			}
			if chunk.IsLast {
				return
			}
		case <-ctx.Done():
			return
		case <-time.After(60 * time.Second): // Timeout
			log.Printf("[%s] WebSocket stream timed out", correlationID)
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

	var req GenericChatRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad request: "+err.Error(), http.StatusBadRequest)
		return
	}

	// 1. Session tracking
	sessionID, err := h.ensureSession(ctx, req.SessionID)
	if err != nil {
		log.Printf("Failed to ensure session exists: %v", err)
		errorCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("type", "session_ensure")))
		http.Error(w, fmt.Sprintf("Failed to ensure session: %v", err), http.StatusInternalServerError)
		return
	}

	correlationID := uuid.New().String()

	// Save user message to DB via Pulsar event
	if err := h.Pulsar.SendPromptEvent(ctx, correlationID, sessionID, req.Prompt); err != nil {
		log.Printf("[%s] Failed to send prompt event for session %s: %v", correlationID, sessionID, err)
	}

	// Direct mapping to InternalRequest
	internalReq := contracts.InternalRequest{
		ID:            correlationID,
		SessionID:     sessionID,
		Prompt:        req.Prompt,
		PlannerModel:  req.Planner,
		ExecutorModel: req.Executor,
		Tags:          req.Tags,
		Timestamp:     time.Now().Format(time.RFC3339),
		Metadata: map[string]interface{}{
			"source": "generic-api",
		},
	}

	result, err := h.Pulsar.SendRequest(ctx, correlationID, internalReq)
	if err != nil {
		errorCounter.Add(ctx, 1, metric.WithAttributes(attribute.String("type", "pulsar_send")))
		http.Error(w, "Service unavailable: "+err.Error(), http.StatusServiceUnavailable)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	response := map[string]interface{}{
		"id":         correlationID,
		"session_id": sessionID,
		"result":     result,
	}
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("[%s] Failed to encode response: %v", correlationID, err)
	}
}
