package service

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"google.golang.org/protobuf/encoding/protojson"

	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/common/ent"
	"app-builds/common/ent/inferencenode"
	"app-builds/common/ent/modeldefinition"
	"app-builds/common/ent/modelexecutionmetric"
	"app-builds/common/ent/prompt"
	"app-builds/common/ent/response"
	"app-builds/common/ent/retrievallog"
	"app-builds/common/ent/session"
	"app-builds/common/logging"
	"app-builds/common/telemetry"
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

	var payload struct {
		Op        string `json:"op"`
		Id        string `json:"id"`
		SessionId int64  `json:"session_id"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal DB op payload: %w", err)
	}

	logging.Printf("[SID:%d] Received DB op message: %s", payload.SessionId, string(msg.Payload()))

	attrs := []attribute.KeyValue{
		attribute.String("op", payload.Op),
		attribute.Int64("session_id", payload.SessionId),
	}
	span.SetAttributes(attrs...)

	defer func() {
		duration := float64(time.Since(start).Milliseconds())
		if p.queryLatency != nil {
			p.queryLatency.Record(msgCtx, duration, metric.WithAttributes(attrs...))
		}
	}()
	if p.queryCounter != nil {
		p.queryCounter.Add(msgCtx, 1, metric.WithAttributes(attrs...))
	}

	if payload.Op == "delete_session" {
		sessID, parseErr := strconv.ParseInt(payload.Id, 10, 64)
		if parseErr != nil {
			logging.Printf("Invalid ID for delete_session: %q", payload.Id)
			return dlq.PermanentFailure, fmt.Errorf("invalid ID in delete_session: %q: %w", payload.Id, parseErr)
		}

		logging.Printf("Attempting to delete session %d and its dependents", sessID)

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
		if err != nil {
			logging.Printf("Warning: failed to delete metrics for session %d: %v", sessID, err)
		}

		// Delete retrieval logs
		_, err = tx.RetrievalLog.Delete().Where(retrievallog.SessionID(sessID)).Exec(msgCtx)
		if err != nil {
			logging.Printf("Warning: failed to delete retrieval logs for session %d: %v", sessID, err)
		}

		// Delete prompts & responses (using raw SQL as they don't have edges in Ent)
		// Assuming 'prompts' and 'responses' are the table names.
		// Note: Ent might use singular/plural names.
		_, err = tx.Prompt.Delete().Where(prompt.SessionID(sessID)).Exec(msgCtx)
		if err != nil {
			logging.Printf("Warning: failed to delete prompts for session %d: %v", sessID, err)
		}

		_, err = tx.Response.Delete().Where(response.SessionID(sessID)).Exec(msgCtx)
		if err != nil {
			logging.Printf("Warning: failed to delete responses for session %d: %v", sessID, err)
		}

		// Finally delete the session
		_, err = tx.Session.Delete().Where(session.ID(sessID)).Exec(msgCtx)
		if err != nil {
			tx.Rollback()
			logging.Printf("Error deleting session %d: %v", sessID, err)
			return dlq.TransientFailure, fmt.Errorf("delete session %d: %w", sessID, err)
		}

		if err := tx.Commit(); err != nil {
			return dlq.TransientFailure, fmt.Errorf("commit delete session %d: %w", sessID, err)
		}

		logging.Printf("Successfully deleted session %d and dependents via Pulsar op", sessID)
	} else {
		logging.Printf("Unknown DB op: %s", payload.Op)
	}

	return dlq.Success, nil
}

func (p *PulsarProcessor) sanitizeString(s string) string {
	return strings.ReplaceAll(s, "\x00", "")
}

func (p *PulsarProcessor) cloneMetadata(src map[string]interface{}) map[string]interface{} {
	if src == nil {
		return map[string]interface{}{}
	}

	out := make(map[string]interface{}, len(src))
	for k, v := range src {
		out[k] = v
	}
	return out
}

func (p *PulsarProcessor) mergeMetadata(
	base map[string]interface{},
	update map[string]interface{},
) map[string]interface{} {
	merged := p.cloneMetadata(base)
	for k, v := range update {
		merged[k] = v
	}
	return merged
}

func (p *PulsarProcessor) hasContentSegment(metadata map[string]interface{}) bool {
	for _, seg := range p.extractResponseSegments(metadata) {
		if m, ok := seg.(map[string]interface{}); ok {
			if kind, _ := m["kind"].(string); kind == "content" {
				return true
			}
		}
	}
	return false
}

func (p *PulsarProcessor) hasResponseSegments(metadata map[string]interface{}) bool {
	if metadata == nil {
		return false
	}
	raw, ok := metadata["message_segments"]
	if !ok {
		return false
	}
	switch v := raw.(type) {
	case []interface{}:
		return len(v) > 0
	case []map[string]interface{}:
		return len(v) > 0
	default:
		return false
	}
}

func (p *PulsarProcessor) extractResponseSegments(metadata map[string]interface{}) []interface{} {
	if metadata == nil {
		return []interface{}{}
	}

	raw, ok := metadata["message_segments"]
	if !ok {
		return []interface{}{}
	}

	switch v := raw.(type) {
	case []interface{}:
		out := make([]interface{}, len(v))
		copy(out, v)
		return out
	case []map[string]interface{}:
		out := make([]interface{}, 0, len(v))
		for _, segment := range v {
			out = append(out, segment)
		}
		return out
	default:
		return []interface{}{}
	}
}

func (p *PulsarProcessor) appendResponseSegments(
	metadata map[string]interface{},
	planningResponse string,
	result string,
	sequenceNumber int32,
	isLast bool,
	existingHasSegments bool,
	inConversation bool,
	allowFinalContentSegment bool,
) map[string]interface{} {
	merged := p.cloneMetadata(metadata)
	segments := p.extractResponseSegments(merged)

	if planningResponse != "" {
		segments = append(segments, map[string]interface{}{
			"kind":            "planning",
			"content":         planningResponse,
			"sequence_number": sequenceNumber,
			"is_last":         isLast,
			"in_conversation": inConversation,
		})
	}

	if result != "" {
		shouldAppendContent := !isLast || allowFinalContentSegment || !existingHasSegments
		if shouldAppendContent {
			segments = append(segments, map[string]interface{}{
				"kind":            "content",
				"content":         result,
				"sequence_number": sequenceNumber,
				"is_last":         isLast,
				"in_conversation": inConversation,
			})
		}
	}

	if len(segments) > 0 {
		merged["message_segments"] = segments
	}

	return merged
}

func (p *PulsarProcessor) ensureSessionExists(ctx context.Context, sessionID int64) error {
	if sessionID == 0 {
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
	telemetry.RecordMessage(msgCtx, "user")
	tracer := otel.Tracer("db-adapter")
	msgCtx, span := tracer.Start(msgCtx, "HandlePrompt")
	defer span.End()

	var payload struct {
		Id        string  `json:"id"`
		SessionId int64   `json:"session_id"`
		Content   string  `json:"content"`
		Tags      []int64 `json:"tags"`
	}
	if err := json.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal prompt payload: %w", err)
	}

	promptID, parseErr := uuid.Parse(payload.Id)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid prompt UUID: %q: %w", payload.Id, parseErr)
	}
	sessID := payload.SessionId

	content := p.sanitizeString(payload.Content)

	if err := p.ensureSessionExists(msgCtx, sessID); err != nil {
		return dlq.TransientFailure, fmt.Errorf("ensure session exists: %w", err)
	}

	// Update session tags if provided in prompt
	if len(payload.Tags) > 0 {
		err := p.client.Session.UpdateOneID(sessID).
			AddTagIDs(payload.Tags...).
			Exec(msgCtx)
		if err != nil {
			logging.Printf("Warning: failed to associate tags with session %d from prompt: %v", sessID, err)
		}
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
			logging.Printf("Updated ghost prompt %s with content", payload.Id)
			return dlq.Success, nil
		}
		logging.Printf("Prompt %s already exists with content, skipping", payload.Id)
		return dlq.Success, nil
	}

	_, err = p.client.Prompt.Create().
		SetPromptID(promptID).
		SetSessionID(sessID).
		SetContent(content).
		Save(msgCtx)
	if err != nil {
		logging.Printf("Failed to insert prompt %s for session %d: %v", payload.Id, payload.SessionId, err)
		return dlq.TransientFailure, fmt.Errorf("insert prompt: %w", err)
	}

	logging.Printf("Inserted prompt %s for session %d", payload.Id, payload.SessionId)
	return dlq.Success, nil
}

func (p *PulsarProcessor) HandleResponse(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	telemetry.RecordMessage(msgCtx, "assistant")
	tracer := otel.Tracer("db-adapter")
	msgCtx, span := tracer.Start(msgCtx, "HandleResponse")
	defer span.End()

	var payload contracts.StreamChunk
	if err := protojson.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal response payload: %w", err)
	}

	if payload.Result == "" && payload.PlanningResponse == "" && payload.Metadata == nil && payload.SequenceNumber != 0 {
		return dlq.Success, nil
	}

	logging.Printf("Processing response: ID=%s, SessionID=%d, Model=%s", payload.Id, payload.SessionId, payload.Model)

	promptUUID, parseErr := uuid.Parse(payload.Id)
	if parseErr != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid prompt UUID in response: %q: %w", payload.Id, parseErr)
	}
	respID := promptUUID

	var sessID int64
	if payload.SessionId != 0 {
		sessID = payload.SessionId
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
			logging.Printf("Prompt %s not found for response, creating ghost prompt", payload.Id)

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

	if sessID == 0 {
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
		metadataMap := contracts.FromStruct(payload.Metadata)
		metadataMap = p.appendResponseSegments(
			metadataMap,
			payload.PlanningResponse,
			result,
			payload.SequenceNumber,
			payload.IsLast,
			false,
			payload.InConversation,
			true,
		)

		_, err = tx.Response.Create().
			SetResponseID(respID).
			SetPromptID(pr.ID).
			SetSessionID(sessID).
			SetContent(result).
			SetPlanningResponse(payload.PlanningResponse).
			SetSequenceNumber(int(payload.SequenceNumber)).
			SetNillableModelName(modelName).
			SetMetadata(metadataMap).
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
		metadataMap := p.cloneMetadata(existing.Metadata)
		metadataMap = p.mergeMetadata(metadataMap, contracts.FromStruct(payload.Metadata))
		metadataMap = p.appendResponseSegments(
			metadataMap,
			payload.PlanningResponse,
			result,
			payload.SequenceNumber,
			payload.IsLast,
			p.hasResponseSegments(existing.Metadata),
			payload.InConversation,
			!p.hasContentSegment(existing.Metadata),
		)

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
		u.SetMetadata(metadataMap)
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

	// Persist retrieval logs if metadata contains contexts or sub-queries
	metadataMap := contracts.FromStruct(payload.Metadata)
	if metadataMap != nil {
		// Check if we already persisted logs for this prompt to avoid duplicates from seq 0 and aggregator final chunk
		exists, _ := p.client.RetrievalLog.Query().
			Where(retrievallog.MessageIDEQ(promptUUID)).
			Exist(msgCtx)

		if !exists {
			logCount := 0
			// 1. Log Sub-queries
			if subQueries, ok := metadataMap["sub_queries"].([]interface{}); ok && len(subQueries) > 0 {
				for _, q := range subQueries {
					if qStr, ok := q.(string); ok && qStr != "" {
						_, _ = p.client.RetrievalLog.Create().
							SetMessageID(promptUUID).
							SetSessionID(sessID).
							SetType("QUERY").
							SetQuery(qStr).
							Save(msgCtx)
						logCount++
					}
				}
			}

			// 2. Log Retrieved Contexts
			if contexts, ok := metadataMap["contexts"].([]interface{}); ok && len(contexts) > 0 {
				for _, c := range contexts {
					if ctxStr, ok := c.(string); ok && ctxStr != "" {
						_, _ = p.client.RetrievalLog.Create().
							SetMessageID(promptUUID).
							SetSessionID(sessID).
							SetType("RETRIEVAL").
							SetDetail(ctxStr).
							Save(msgCtx)
						logCount++
					}
				}
			}
			if logCount > 0 {
				logging.Printf("Stored %d retrieval logs (queries/contexts) for session %d", logCount, sessID)
			}
		}
	}

	return dlq.Success, nil
}

func (p *PulsarProcessor) HandleCompletion(ctx context.Context, msg pulsar.Message) (dlq.ProcessResult, error) {
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(msg.Properties()))
	tracer := otel.Tracer("db-adapter")
	_, span := tracer.Start(msgCtx, "HandleCompletion")
	defer span.End()

	logging.Printf("Received completion event for processing")

	var payload contracts.ResponseCompletion
	if err := protojson.Unmarshal(msg.Payload(), &payload); err != nil {
		return dlq.PermanentFailure, fmt.Errorf("unmarshal completion payload: %w", err)
	}

	if payload.Metrics == nil {
		return dlq.Success, nil
	}

	m := payload.Metrics
	sessID := payload.SessionId
	respID, err := uuid.Parse(payload.Id)
	if err != nil {
		return dlq.PermanentFailure, fmt.Errorf("invalid response ID %q in completion: %w", payload.Id, err)
	}

	var dbResponseID *int64
	res, err := p.client.Response.Query().
		Where(response.ResponseID(respID)).
		Order(ent.Desc(response.FieldID)).
		First(ctx)
	if err == nil {
		dbResponseID = &res.ID
	}

	modelID, err := p.client.ModelDefinition.Create().
		SetModelName(payload.Model).
		SetFamily(m.ModelFamily).
		OnConflict(
			sql.ConflictColumns(modeldefinition.FieldModelName),
		).
		UpdateNewValues().
		ID(ctx)
	if err != nil {
		logging.Printf("Failed to upsert model definition: %v", err)
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
		logging.Printf("Failed to upsert inference node: %v", err)
	}

	_, err = p.client.ModelExecutionMetric.Create().
		SetNillableResponseID(dbResponseID).
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
		logging.Printf("Failed to insert execution metrics: %v", err)
		return dlq.TransientFailure, err
	}

	logging.Printf("Stored execution metrics for response %s", payload.Id)
	return dlq.Success, nil
}
