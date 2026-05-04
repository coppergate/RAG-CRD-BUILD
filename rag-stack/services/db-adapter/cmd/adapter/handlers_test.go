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
	"app-builds/common/ent"
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
	"strconv"
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

	sessionID := time.Now().UnixNano() % 100000
	sessionIDStr := strconv.FormatInt(sessionID, 10)

	// Create session first to satisfy FK
	_, err := client.Session.Create().SetID(sessionID).SetName("test-session-" + sessionIDStr).Save(context.Background())
	assert.NoError(t, err)

	responseID := uuid.New()

	payload := contracts.ResponseCompletion{
		Id:        responseID.String(),
		SessionId: sessionID,
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
	assert.Equal(t, int64(1000000), metrics[0].TotalDurationUsec)
}

func TestHandleResponseGhostPrompt(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	promptID := uuid.New()
	sessionID := time.Now().UnixNano() % 100000

	payload := struct {
		contracts.StreamChunk
		Result string `json:"result"`
	}{
		StreamChunk: contracts.StreamChunk{
			Id:             promptID.String(),
			SessionId:      sessionID,
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

	sessionID := time.Now().UnixNano() % 100000
	sessionIDStr := strconv.FormatInt(sessionID, 10)

	// Create session first to satisfy FK
	_, err := client.Session.Create().SetID(sessionID).SetName("test-session-" + sessionIDStr).Save(context.Background())
	assert.NoError(t, err)

	// Insert some dummy metrics
	_, err = client.ModelExecutionMetric.Create().
		SetSessionID(sessionID).
		SetTotalTokens(100).
		SetTotalDurationUsec(500000).
		SetTokensPerSecond(20.0).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/sessions/"+sessionIDStr+"/health", nil)
	w := httptest.NewRecorder()

	svc := service.NewMetricsService(client)
	svc.GetHealth(w, req, sessionIDStr)

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

	sessionID := time.Now().UnixNano() % 100000
	sessionIDStr := strconv.FormatInt(sessionID, 10)

	// Create session first to satisfy FK
	_, err := client.Session.Create().SetID(sessionID).SetName("test-session-" + sessionIDStr).Save(context.Background())
	assert.NoError(t, err)

	// Insert retrieval log
	_, err = client.RetrievalLog.Create().
		SetSessionID(sessionID).
		SetQuery("test query").
		Save(context.Background())
	assert.NoError(t, err)

	// Insert memory event
	memID := time.Now().UnixNano() % 100000
	_, err = client.MemoryItem.Create().
		SetID(memID).
		SetMemoryType("short_term_memory").
		SetSummary("test summary").
		SetContent("test memory").
		Save(context.Background())
	assert.NoError(t, err)

	_, err = client.MemoryEvent.Create().
		SetSessionID(sessionID).
		SetMemoryItemID(memID).
		SetEventType("test_event").
		SetEventData(map[string]interface{}{"foo": "bar"}).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/audit/sessions/"+sessionIDStr, nil)
	w := httptest.NewRecorder()

	svc := service.NewMetricsService(client)
	svc.GetAudit(w, req, sessionIDStr)

	assert.Equal(t, http.StatusOK, w.Code)

	var logs []map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &logs)
	assert.NoError(t, err)
	assert.Len(t, logs, 2)
}

func TestHandleGetSessionMessages(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	sessionID := time.Now().UnixNano() % 100000
	sessionIDStr := strconv.FormatInt(sessionID, 10)
	_, err := client.Session.Create().SetID(sessionID).SetName("test-session-" + sessionIDStr).Save(context.Background())
	assert.NoError(t, err)

	// Create a prompt
	p1, err := client.Prompt.Create().
		SetPromptID(uuid.New()).
		SetSessionID(sessionID).
		SetContent("hello").
		Save(context.Background())
	assert.NoError(t, err)

	// Create a response
	model := "test-model"
	_, err = client.Response.Create().
		SetSessionID(sessionID).
		SetPromptID(p1.ID).
		SetResponseID(uuid.New()).
		SetContent("hi").
		SetModelName(model).
		SetSequenceNumber(1).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/sessions/"+sessionIDStr+"/messages", nil)
	w := httptest.NewRecorder()

	svc := service.NewSessionService(client)
	svc.GetMessages(w, req, sessionIDStr)

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

	tagID := time.Now().UnixNano() % 100000
	t1, err := client.Tag.Create().SetID(tagID).SetName("test-tag").Save(context.Background())
	assert.NoError(t, err)

	ingestionID := time.Now().UnixNano() % 100000 + 100000
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

	req := httptest.NewRequest("GET", "/storage/files?tag_id="+strconv.FormatInt(tagID, 10), nil)
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

func TestHandleGetFilesEmptyMetadata(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent_empty?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	// Create embedding with NO path in metadata
	_, err := client.CodeEmbedding.Create().
		SetMetadata(map[string]interface{}{"foo": "bar"}).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/storage/files", nil)
	w := httptest.NewRecorder()

	svc := service.NewStorageService(client)
	svc.GetFiles(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var files []map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &files)
	assert.NoError(t, err)
	assert.Len(t, files, 0) // Should skip files without path
}

func TestHandleGetFilesBySession(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent_session?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	sessionID := time.Now().UnixNano() % 100000
	sessionIDStr := strconv.FormatInt(sessionID, 10)
	s1, err := client.Session.Create().SetID(sessionID).SetName("test-session-" + sessionIDStr).Save(context.Background())
	assert.NoError(t, err)

	tagID := time.Now().UnixNano() % 100000 + 100000
	t1, err := client.Tag.Create().SetID(tagID).SetName("test-tag-"+strconv.FormatInt(tagID, 10)).AddSessions(s1).Save(context.Background())
	assert.NoError(t, err)

	_, err = client.CodeEmbedding.Create().
		SetMetadata(map[string]interface{}{"path": "test/path/session_file.go"}).
		AddTags(t1).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/storage/files?session_id="+sessionIDStr, nil)
	w := httptest.NewRecorder()

	svc := service.NewStorageService(client)
	svc.GetFiles(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var files []map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &files)
	assert.NoError(t, err)
	assert.Len(t, files, 1)
	assert.Equal(t, "test/path/session_file.go", files[0]["path"])
}

func TestHandleGetFilesNoFilters(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent_no_filters?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	_, err := client.CodeEmbedding.Create().
		SetMetadata(map[string]interface{}{"path": "file1.go"}).
		Save(context.Background())
	assert.NoError(t, err)

	_, err = client.CodeEmbedding.Create().
		SetMetadata(map[string]interface{}{"path": "file2.go"}).
		Save(context.Background())
	assert.NoError(t, err)

	req := httptest.NewRequest("GET", "/storage/files", nil)
	w := httptest.NewRecorder()

	svc := service.NewStorageService(client)
	svc.GetFiles(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var files []map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &files)
	assert.NoError(t, err)
	assert.Len(t, files, 2)
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

	sourceTagID := int64(999)
	targetTagID := int64(1000)

	sTag, _ := client.Tag.Create().SetID(sourceTagID).SetName("source").Save(ctx)
	_, _ = client.Tag.Create().SetID(targetTagID).SetName("target").Save(ctx)

	// Create a session with source tag
	sess, _ := client.Session.Create().SetID(2000).SetName("sess").AddTags(sTag).Save(ctx)

	// Create an embedding with source tag
	client.CodeEmbedding.Create().
		SetMetadata(map[string]interface{}{"path": "file1.go"}).
		AddTags(sTag).
		Save(ctx)

	payload := struct {
		SourceIDs []int64 `json:"source_ids"`
		TargetID  int64   `json:"target_id"`
	}{
		SourceIDs: []int64{999},
		TargetID:  1000,
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

func TestListSessions(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent_list?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	ctx := context.Background()
	client.Session.Create().SetID(101).SetName("S1").SetLastActiveAt(time.Now()).Save(ctx)
	client.Session.Create().SetID(102).SetName("S2").SetLastActiveAt(time.Now().Add(time.Hour)).Save(ctx)

	req := httptest.NewRequest("GET", "/sessions", nil)
	w := httptest.NewRecorder()

	svc := service.NewSessionService(client)
	svc.ListSessions(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	var sessions []ent.Session
	err := json.Unmarshal(w.Body.Bytes(), &sessions)
	assert.NoError(t, err)
	assert.Len(t, sessions, 2)
	assert.Equal(t, int64(102), sessions[0].ID) // Order Desc by last_active_at
}

func TestUpdateSessionTags(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent_tags?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	ctx := context.Background()
	sessID := int64(301)
	client.Session.Create().SetID(sessID).SetName("S3").Save(ctx)

	_, _ = client.Tag.Create().SetID(501).SetName("T1").Save(ctx)
	_, _ = client.Tag.Create().SetID(502).SetName("T2").Save(ctx)

	payload := struct {
		TagIDs []string `json:"tag_ids"`
	}{
		TagIDs: []string{"501", "502"},
	}
	body, _ := json.Marshal(payload)
	req := httptest.NewRequest("POST", "/sessions/tags?session_id=301", bytes.NewBuffer(body))
	w := httptest.NewRecorder()

	svc := service.NewSessionService(client)
	svc.UpdateSessionTags(w, req)

	assert.Equal(t, http.StatusNoContent, w.Code)

	sess, _ := client.Session.Query().Where(session.ID(sessID)).WithTags().Only(ctx)
	assert.Len(t, sess.Edges.Tags, 2)
}

func TestDeleteSession(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent_delete?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	ctx := context.Background()
	sessID := int64(401)
	client.Session.Create().SetID(sessID).SetName("S4").Save(ctx)

	req := httptest.NewRequest("DELETE", "/sessions/401", nil)
	w := httptest.NewRecorder()

	svc := service.NewSessionService(client)
	svc.DeleteSession(w, req, "401")

	assert.Equal(t, http.StatusNoContent, w.Code)

	exists, _ := client.Session.Query().Where(session.ID(sessID)).Exist(ctx)
	assert.False(t, exists)
}
