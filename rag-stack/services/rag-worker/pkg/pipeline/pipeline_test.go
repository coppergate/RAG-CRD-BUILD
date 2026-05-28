package pipeline

import (
	"context"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"testing"

	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/rag-worker/internal/config"
	"app-builds/rag-worker/internal/models"
	"app-builds/rag-worker/internal/ollama"
	"app-builds/rag-worker/pkg/messaging"
)

// MockSearcher is a mock implementation of QdrantSearcher interface
type MockSearcher struct {
	mock.Mock
}

type MockTagSource struct {
	mock.Mock
}

func (m *MockSearcher) Search(ctx context.Context, embeddingModel string, vector []float32, tags []int64, sessionID int64, includeGlobal bool, limit int) ([]interface{}, error) {
	args := m.Called(ctx, embeddingModel, vector, tags, sessionID, includeGlobal, limit)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).([]interface{}), args.Error(1)
}

func (m *MockSearcher) RetrieveByPaths(ctx context.Context, embeddingModel string, paths []string) ([]interface{}, error) {
	args := m.Called(ctx, embeddingModel, paths)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).([]interface{}), args.Error(1)
}

func (m *MockTagSource) TagsForSession(ctx context.Context, sessionID int64) ([]int64, error) {
	args := m.Called(ctx, sessionID)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).([]int64), args.Error(1)
}

// MockMemoryClient is a mock implementation of MemoryClient interface
type MockMemoryClient struct {
	mock.Mock
}

func (m *MockMemoryClient) Retrieve(ctx context.Context, sessionID int64, tags []int64, actionType, query string) (*contracts.MemoryPack, error) {
	args := m.Called(ctx, sessionID, tags, actionType, query)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*contracts.MemoryPack), args.Error(1)
}

func (m *MockMemoryClient) AuditRuleApplication(ctx context.Context, promptID string, ruleID int64, actionType string, metadata map[string]interface{}) error {
	args := m.Called(ctx, promptID, ruleID, actionType, metadata)
	return args.Error(0)
}

func (m *MockMemoryClient) GetActionIdentifiers(ctx context.Context) (map[string][]string, error) {
	args := m.Called(ctx)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(map[string][]string), args.Error(1)
}

func (m *MockMemoryClient) RecordLearning(ctx context.Context, feedback string, actionType, category string, priority int) error {
	args := m.Called(ctx, feedback, actionType, category, priority)
	return args.Error(0)
}

func (m *MockMemoryClient) ResetSessionBehavior(ctx context.Context, sessionID int64) error {
	args := m.Called(ctx, sessionID)
	return args.Error(0)
}

// MockRegistry is a mock implementation of ModelRegistry interface
type MockRegistry struct {
	mock.Mock
}

func (m *MockRegistry) GetPlanner(modelID string) (models.Planner, error) {
	args := m.Called(modelID)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(models.Planner), args.Error(1)
}

func (m *MockRegistry) GetExecutor(modelID string) (models.Executor, error) {
	args := m.Called(modelID)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(models.Executor), args.Error(1)
}

// MockPlanner is a mock implementation of models.Planner interface
type MockPlanner struct {
	mock.Mock
}

func (m *MockPlanner) Plan(ctx context.Context, prompt string, contexts []interface{}, history []interface{}) (*contracts.PlannerTaskPlan, interface{}, error) {
	args := m.Called(ctx, prompt, contexts, history)
	if args.Get(0) == nil {
		return nil, args.Get(1), args.Error(2)
	}
	return args.Get(0).(*contracts.PlannerTaskPlan), args.Get(1), args.Error(2)
}

func (m *MockPlanner) GetEmbeddings(ctx context.Context, text string) ([]float32, error) {
	args := m.Called(ctx, text)
	return args.Get(0).([]float32), args.Error(1)
}

// MockExecutor is a mock implementation of models.Executor interface
type MockExecutor struct {
	mock.Mock
}

func (m *MockExecutor) Execute(ctx context.Context, prompt string, contexts []interface{}, history []interface{}) (string, interface{}, error) {
	args := m.Called(ctx, prompt, contexts, history)
	return args.String(0), args.Get(1), args.Error(2)
}

func (m *MockExecutor) ExecuteStream(ctx context.Context, prompt string, contexts []interface{}, history []interface{}) (<-chan string, <-chan interface{}, <-chan error) {
	args := m.Called(ctx, prompt, contexts, history)
	return args.Get(0).(<-chan string), args.Get(1).(<-chan interface{}), args.Get(2).(<-chan error)
}

func (m *MockExecutor) IsInsufficientContext(result string) bool {
	args := m.Called(result)
	return args.Bool(0)
}

// MockProducer is a mock implementation of pulsar.Producer interface
type MockProducer struct {
	mock.Mock
	pulsar.Producer
}

func (m *MockProducer) Send(ctx context.Context, msg *pulsar.ProducerMessage) (pulsar.MessageID, error) {
	args := m.Called(ctx, msg)
	return nil, args.Error(1)
}

func (m *MockProducer) Close() {
	m.Called()
}

func TestChunkResults(t *testing.T) {
	mockSearcher := new(MockSearcher)
	h := &Handler{
		searcher: mockSearcher,
		cfg: &config.Config{
			ChunkVectorLimit: 50,
		},
	}

	rawResults := []interface{}{
		map[string]interface{}{
			"_qdrant_id": "1",
			"path":       "file1.txt",
			"chunk":      float64(0),
			"content":    "chunk 0",
		},
		map[string]interface{}{
			"_qdrant_id": "2",
			"path":       "file1.txt",
			"chunk":      float64(1),
			"content":    "chunk 1",
		},
		map[string]interface{}{
			"_qdrant_id": "1", // Duplicate ID
			"path":       "file1.txt",
			"chunk":      float64(0),
			"content":    "chunk 0 duplicate",
		},
		map[string]interface{}{
			"content": "non-file content",
		},
	}

	// Mock RetrieveByPaths to return all chunks for file1.txt
	mockSearcher.On("RetrieveByPaths", mock.Anything, "", []string{"file1.txt"}).Return([]interface{}{
		map[string]interface{}{
			"_qdrant_id": "1",
			"path":       "file1.txt",
			"chunk":      float64(0),
			"content":    "chunk 0",
		},
		map[string]interface{}{
			"_qdrant_id": "2",
			"path":       "file1.txt",
			"chunk":      float64(1),
			"content":    "chunk 1",
		},
		map[string]interface{}{
			"_qdrant_id": "3",
			"path":       "file1.txt",
			"chunk":      float64(2),
			"content":    "chunk 2",
		},
	}, nil)

	chunks := h.chunkResults(context.Background(), rawResults)

	// One chunk containing both the reassembled file and non-file content
	assert.Len(t, chunks, 1)
	chunk := chunks[0]
	assert.Len(t, chunk, 2)

	// Sort to ensure stable order for comparison
	sort.Strings(chunk)

	assert.Contains(t, chunk[0], "--- File: file1.txt ---")
	assert.Contains(t, chunk[0], "chunk 0")
	assert.Contains(t, chunk[0], "chunk 1")
	assert.Contains(t, chunk[0], "chunk 2")
	assert.Equal(t, "non-file content", chunk[1])

	mockSearcher.AssertExpectations(t)
}

func TestChunkResults_Empty(t *testing.T) {
	h := &Handler{
		cfg: &config.Config{},
	}
	chunks := h.chunkResults(context.Background(), nil)
	assert.Empty(t, chunks)
}

// MockMessage is a simple mock for pulsar.Message
type MockMessage struct {
	pulsar.Message
	payload []byte
}

func (m *MockMessage) Payload() []byte {
	return m.payload
}

func TestHandleSearch(t *testing.T) {
	mockSearcher := new(MockSearcher)
	mockRegistry := new(MockRegistry)
	mockPlanner := new(MockPlanner)
	mockMem := new(MockMemoryClient)
	mockStatusProd := new(MockProducer)
	mockExecProd := new(MockProducer)

	cfg := &config.Config{
		PlannerModel:   "default-planner",
		EmbeddingModel: "embed-model",
	}

	h := &Handler{
		cfg:          cfg,
		registry:     mockRegistry,
		searcher:     mockSearcher,
		memoryClient: mockMem,
		msg: &messaging.Client{
			// We only need the producers used in handleSearch
			Producers: messaging.Producers{
				Status: mockStatusProd,
				Exec:   mockExecProd,
			},
		},
	}

	req := &contracts.InternalRequest{
		Id:             "test-id",
		SessionId:      1,
		Prompt:         "test prompt",
		EmbeddingModel: "embed-model",
	}

	mockRegistry.On("GetPlanner", "default-planner").Return(mockPlanner, nil)
	mockRegistry.On("GetPlanner", "embed-model").Return(mockPlanner, nil)
	mockPlanner.On("GetEmbeddings", mock.Anything, "test prompt").Return([]float32{0.1, 0.2}, nil)
	mockPlanner.On("Plan", mock.Anything, "test prompt", mock.Anything, mock.Anything).Return(&contracts.PlannerTaskPlan{
		Objective:     "test prompt",
		ActionType:    "FILE_SEARCH",
		SearchQueries: []string{"found context"},
		ContextBudget: 1,
	}, nil, nil)

	// Mock status updates
	mockStatusProd.On("Send", mock.Anything, mock.MatchedBy(func(m *pulsar.ProducerMessage) bool {
		return strings.Contains(string(m.Payload), "RETRIEVING_CONTEXT")
	})).Return(nil, nil)

	// Mock search
	mockSearcher.On("Search", mock.Anything, "embed-model", []float32{0.1, 0.2}, []int64(nil), int64(1), false, mock.Anything).Return([]interface{}{
		map[string]interface{}{"content": "found context"},
	}, nil)

	// Mock send to exec topic
	mockExecProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	// Call handleSearch
	result, err := h.handleSearch(context.Background(), req)

	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, result)

	mockSearcher.AssertExpectations(t)
	mockRegistry.AssertExpectations(t)
	mockPlanner.AssertExpectations(t)
	mockMem.AssertExpectations(t)
	mockExecProd.AssertExpectations(t)
}

func TestResolveSearchTags_UsesDatabaseSource(t *testing.T) {
	mockTags := new(MockTagSource)
	h := &Handler{
		tagSource: mockTags,
	}

	req := &contracts.InternalRequest{
		SessionId: 123,
		Tags:      []int64{1, 2},
	}

	mockTags.On("TagsForSession", mock.Anything, int64(123)).Return([]int64{9, 10}, nil)

	tags, err := h.resolveSearchTags(context.Background(), req)

	assert.NoError(t, err)
	assert.Equal(t, []int64{9, 10}, tags)
	mockTags.AssertExpectations(t)
}

func TestHandlePlan(t *testing.T) {
	mockRegistry := new(MockRegistry)
	mockPlanner := new(MockPlanner)
	mockMem := new(MockMemoryClient)
	mockStatusProd := new(MockProducer)
	mockPlanProd := new(MockProducer)
	mockSearchProd := new(MockProducer)

	cfg := &config.Config{
		PlannerModel: "default-planner",
	}

	h := &Handler{
		cfg:          cfg,
		registry:     mockRegistry,
		memoryClient: mockMem,
		msg: &messaging.Client{
			Producers: messaging.Producers{
				Status: mockStatusProd,
				Plan:   mockPlanProd,
				Search: mockSearchProd,
			},
		},
	}

	req := &contracts.InternalRequest{
		Id:        "test-id",
		SessionId: 1,
		Prompt:    "test prompt",
	}

	mockRegistry.On("GetPlanner", "default-planner").Return(mockPlanner, nil)
	mockMem.On("GetActionIdentifiers", mock.Anything).Return(map[string][]string{"FILE_EDIT": {"edit"}}, nil)
	mockMem.On("Retrieve", mock.Anything, int64(1), []int64(nil), "UNKNOWN", "test prompt").Return(&contracts.MemoryPack{
		Items: []*contracts.MemoryWriteItem{
			{Content: "history item", MemoryType: "episodic", Metadata: contracts.ToStruct(map[string]interface{}{"role": "user"})},
		},
	}, nil)
	mockPlanner.On("Plan", mock.Anything, "test prompt", mock.Anything, mock.Anything).Return(&contracts.PlannerTaskPlan{
		Objective:     "test prompt",
		ActionType:    "FILE_EDIT",
		SearchQueries: []string{"subquery 1"},
		ContextBudget: 2,
		Trace: contracts.PlannerTrace{
			RawResponse: `{"objective":"test prompt","action_type":"FILE_EDIT","search_queries":["subquery 1"]}`,
			ParserMode:  "json_object",
			Prompt:      "test prompt",
		},
	}, nil, nil)

	// Mock status and planning response
	mockStatusProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockSearchProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockResultsProd := new(MockProducer)
	h.msg.Producers.Results = mockResultsProd
	mockResultsProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	h.msg.SetSessionProducer(h.msg.SessionTopic("test-id"), mockResultsProd)

	// Call handlePlan
	result, err := h.handlePlan(context.Background(), req)

	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, result)

	mockMem.AssertExpectations(t)
	mockPlanner.AssertExpectations(t)
	mockSearchProd.AssertExpectations(t)
}

func TestHandlePlan_LearningLoop(t *testing.T) {
	mockRegistry := new(MockRegistry)
	mockPlanner := new(MockPlanner)
	mockMem := new(MockMemoryClient)
	mockStatusProd := new(MockProducer)
	mockSearchProd := new(MockProducer)
	mockResultsProd := new(MockProducer)

	h := &Handler{
		cfg:          &config.Config{PlannerModel: "p-model"},
		registry:     mockRegistry,
		memoryClient: mockMem,
		msg: &messaging.Client{
			Producers: messaging.Producers{
				Status:  mockStatusProd,
				Search:  mockSearchProd,
				Results: mockResultsProd,
			},
		},
	}
	h.msg.SetSessionProducer(h.msg.SessionTopic("test-id"), mockResultsProd)

	req := &contracts.InternalRequest{
		Id:        "test-id",
		SessionId: 1,
		Prompt:    "REMEMBER WHEN FILE_EDIT # Optimization - minimize horizontal scrolling",
	}

	mockRegistry.On("GetPlanner", "p-model").Return(mockPlanner, nil)
	mockMem.On("GetActionIdentifiers", mock.Anything).Return(map[string][]string{}, nil)
	mockMem.On("Retrieve", mock.Anything, int64(1), []int64(nil), "UNKNOWN", req.Prompt).Return(&contracts.MemoryPack{}, nil)
	mockPlanner.On("Plan", mock.Anything, req.Prompt, mock.Anything, mock.Anything).Return(&contracts.PlannerTaskPlan{
		Objective:     req.Prompt,
		ActionType:    "FILE_EDIT",
		SearchQueries: []string{"plan"},
		ContextBudget: 1,
		Trace: contracts.PlannerTrace{
			RawResponse: `{"objective":"REMEMBER WHEN FILE_EDIT # Optimization - minimize horizontal scrolling","action_type":"FILE_EDIT","search_queries":["plan"]}`,
			ParserMode:  "json_object",
			Prompt:      req.Prompt,
		},
	}, nil, nil)
	mockStatusProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockSearchProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockResultsProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	// expectation for learning
	mockMem.On("RecordLearning", mock.Anything, "minimize horizontal scrolling", "FILE_EDIT", "Optimization", 100).Return(nil)

	result, err := h.handlePlan(context.Background(), req)

	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, result)
	mockMem.AssertExpectations(t)
}

func TestHandlePlan_MissingPlannerModel_IsPermanentFailure(t *testing.T) {
	mockRegistry := new(MockRegistry)
	mockPlanner := new(MockPlanner)
	mockMem := new(MockMemoryClient)
	mockStatusProd := new(MockProducer)
	mockSearchProd := new(MockProducer)
	mockResultsProd := new(MockProducer)

	h := &Handler{
		cfg:          &config.Config{PlannerModel: "p-model"},
		registry:     mockRegistry,
		memoryClient: mockMem,
		msg: &messaging.Client{
			Producers: messaging.Producers{
				Status:  mockStatusProd,
				Search:  mockSearchProd,
				Results: mockResultsProd,
			},
		},
	}
	h.msg.SetSessionProducer(h.msg.SessionTopic("test-id"), mockResultsProd)

	req := &contracts.InternalRequest{
		Id:        "test-id",
		SessionId: 1,
		Prompt:    "test prompt",
	}

	mockRegistry.On("GetPlanner", "p-model").Return(mockPlanner, nil)
	mockMem.On("GetActionIdentifiers", mock.Anything).Return(map[string][]string{}, nil)
	mockMem.On("Retrieve", mock.Anything, int64(1), []int64(nil), "UNKNOWN", req.Prompt).Return(&contracts.MemoryPack{}, nil)
	mockPlanner.On("Plan", mock.Anything, req.Prompt, mock.Anything, mock.Anything).Return(
		(*contracts.PlannerTaskPlan)(nil),
		nil,
		&ollama.APIStatusError{Operation: "chat", URL: "http://ollama", StatusCode: http.StatusNotFound, Body: "model not found"},
	)
	mockStatusProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockSearchProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockResultsProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	result, err := h.handlePlan(context.Background(), req)

	assert.Error(t, err)
	assert.Equal(t, dlq.PermanentFailure, result)
	mockMem.AssertExpectations(t)
	mockPlanner.AssertExpectations(t)
}

func TestHandlePlan_ResetBehavior(t *testing.T) {
	mockRegistry := new(MockRegistry)
	mockPlanner := new(MockPlanner)
	mockMem := new(MockMemoryClient)
	mockStatusProd := new(MockProducer)
	mockSearchProd := new(MockProducer)
	mockResultsProd := new(MockProducer)

	h := &Handler{
		cfg:          &config.Config{PlannerModel: "p-model"},
		registry:     mockRegistry,
		memoryClient: mockMem,
		msg: &messaging.Client{
			Producers: messaging.Producers{
				Status:  mockStatusProd,
				Search:  mockSearchProd,
				Results: mockResultsProd,
			},
		},
	}
	h.msg.SetSessionProducer(h.msg.SessionTopic("test-id"), mockResultsProd)

	req := &contracts.InternalRequest{
		Id:        "test-id",
		SessionId: 1,
		Prompt:    "RESET BEHAVIOR",
	}

	mockRegistry.On("GetPlanner", "p-model").Return(mockPlanner, nil)
	mockMem.On("GetActionIdentifiers", mock.Anything).Return(map[string][]string{}, nil)
	mockMem.On("Retrieve", mock.Anything, int64(1), []int64(nil), "UNKNOWN", req.Prompt).Return(&contracts.MemoryPack{}, nil)
	mockPlanner.On("Plan", mock.Anything, req.Prompt, mock.Anything, mock.Anything).Return(&contracts.PlannerTaskPlan{
		Objective:     req.Prompt,
		ActionType:    "UNKNOWN",
		SearchQueries: []string{"plan"},
		ContextBudget: 1,
		Trace: contracts.PlannerTrace{
			RawResponse: `["plan"]`,
			ParserMode:  "legacy_array",
			Prompt:      req.Prompt,
		},
	}, nil, nil)
	mockStatusProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockSearchProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockResultsProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	// expectation for reset
	mockMem.On("ResetSessionBehavior", mock.Anything, int64(1)).Return(nil)

	result, err := h.handlePlan(context.Background(), req)

	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, result)
	mockMem.AssertExpectations(t)
}

func TestHandleExec_Recursion(t *testing.T) {
	mockRegistry := new(MockRegistry)
	mockExecutor := new(MockExecutor)
	mockStatusProd := new(MockProducer)
	mockPlanProd := new(MockProducer)

	cfg := &config.Config{
		ExecutorModel:     "default-executor",
		PlannerModel:      "default-planner",
		MaxRecursionCount: 3,
		MaxTotalChunks:    100,
	}

	h := &Handler{
		cfg:      cfg,
		registry: mockRegistry,
		msg: &messaging.Client{
			Producers: messaging.Producers{
				Status: mockStatusProd,
				Plan:   mockPlanProd,
			},
		},
	}
	h.msg.SetSessionProducer(h.msg.SessionTopic("test-id"), mockStatusProd) // Use any producer as mock

	metadataMap := map[string]interface{}{
		"recursion_budget": float64(1),
	}
	req := &contracts.InternalRequest{
		Id:            "test-id",
		SessionId:     1,
		Prompt:        "test prompt",
		Metadata:      contracts.ToStruct(metadataMap),
		ExecutorModel: "default-executor",
	}

	mockRegistry.On("GetExecutor", "default-executor").Return(mockExecutor, nil)
	mockRegistry.On("GetPlanner", "default-planner").Return(nil, fmt.Errorf("not needed"))

	// Mock non-streaming execution
	mockExecutor.On("Execute", mock.Anything, "test prompt", mock.Anything, mock.Anything).Return("I don't know enough", nil, nil)

	// Grounding check for chunk and then final
	mockExecutor.On("IsInsufficientContext", "I don't know enough").Return(true)

	// Mock status updates
	mockStatusProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	// Mock send back to plan topic (recursion)
	mockPlanProd.On("Send", mock.Anything, mock.MatchedBy(func(m *pulsar.ProducerMessage) bool {
		// Verify budget decreased
		return strings.Contains(string(m.Payload), "\"recursion_budget\":0")
	})).Return(nil, nil)

	// Call handleExec
	result, err := h.handleExec(context.Background(), req)

	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, result)

	mockRegistry.AssertExpectations(t)
	mockExecutor.AssertExpectations(t)
	mockPlanProd.AssertExpectations(t)
}

func TestHandleExec_UsesRawResultsWhenChunkMetadataIsMissing(t *testing.T) {
	mockRegistry := new(MockRegistry)
	mockExecutor := new(MockExecutor)
	mockStatusProd := new(MockProducer)
	mockResultsProd := new(MockProducer)
	mockSessionProd := new(MockProducer)
	mockCompletionProd := new(MockProducer)

	cfg := &config.Config{
		ExecutorModel:     "default-executor",
		PlannerModel:      "default-planner",
		MaxRecursionCount: 3,
		MaxTotalChunks:    100,
	}

	h := &Handler{
		cfg:      cfg,
		registry: mockRegistry,
		msg: &messaging.Client{
			Producers: messaging.Producers{
				Status:     mockStatusProd,
				Results:    mockResultsProd,
				Completion: mockCompletionProd,
			},
		},
	}
	h.msg.SetSessionProducer(h.msg.SessionTopic("test-id"), mockSessionProd)

	req := &contracts.InternalRequest{
		Id:        "test-id",
		SessionId: 1,
		Prompt:    "test prompt",
		Metadata: contracts.ToStruct(map[string]interface{}{
			"raw_results": []interface{}{
				map[string]interface{}{
					"content": "Project Alpha uses the Zeltron-9 protocol.",
				},
			},
			"recursion_budget": float64(1),
		}),
		ExecutorModel: "default-executor",
	}

	mockRegistry.On("GetExecutor", "default-executor").Return(mockExecutor, nil)
	mockRegistry.On("GetPlanner", "default-planner").Return(nil, fmt.Errorf("not needed"))

	mockExecutor.On("Execute", mock.Anything, "test prompt", mock.MatchedBy(func(contexts []interface{}) bool {
		return len(contexts) == 1 && strings.Contains(fmt.Sprintf("%v", contexts[0]), "Zeltron-9")
	}), mock.Anything).Return("Zeltron-9", nil, nil)
	mockExecutor.On("IsInsufficientContext", "Zeltron-9").Return(false)

	mockStatusProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockResultsProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockSessionProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	mockCompletionProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	result, err := h.handleExec(context.Background(), req)

	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, result)

	mockRegistry.AssertExpectations(t)
	mockExecutor.AssertExpectations(t)
	mockStatusProd.AssertExpectations(t)
	mockResultsProd.AssertExpectations(t)
	mockSessionProd.AssertExpectations(t)
	mockCompletionProd.AssertExpectations(t)
}
