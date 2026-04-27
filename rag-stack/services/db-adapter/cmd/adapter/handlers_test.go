package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/common/ent/enttest"
	"app-builds/common/ent/session"
	"app-builds/common/ent/tag"
	"app-builds/db-adapter/internal/service"
	"entgo.io/ent/dialect/sql"
	"entgo.io/ent/dialect/sql/sqljson"
	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/google/uuid"
	_ "github.com/mattn/go-sqlite3"
	"github.com/stretchr/testify/assert"
)

// We need a mock Pulsar message
type mockMessage struct {
	payload []byte
}

func (m *mockMessage) Topic() string                                   { return "" }
func (m *mockMessage) ProducerName() string                            { return "" }
func (m *mockMessage) Properties() map[string]string                   { return nil }
func (m *mockMessage) Payload() []byte                                 { return m.payload }
func (m *mockMessage) ID() pulsar.MessageID                            { return nil }
func (m *mockMessage) PublishTime() time.Time                          { return time.Now() }
func (m *mockMessage) EventTime() time.Time                            { return time.Now() }
func (m *mockMessage) Key() string                                     { return "" }
func (m *mockMessage) OrderingKey() string                             { return "" }
func (m *mockMessage) RedeliveryCount() uint32                         { return 0 }
func (m *mockMessage) IsReplicated() bool                              { return false }
func (m *mockMessage) GetReplicatedFrom() string                       { return "" }
func (m *mockMessage) GetSchemaValue(v interface{}) error              { return nil }
func (m *mockMessage) SchemaVersion() []byte                           { return nil }
func (m *mockMessage) GetEncryptionContext() *pulsar.EncryptionContext { return nil }
func (m *mockMessage) Index() *uint64                                  { return nil }
func (m *mockMessage) BrokerPublishTime() *time.Time                   { return nil }

func TestHandleCompletion(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	sessionID := uuid.New()

	// Create session first to satisfy FK
	_, err := client.Session.Create().SetID(sessionID).SetName("test-session").Save(context.Background())
	assert.NoError(t, err)

	responseID := uuid.New()

	payload := contracts.ResponseCompletion{
		Id:        responseID.String(),
		SessionId: sessionID.String(),
		Model:     "test-model",
		Metrics: &contracts.ExecutionMetrics{
			PromptTokens:      10,
			CompletionTokens:  20,
			TotalDurationUsec: 1000000,
			Hostname:          "test-host",
			ModelFamily:       "llama",
		},
	}
	data, _ := json.Marshal(payload)
	msg := &mockMessage{payload: data}

	processor := service.NewPulsarProcessor(client, nil, nil, nil)
	res, err := processor.HandleCompletion(context.Background(), msg)
	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, res)

	// Verify data in DB
	metrics, err := client.ModelExecutionMetric.Query().All(context.Background())
	assert.NoError(t, err)
	assert.Len(t, metrics, 1)
	assert.Equal(t, 30, metrics[0].TotalTokens)
	assert.Equal(t, int64(1000000), metrics[0].TotalDurationUsec)
}

func TestHandleResponseGhostPrompt(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	promptID := uuid.New()
	sessionID := uuid.New()

	payload := struct {
		contracts.StreamChunk
		Result string `json:"result"`
	}{
		StreamChunk: contracts.StreamChunk{
			Id:             promptID.String(),
			SessionId:      sessionID.String(),
			SequenceNumber: 0,
			Model:          "test-model",
		},
		Result: "Test result",
	}
	data, _ := json.Marshal(payload)
	msg := &mockMessage{payload: data}

	processor := service.NewPulsarProcessor(client, nil, nil, nil)

	// Ensure prompt does NOT exist
	res, err := processor.HandleResponse(context.Background(), msg)
	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, res)

	// Verify ghost prompt was created
	pr, err := client.Prompt.Query().First(context.Background())
	assert.NoError(t, err)
	assert.Equal(t, promptID, pr.PromptID)
	assert.Equal(t, "[PENDING]", pr.Content)

	// Verify response was created
	resp, err := client.Response.Query().First(context.Background())
	assert.NoError(t, err)
	assert.Equal(t, pr.ID, resp.PromptID)
	assert.Equal(t, "Test result", resp.Content)
}

func TestHandleGetSessionHealth(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	sessionID := uuid.New()

	// Create session first to satisfy FK
	_, err := client.Session.Create().SetID(sessionID).SetName("test-session").Save(context.Background())
	assert.NoError(t, err)

	// Insert some dummy metrics
	_, err = client.ModelExecutionMetric.Create().
		SetSessionID(sessionID).
		SetTotalTokens(100).
		SetTotalDurationUsec(500000).
		SetTokensPerSecond(20.0).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/sessions/"+sessionID.String()+"/health", nil)
	w := httptest.NewRecorder()

	svc := service.NewMetricsService(client)
	svc.GetHealth(w, req, sessionID.String())

	assert.Equal(t, http.StatusOK, w.Code)

	var health map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &health)
	assert.NoError(t, err)
	assert.Equal(t, 1.0, health["total_requests"])
	assert.Equal(t, 500.0, health["avg_latency_ms"])
	assert.Equal(t, "HEALTHY", health["status"])
}

func TestHandleGetSessionAudit(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	sessionID := uuid.New()

	// Create session first to satisfy FK
	_, err := client.Session.Create().SetID(sessionID).SetName("test-session").Save(context.Background())
	assert.NoError(t, err)

	// Insert retrieval log
	_, err = client.RetrievalLog.Create().
		SetSessionID(sessionID).
		SetQuery("test query").
		Save(context.Background())
	assert.NoError(t, err)

	// Insert memory event
	_, err = client.MemoryEvent.Create().
		SetSessionID(sessionID).
		SetMemoryItemID(uuid.New()).
		SetEventType("test_event").
		SetEventData(map[string]interface{}{"foo": "bar"}).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/audit/sessions/"+sessionID.String(), nil)
	w := httptest.NewRecorder()

	svc := service.NewMetricsService(client)
	svc.GetAudit(w, req, sessionID.String())

	assert.Equal(t, http.StatusOK, w.Code)

	var logs []map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &logs)
	assert.NoError(t, err)
	assert.Len(t, logs, 2)
}

func TestHandleGetSessionMessages(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	sessionID := uuid.New()
	_, err := client.Session.Create().SetID(sessionID).SetName("test-session").Save(context.Background())
	assert.NoError(t, err)

	// Create a prompt
	_, err = client.Prompt.Create().
		SetSessionID(sessionID).
		SetContent("hello").
		Save(context.Background())
	assert.NoError(t, err)

	// Create a response
	model := "test-model"
	_, err = client.Response.Create().
		SetSessionID(sessionID).
		SetContent("hi").
		SetModelName(model).
		SetSequenceNumber(1).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/sessions/"+sessionID.String()+"/messages", nil)
	w := httptest.NewRecorder()

	svc := service.NewSessionService(client)
	svc.GetMessages(w, req, sessionID.String())

	assert.Equal(t, http.StatusOK, w.Code)

	var messages []map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &messages)
	assert.NoError(t, err)
	assert.Len(t, messages, 2)
	assert.Equal(t, "user", messages[0]["role"])
	assert.Equal(t, "assistant", messages[1]["role"])
}

func TestHandleGetFiles(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	tagID := uuid.New()
	t1, err := client.Tag.Create().SetID(tagID).SetName("test-tag").Save(context.Background())
	assert.NoError(t, err)

	ingestionID := uuid.New()
	ci, err := client.CodeIngestion.Create().
		SetID(ingestionID).
		SetS3BucketID("test-bucket").
		AddTags(t1).
		Save(context.Background())
	assert.NoError(t, err)

	_, err = client.CodeEmbedding.Create().
		SetIngestion(ci).
		SetMetadata(map[string]interface{}{"path": "test/path/file.go"}).
		AddTags(t1).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/storage/files?tag_id="+tagID.String(), nil)
	w := httptest.NewRecorder()

	svc := service.NewStorageService(client)
	svc.GetFiles(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var files []map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &files)
	assert.NoError(t, err)
	assert.Len(t, files, 1)
	assert.Equal(t, "test/path/file.go", files[0]["path"])
	assert.Contains(t, files[0]["tags"], "test-tag")
}

type mockProducer struct {
	pulsar.Producer
	sentMessages []*pulsar.ProducerMessage
}

func (m *mockProducer) Send(ctx context.Context, msg *pulsar.ProducerMessage) (pulsar.MessageID, error) {
	m.sentMessages = append(m.sentMessages, msg)
	return nil, nil
}

func (m *mockProducer) Close() {}

func TestHandleMaintenanceTagMerge(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	ctx := context.Background()

	sourceTagID := uuid.New()
	targetTagID := uuid.New()

	sTag, _ := client.Tag.Create().SetID(sourceTagID).SetName("source").Save(ctx)
	_, _ = client.Tag.Create().SetID(targetTagID).SetName("target").Save(ctx)

	// Create a session with source tag
	sess, _ := client.Session.Create().SetID(uuid.New()).SetName("sess").AddTags(sTag).Save(ctx)

	// Create an embedding with source tag
	client.CodeEmbedding.Create().
		SetMetadata(map[string]interface{}{"path": "file1.go"}).
		AddTags(sTag).
		Save(ctx)

	payload := struct {
		SourceIDs []string `json:"source_ids"`
		TargetID  string   `json:"target_id"`
	}{
		SourceIDs: []string{sourceTagID.String()},
		TargetID:  targetTagID.String(),
	}
	body, _ := json.Marshal(payload)
	req := httptest.NewRequest("POST", "/maintenance/tags/merge", bytes.NewBuffer(body))
	w := httptest.NewRecorder()

	prod := &mockProducer{}

	svc := service.NewMaintenanceService(client, prod, "http://localhost:invalid")
	svc.MergeTags(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	// 1. Source tag should be deleted
	exists, _ := client.Tag.Query().Where(tag.ID(sourceTagID)).Exist(ctx)
	assert.False(t, exists)

	// 2. Session should now have target tag
	hasTarget, _ := client.Session.Query().
		Where(session.ID(sess.ID)).
		Where(session.HasTagsWith(tag.ID(targetTagID))).
		Exist(ctx)
	assert.True(t, hasTarget)

	// 3. Embedding for file1.go should be deleted from DB (it will be re-ingested)
	embeddingExists, err := client.CodeEmbedding.Query().
		Where(func(s *sql.Selector) {
			s.Where(sqljson.ValueEQ("metadata", "file1.go", sqljson.Path("path")))
		}).
		Exist(ctx)
	assert.NoError(t, err)
	assert.False(t, embeddingExists)
}
