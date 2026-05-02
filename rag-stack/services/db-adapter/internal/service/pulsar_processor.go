package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"google.golang.org/protobuf/encoding/protojson"

	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/common/ent"
	"app-builds/common/ent/inferencenode"
	"app-builds/common/ent/modelexecutionmetric"
	"app-builds/common/ent/modeldefinition"
	"app-builds/common/ent/prompt"
	"app-builds/common/ent/response"
	"app-builds/common/ent/retrievallog"
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

	log.Printf("Received DB op message: %s", string(msg.Payload()))

	attrs := []attribute.KeyValue{attribute.String("op", "unknown")}
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
		Id string `json:"id"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal DB op payload: %w", err)
	}

	attrs[0] = attribute.String("op", payload.Op)

	if payload.Op == "delete_session" {
		sessID, parseErr := uuid.Parse(payload.Id)
		if parseErr != nil {
			log.Printf("Invalid UUID for delete_session: %q", payload.Id)
			return dlq.PermanentFailure, fmt.Errorf("invalid UUID in delete_session: %q: %w", payload.Id, parseErr)
		}

		log.Printf("Attempting to delete session %s and its dependents", sessID)

		tx, err := p.client.Tx(msgCtx)
		if err != nil {
			return dlq.TransientFailure, fmt.Errorf("start tx for delete session: %w", err)
		}
		defer func() {
			if r := recover(); r != nil {
				tx.Rollback()
				panic(r)
			}
		}()

		// Delete metrics
		_, err = tx.ModelExecutionMetric.Delete().Where(modelexecutionmetric.SessionID(sessID)).Exec(msgCtx)
		if err != nil { log.Printf("Warning: failed to delete metrics for session %s: %v", sessID, err) }

		// Delete retrieval logs
		_, err = tx.RetrievalLog.Delete().Where(retrievallog.SessionID(sessID)).Exec(msgCtx)
		if err != nil { log.Printf("Warning: failed to delete retrieval logs for session %s: %v", sessID, err) }

		// Delete prompts & responses (using raw SQL as they don't have edges in Ent)
		// Assuming 'prompts' and 'responses' are the table names.
		// Note: Ent might use singular/plural names.
		_, err = tx.Prompt.Delete().Where(prompt.SessionID(sessID)).Exec(msgCtx)
		if err != nil { log.Printf("Warning: failed to delete prompts for session %s: %v", sessID, err) }

		_, err = tx.Response.Delete().Where(response.SessionID(sessID)).Exec(msgCtx)
		if err != nil { log.Printf("Warning: failed to delete responses for session %s: %v", sessID, err) }

		// Finally delete the session
		_, err = tx.Session.Delete().Where(session.ID(sessID)).Exec(msgCtx)
		if err != nil {
			tx.Rollback()
			log.Printf("Error deleting session %s: %v", sessID, err)
			return dlq.TransientFailure, fmt.Errorf("delete session %s: %w", payload.Id, err)
		}

		if err := tx.Commit(); err != nil {
			return dlq.TransientFailure, fmt.Errorf("commit delete session %s: %w", sessID, err)
		}

		log.Printf("Successfully deleted session %s and dependents via Pulsar op", sessID)
	} else {
		log.Printf("Unknown DB op: %s", payload.Op)
	}

	return dlq.Success, nil
}

func (p *PulsarProcessor) sanitizeString(s string) string {
	return strings.ReplaceAll(s, "\x00", "")
}

func (p *PulsarProcessor) ensureSessionExists(ctx context.Context, sessionID uuid.UUID) error {
	if sessionID == uuid.Nil {
		return nil
	}
	// Upsert session to handle FK constraints for out-of-order messages
	return p.client.Session.Create().
		SetID(sessionID).
		OnConflict(
			sql.ConflictColumns(session.FieldID),
		).
		Ignore().
		Exec(ctx)
}

func (p *PulsarProcessor) HandlePrompt(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	msgCtx, span := tracer.Start(msgCtx, "HandlePrompt")
	defer span.End()

	var payload struct {
		Id        string `json:"id"`
		SessionId string `json:"session_id"`
		Content   string `json:"content"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal prompt payload: %w", err)
	}

	promptID, parseErr := uuid.Parse(payload.Id)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid prompt UUID: %q: %w", payload.Id, parseErr)
	}
	sessID, parseErr := uuid.Parse(payload.SessionId)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid session UUID: %q: %w", payload.SessionId, parseErr)
	}

	content := p.sanitizeString(payload.Content)

	if err := p.ensureSessionExists(msgCtx, sessID); err != nil {
		return dlq.TransientFailure, fmt.Errorf("ensure session exists: %w", err)
	}

	// Try to find if a ghost prompt already exists for this ID
	existing, err := p.client.Prompt.Query().
		Where(prompt.PromptID(promptID)).
		Order(ent.Desc(prompt.FieldCreatedAt)).
		First(msgCtx)

	if err == nil {
		if existing.Content == "[PENDING]" {
			_, err = p.client.Prompt.UpdateOne(existing).
				SetContent(content).
				SetSessionID(sessID).
				Save(msgCtx)
			if err != nil {
				return dlq.TransientFailure, fmt.Errorf("update ghost prompt: %w", err)
			}
			log.Printf("Updated ghost prompt %s with content", payload.Id)
			return dlq.Success, nil
		}
		log.Printf("Prompt %s already exists with content, skipping", payload.Id)
		return dlq.Success, nil
	}

	_, err = p.client.Prompt.Create().
		SetPromptID(promptID).
		SetSessionID(sessID).
		SetContent(content).
		Save(msgCtx)
	if err != nil {
		log.Printf("Failed to insert prompt %s for session %s: %v", payload.Id, payload.SessionId, err)
		return dlq.TransientFailure, fmt.Errorf("insert prompt: %w", err)
	}

	log.Printf("Inserted prompt %s for session %s", payload.Id, payload.SessionId)
	return dlq.Success, nil
}

func (p *PulsarProcessor) HandleResponse(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	msgCtx, span := tracer.Start(msgCtx, "HandleResponse")
	defer span.End()

	var payload contracts.StreamChunk
	if err := protojson.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal response payload: %w", err)
	}

	if payload.Result == "" && payload.PlanningResponse == "" {
		return dlq.Success, nil
	}

	log.Printf("Processing response: ID=%s, SessionID=%s, Model=%s", payload.Id, payload.SessionId, payload.Model)

	promptUUID, parseErr := uuid.Parse(payload.Id)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid prompt UUID in response: %q: %w", payload.Id, parseErr)
	}
	respID := promptUUID

	var sessID uuid.UUID
	if payload.SessionId != "" {
		sessID, _ = uuid.Parse(payload.SessionId)
	}

	pr, err := p.client.Prompt.Query().
		Where(prompt.PromptID(promptUUID)).
		Order(ent.Desc(prompt.FieldCreatedAt)).
		First(msgCtx)

	if err != nil {
		isNotFound := ent.IsNotFound(err)
		if !isNotFound && err != nil && strings.Contains(err.Error(), "not found") {
			isNotFound = true
		}

		if isNotFound {
			log.Printf("Prompt %s not found for response, creating ghost prompt", payload.Id)

			if err := p.ensureSessionExists(msgCtx, sessID); err != nil {
				return dlq.TransientFailure, fmt.Errorf("ensure session exists for ghost prompt: %w", err)
			}

			// Create a ghost prompt to handle out-of-order arrival
			ghost, err := p.client.Prompt.Create().
				SetPromptID(promptUUID).
				SetSessionID(sessID).
				SetContent("[PENDING]").
				Save(msgCtx)
			if err != nil {
				// Could be a race where it was just created
				return dlq.TransientFailure, fmt.Errorf("failed to create ghost prompt: %w", err)
			}
			pr = ghost
		} else {
			return dlq.TransientFailure, fmt.Errorf("find prompt for response (ID %s): %w", payload.Id, err)
		}
	}

	if sessID == uuid.Nil {
		sessID = pr.SessionID
	}

	var modelName *string
	if payload.Model != "" {
		modelName = &payload.Model
	}

	result := p.sanitizeString(payload.Result)

	// Use a transaction to find or create a single response record per prompt_id.
	// This ensures we aggregate chunks into one record instead of multiple.
	tx, err := p.client.Tx(msgCtx)
	if err != nil {
		return dlq.TransientFailure, fmt.Errorf("failed to start transaction: %w", err)
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
			panic(r)
		}
	}()

	existing, err := tx.Response.Query().
		Where(response.PromptID(pr.ID)).
		First(msgCtx)

		if ent.IsNotFound(err) {
			// Create new record
			_, err = tx.Response.Create().
				SetResponseID(respID).
				SetPromptID(pr.ID).
				SetSessionID(sessID).
				SetContent(result).
				SetPlanningResponse(payload.PlanningResponse).
				SetSequenceNumber(int(payload.SequenceNumber)).
				SetNillableModelName(modelName).
				SetMetadata(contracts.FromStruct(payload.Metadata)).
				Save(msgCtx)
		if err != nil {
			tx.Rollback()
			return dlq.TransientFailure, fmt.Errorf("create response in tx: %w", err)
		}
		if err := tx.Commit(); err != nil {
			return dlq.TransientFailure, fmt.Errorf("commit create response: %w", err)
		}
	} else if err != nil {
		tx.Rollback()
		return dlq.TransientFailure, fmt.Errorf("query existing response in tx: %w", err)
	} else {
		// Update existing record
		u := tx.Response.UpdateOne(existing)
		if payload.PlanningResponse != "" {
			newPR := ""
			if existing.PlanningResponse != nil {
				newPR = *existing.PlanningResponse + "\n"
			}
			newPR += payload.PlanningResponse
			u.SetPlanningResponse(newPR)
		}
		if payload.Result != "" {
			if payload.IsLast {
				// Aggregated final result from prompt-aggregator (or final chunk)
				u.SetContent(result)
			} else {
				// Delta chunk from worker, append it
				u.SetContent(existing.Content + result)
			}
		}
		if modelName != nil {
			u.SetNillableModelName(modelName)
		}
		u.SetSequenceNumber(int(payload.SequenceNumber))
		u.SetMetadata(contracts.FromStruct(payload.Metadata))
		if err := u.Exec(msgCtx); err != nil {
			tx.Rollback()
			return dlq.TransientFailure, fmt.Errorf("update response in tx: %w", err)
		}
		if err := tx.Commit(); err != nil {
			return dlq.TransientFailure, fmt.Errorf("commit update response: %w", err)
		}
	}

	if err != nil {
		return dlq.TransientFailure, fmt.Errorf("transactional upsert response for prompt %s: %w", payload.Id, err)
	}

	log.Printf("Aggregated response for prompt %s (seq %d, last=%v)", payload.Id, payload.SequenceNumber, payload.IsLast)

	// Process retrieval logs if it's the last chunk and metadata has contexts
	if payload.IsLast {
		metadataMap := contracts.FromStruct(payload.Metadata)
		if contexts, ok := metadataMap["contexts"].([]interface{}); ok && len(contexts) > 0 {
			for _, c := range contexts {
				if ctxStr, ok := c.(string); ok && ctxStr != "" {
					_, _ = p.client.RetrievalLog.Create().
						SetSessionID(sessID).
						SetType("RETRIEVAL").
						SetDetail(ctxStr).
						Save(msgCtx)
				}
			}
			log.Printf("Stored %d retrieval logs for session %s", len(contexts), sessID)
		}
	}

	return dlq.Success, nil
}

func (p *PulsarProcessor) HandleCompletion(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	_, span := tracer.Start(msgCtx, "HandleCompletion")
	defer span.End()

	log.Printf("Received completion event for processing")

	var payload contracts.ResponseCompletion
	if err := protojson.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal completion payload: %w", err)
	}

	if payload.Metrics == nil {
		return dlq.Success, nil
	}

	m := payload.Metrics
	sessID, _ := uuid.Parse(payload.SessionId)
	respID, _ := uuid.Parse(payload.Id)

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
		SetPromptTokens(int(m.PromptTokens)).
		SetCompletionTokens(int(m.CompletionTokens)).
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

	log.Printf("Stored execution metrics for response %s", payload.Id)
	return dlq.Success, nil
}
