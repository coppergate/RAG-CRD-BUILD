package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/common/ent"
	"app-builds/common/ent/inferencenode"
	"app-builds/common/ent/modeldefinition"
	"app-builds/common/ent/prompt"
	"app-builds/common/ent/session"
	"entgo.io/ent/dialect/sql"
	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/google/uuid"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
)

type PulsarProcessor struct {
	client       *ent.Client
	queryCounter metric.Int64Counter
	errorCounter metric.Int64Counter
	queryLatency metric.Float64Histogram
}

func NewPulsarProcessor(client *ent.Client, qc metric.Int64Counter, ec metric.Int64Counter, ql metric.Float64Histogram) *PulsarProcessor {
	return &PulsarProcessor{
		client:       client,
		queryCounter: qc,
		errorCounter: ec,
		queryLatency: ql,
	}
}

func (p *PulsarProcessor) HandleDBOp(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	start := time.Now()
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	msgCtx, span := tracer.Start(msgCtx, "HandleDBOp")
	defer span.End()

	attrs := []attribute.KeyValue{attribute.String("op", "delete_session")}
	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		if p.queryLatency != nil {
			p.queryLatency.Record(msgCtx, duration, metric.WithAttributes(attrs...))
		}
	}()
	if p.queryCounter != nil {
		p.queryCounter.Add(msgCtx, 1, metric.WithAttributes(attrs...))
	}

	var payload struct {
		Op string `json:"op"`
		ID string `json:"id"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal DB op payload: %w", err)
	}

	if payload.Op == "delete_session" {
		sessID, parseErr := uuid.Parse(payload.ID)
		if parseErr != nil {
			if p.errorCounter != nil {
				p.errorCounter.Add(msgCtx, 1, metric.WithAttributes(attrs...))
			}
			return dlq.PermanentFailure, fmt.Errorf("invalid UUID in delete_session: %q: %w", payload.ID, parseErr)
		}
		_, err := p.client.Session.Delete().
			Where(session.ID(sessID)).
			Exec(ctx)
		if err != nil {
			if p.errorCounter != nil {
				p.errorCounter.Add(msgCtx, 1, metric.WithAttributes(attrs...))
			}
			return dlq.TransientFailure, fmt.Errorf("delete session %s: %w", payload.ID, err)
		}
		log.Printf("Deleted session %s via Pulsar op", payload.ID)
	}

	return dlq.Success, nil
}

func (p *PulsarProcessor) HandlePrompt(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	_, span := tracer.Start(msgCtx, "HandlePrompt")
	defer span.End()

	var payload struct {
		ID        string `json:"id"`
		SessionID string `json:"session_id"`
		Content   string `json:"content"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal prompt payload: %w", err)
	}

	promptID, parseErr := uuid.Parse(payload.ID)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid prompt UUID: %q: %w", payload.ID, parseErr)
	}
	sessID, parseErr := uuid.Parse(payload.SessionID)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid session UUID: %q: %w", payload.SessionID, parseErr)
	}

	_, err := p.client.Prompt.Create().
		SetPromptID(promptID).
		SetSessionID(sessID).
		SetContent(payload.Content).
		Save(ctx)
	if err != nil {
		log.Printf("Failed to insert prompt %s for session %s: %v", payload.ID, payload.SessionID, err)
		return dlq.TransientFailure, fmt.Errorf("insert prompt: %w", err)
	}

	log.Printf("Inserted prompt %s for session %s", payload.ID, payload.SessionID)
	return dlq.Success, nil
}

func (p *PulsarProcessor) HandleResponse(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	_, span := tracer.Start(msgCtx, "HandleResponse")
	defer span.End()

	var payload struct {
		contracts.StreamChunk
		Result   string                 `json:"result"`
		Metadata map[string]interface{} `json:"metadata"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal response payload: %w", err)
	}

	if payload.StreamChunk.Metadata == nil && payload.Metadata != nil {
		payload.StreamChunk.Metadata = payload.Metadata
	}

	if payload.Result == "" {
		if payload.Chunk != "" {
			return dlq.Success, nil
		}
		return dlq.Success, nil
	}

	log.Printf("Processing response: ID=%s, SessionID=%s, Model=%s", payload.ID, payload.SessionID, payload.Model)

	promptUUID, parseErr := uuid.Parse(payload.ID)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid prompt UUID in response: %q: %w", payload.ID, parseErr)
	}

	pr, err := p.client.Prompt.Query().
		Where(prompt.PromptID(promptUUID)).
		Order(ent.Desc(prompt.FieldCreatedAt)).
		First(ctx)
	if err != nil {
		return dlq.TransientFailure, fmt.Errorf("find prompt for response (ID %s): %w", payload.ID, err)
	}

	var sessID uuid.UUID
	if payload.SessionID != "" {
		sessID, parseErr = uuid.Parse(payload.SessionID)
		if parseErr != nil {
			log.Printf("Invalid session UUID in response: %q, falling back to prompt session: %v", payload.SessionID, parseErr)
			sessID = pr.SessionID
		}
	} else {
		sessID = pr.SessionID
	}

	var modelName *string
	if payload.Model != "" {
		modelName = &payload.Model
	}

	_, err = p.client.Response.Create().
		SetPromptID(pr.ID).
		SetSessionID(sessID).
		SetContent(payload.Result).
		SetSequenceNumber(payload.SequenceNumber).
		SetNillableModelName(modelName).
		SetMetadata(payload.StreamChunk.Metadata).
		Save(ctx)
	if err != nil {
		return dlq.TransientFailure, fmt.Errorf("insert response for prompt %s: %w", payload.ID, err)
	}

	log.Printf("Inserted response for prompt %s (seq %d)", payload.ID, payload.SequenceNumber)
	return dlq.Success, nil
}

func (p *PulsarProcessor) HandleCompletion(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	_, span := tracer.Start(msgCtx, "HandleCompletion")
	defer span.End()

	var payload contracts.ResponseCompletion
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal completion payload: %w", err)
	}

	if payload.Metrics == nil {
		return dlq.Success, nil
	}

	m := payload.Metrics
	sessID, _ := uuid.Parse(payload.SessionID)
	respID, _ := uuid.Parse(payload.ID)

	modelID, err := p.client.ModelDefinition.Create().
		SetModelName(payload.Model).
		SetFamily(m.ModelFamily).
		OnConflict(
			sql.ConflictColumns(modeldefinition.FieldModelName),
		).
		UpdateNewValues().
		ID(ctx)
	if err != nil {
		log.Printf("Failed to upsert model definition: %v", err)
	}

	hostname := m.Hostname
	if hostname == "" {
		hostname = "unknown"
	}
	nodeID, err := p.client.InferenceNode.Create().
		SetHostname(hostname).
		OnConflict(
			sql.ConflictColumns(inferencenode.FieldHostname),
		).
		UpdateNewValues().
		ID(ctx)
	if err != nil {
		log.Printf("Failed to upsert inference node: %v", err)
	}

	_, err = p.client.ModelExecutionMetric.Create().
		SetNillableResponseID(&respID).
		SetNillableSessionID(&sessID).
		SetNillableNodeID(&nodeID).
		SetNillableModelID(&modelID).
		SetPromptTokens(m.PromptTokens).
		SetCompletionTokens(m.CompletionTokens).
		SetTotalTokens(m.PromptTokens + m.CompletionTokens).
		SetTotalDurationUsec(m.TotalDurationUsec).
		SetLoadDurationUsec(m.LoadDurationUsec).
		SetPromptEvalDurationUsec(m.PromptEvalDurationUsec).
		SetEvalDurationUsec(m.EvalDurationUsec).
		SetTokensPerSecond(float32(m.TokensPerSecond)).
		Save(ctx)

	if err != nil {
		log.Printf("Failed to insert execution metrics: %v", err)
		return dlq.TransientFailure, err
	}

	log.Printf("Stored execution metrics for response %s", payload.ID)
	return dlq.Success, nil
}
