package pipeline

import (
	"context"
	"fmt"
	"testing"

	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"google.golang.org/protobuf/encoding/protojson"

	"app-builds/common/contracts"
	"app-builds/common/dlq"
	"app-builds/rag-worker/internal/config"
	"app-builds/rag-worker/pkg/messaging"
)

func TestHandleSearch_LargeVectorStore(t *testing.T) {
	mockSearcher := new(MockSearcher)
	mockRegistry := new(MockRegistry)
	mockPlanner := new(MockPlanner)
	mockMem := new(MockMemoryClient)
	mockStatusProd := new(MockProducer)
	mockExecProd := new(MockProducer)

	cfg := &config.Config{
		PlannerModel:         "default-planner",
		EmbeddingModel:       "embed-model",
		ChunkVectorLimit:     50,
		QdrantRetrievalLimit: 10000,
	}

	h := &Handler{
		cfg:          cfg,
		registry:     mockRegistry,
		searcher:     mockSearcher,
		memoryClient: mockMem,
		msg: &messaging.Client{
			Producers: messaging.Producers{
				Status: mockStatusProd,
				Exec:   mockExecProd,
			},
		},
	}

	req := &contracts.InternalRequest{
		Id:             "large-test-id",
		SessionId:      1,
		Prompt:         "analyze the whole project",
		Tags:           []int64{101},
		EmbeddingModel: "embed-model",
	}

	mockRegistry.On("GetPlanner", "default-planner").Return(mockPlanner, nil)
	mockRegistry.On("GetPlanner", "embed-model").Return(mockPlanner, nil)

	// Mock status updates
	mockStatusProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	// Create 120 results across 3 files
	// File 1: 60 items (will be split)
	// File 2: 40 items
	// File 3: 40 items

	var tagResults []interface{}
	// Just return a subset in Search, let RetrieveByPaths fetch the rest
	for i := 0; i < 30; i++ {
		tagResults = append(tagResults, map[string]interface{}{
			"_qdrant_id":      fmt.Sprintf("f1-%d", i),
			"path":            "file1.txt",
			"chunk":           float64(i),
			"content":         fmt.Sprintf("file1 content %d", i),
			"embedding_model": "embed-model",
			"vector_size":     float64(384),
		})
	}
	for i := 0; i < 40; i++ {
		tagResults = append(tagResults, map[string]interface{}{
			"_qdrant_id":      fmt.Sprintf("f2-%d", i),
			"path":            "file2.txt",
			"chunk":           float64(i),
			"content":         fmt.Sprintf("file2 content %d", i),
			"embedding_model": "embed-model",
			"vector_size":     float64(384),
		})
	}
	for i := 0; i < 40; i++ {
		tagResults = append(tagResults, map[string]interface{}{
			"_qdrant_id":      fmt.Sprintf("f3-%d", i),
			"path":            "file3.txt",
			"chunk":           float64(i),
			"content":         fmt.Sprintf("file3 content %d", i),
			"embedding_model": "embed-model",
			"vector_size":     float64(384),
		})
	}

	mockSearcher.On("Search", mock.Anything, "embed-model", []float32(nil), []int64{101}, int64(1), false, 10000).Return(tagResults, nil)

	// Mock RetrieveByPaths for all files
	var allFileChunks []interface{}
	mockMem.On("Retrieve", mock.Anything, int64(1), []int64{101}, "analyze the whole project").Return(&contracts.MemoryPack{}, nil)
	// Full file1 (60 chunks)
	for i := 0; i < 60; i++ {
		allFileChunks = append(allFileChunks, map[string]interface{}{
			"_qdrant_id":      fmt.Sprintf("f1-%d", i),
			"path":            "file1.txt",
			"chunk":           float64(i),
			"content":         fmt.Sprintf("file1 content %d", i),
			"embedding_model": "embed-model",
			"vector_size":     float64(384),
		})
	}
	// Full file2 (40 chunks)
	for i := 0; i < 40; i++ {
		allFileChunks = append(allFileChunks, map[string]interface{}{
			"_qdrant_id":      fmt.Sprintf("f2-%d", i),
			"path":            "file2.txt",
			"chunk":           float64(i),
			"content":         fmt.Sprintf("file2 content %d", i),
			"embedding_model": "embed-model",
			"vector_size":     float64(384),
		})
	}
	// Full file3 (40 chunks)
	for i := 0; i < 40; i++ {
		allFileChunks = append(allFileChunks, map[string]interface{}{
			"_qdrant_id":      fmt.Sprintf("f3-%d", i),
			"path":            "file3.txt",
			"chunk":           float64(i),
			"content":         fmt.Sprintf("file3 content %d", i),
			"embedding_model": "embed-model",
			"vector_size":     float64(384),
		})
	}

	// RetrieveByPaths called with all 3 paths
	mockSearcher.On("RetrieveByPaths", mock.Anything, "embed-model", mock.MatchedBy(func(paths []string) bool {
		return len(paths) == 3
	})).Return(allFileChunks, nil)

	// Mock planner embeddings for the prompt itself
	mockPlanner.On("GetEmbeddings", mock.Anything, "analyze the whole project").Return([]float32{0.1}, nil)
	mockPlanner.On("Plan", mock.Anything, "analyze the whole project", mock.Anything, mock.Anything).Return(&contracts.PlannerTaskPlan{
		Objective:     "analyze the whole project",
		ActionType:    "FILE_SEARCH",
		SearchQueries: []string{"refined coverage"},
		ContextBudget: 2,
	}, nil, nil)
	// Mock vector search for prompt (returns empty for simplicity, we focus on tag results)
	mockSearcher.On("Search", mock.Anything, "embed-model", []float32{0.1}, []int64{101}, int64(1), false, mock.Anything).Return([]interface{}{}, nil)

	// Mock memory retrieval
	mockMem.On("Retrieve", mock.Anything, int64(1), []int64{101}, "analyze the whole project").Return(&contracts.MemoryPack{}, nil)

	// Mock send to exec topic and capture the payload
	var capturedPayload []byte
	mockExecProd.On("Send", mock.Anything, mock.MatchedBy(func(m *pulsar.ProducerMessage) bool {
		capturedPayload = m.Payload
		return true
	})).Return(nil, nil)

	// Call handleSearch
	result, err := h.handleSearch(context.Background(), req)

	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, result)

	// Verify the captured payload
	var outReq contracts.InternalRequest
	err = protojson.Unmarshal(capturedPayload, &outReq)
	assert.NoError(t, err)

	metadata := contracts.FromStruct(outReq.Metadata)
	assert.NotNil(t, metadata)

	chunks, ok := metadata["chunks"].([]interface{})
	assert.True(t, ok, "chunks should be present in metadata")

	// Expecting 3 chunks as calculated:
	// Chunk 1: File 1 (0-49) = 50 items
	// Chunk 2: File 1 (50-59) + File 2 (0-39) = 50 items
	// Chunk 3: File 3 (0-39) = 40 items
	assert.Len(t, chunks, 3)

	chunk1 := chunks[0].([]interface{})
	assert.Len(t, chunk1, 1, "Chunk 1 should contain 1 large reassembled file part")
	c1Str := chunk1[0].(string)
	assert.Contains(t, c1Str, "--- File: file1.txt [embed-model] (Part 1) ---")
	assert.Contains(t, c1Str, "file1 content 0")
	assert.Contains(t, c1Str, "file1 content 49")
	assert.NotContains(t, c1Str, "file1 content 50")

	chunk2 := chunks[1].([]interface{})
	// Chunk 2 contains Part 2 of File 1 AND all of File 2 (because 10 + 40 <= 50)
	assert.Len(t, chunk2, 2)
	assert.Contains(t, chunk2[0].(string), "--- File: file1.txt [embed-model] (Part 2) ---")
	assert.Contains(t, chunk2[0].(string), "file1 content 50")
	assert.Contains(t, chunk2[0].(string), "file1 content 59")
	assert.Contains(t, chunk2[1].(string), "--- File: file2.txt [embed-model] ---")
	assert.Contains(t, chunk2[1].(string), "file2 content 0")
	assert.Contains(t, chunk2[1].(string), "file2 content 39")

	chunk3 := chunks[2].([]interface{})
	assert.Len(t, chunk3, 1)
	assert.Contains(t, chunk3[0].(string), "--- File: file3.txt [embed-model] ---")
	assert.Contains(t, chunk3[0].(string), "file3 content 0")
	assert.Contains(t, chunk3[0].(string), "file3 content 39")

	mockSearcher.AssertExpectations(t)
}

func TestHandleExec_MultiChunk(t *testing.T) {
	mockRegistry := new(MockRegistry)
	mockPlanner := new(MockPlanner)
	mockExecutor := new(MockExecutor)
	mockStatusProd := new(MockProducer)
	mockResultsProd := new(MockProducer)
	mockCompletionProd := new(MockProducer)

	cfg := &config.Config{
		PlannerModel:  "p-model",
		ExecutorModel: "e-model",
	}

	h := &Handler{
		cfg:      cfg,
		registry: mockRegistry,
	}

	msgClient := &messaging.Client{
		Producers: messaging.Producers{
			Status:     mockStatusProd,
			Results:    mockResultsProd,
			Completion: mockCompletionProd,
		},
	}
	// Pre-populate session producer to avoid using real Pulsar client
	msgClient.Producers.Results = mockResultsProd
	topic := msgClient.SessionTopic("multi-chunk-test")
	msgClient.SetSessionProducer(topic, mockResultsProd)
	h.msg = msgClient

	chunks := [][]interface{}{
		{"chunk 1 context"},
		{"chunk 2 context"},
	}

	req := &contracts.InternalRequest{
		Id:            "multi-chunk-test",
		SessionId:     1,
		Prompt:        "multi-chunk prompt",
		PlannerModel:  "p-model",
		ExecutorModel: "e-model",
		Metadata: contracts.ToStruct(map[string]interface{}{
			"chunks": chunks,
		}),
	}

	mockRegistry.On("GetPlanner", "p-model").Return(mockPlanner, nil)
	mockRegistry.On("GetExecutor", "e-model").Return(mockExecutor, nil)

	// Mock status updates
	mockStatusProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)
	// Mock completion
	mockCompletionProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	// Planner.Plan should be called for each chunk to "refine"
	mockPlanner.On("Plan", mock.Anything, "multi-chunk prompt", chunks[0], mock.Anything).Return(&contracts.PlannerTaskPlan{
		Objective:     "multi-chunk prompt",
		ActionType:    "FILE_SEARCH",
		SearchQueries: []string{"refined plan 1"},
		ContextBudget: 1,
	}, nil, nil)
	mockPlanner.On("Plan", mock.Anything, "multi-chunk prompt", chunks[1], mock.Anything).Return(&contracts.PlannerTaskPlan{
		Objective:     "multi-chunk prompt",
		ActionType:    "FILE_SEARCH",
		SearchQueries: []string{"refined plan 2"},
		ContextBudget: 1,
	}, nil, nil)

	// Executor.Execute should be called for each chunk
	mockExecutor.On("Execute", mock.Anything, "multi-chunk prompt", chunks[0], mock.Anything).Return("part 1", nil, nil)
	mockExecutor.On("Execute", mock.Anything, "multi-chunk prompt", chunks[1], mock.Anything).Return("part 2", nil, nil)

	// Grounding check for each chunk and then final
	mockExecutor.On("IsInsufficientContext", "part 1").Return(false)
	mockExecutor.On("IsInsufficientContext", "part 2").Return(false)
	mockExecutor.On("IsInsufficientContext", "part 1part 2").Return(false)

	// Mock status updates
	mockStatusProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	// Capture final result
	var finalResult string
	mockResultsProd.On("Send", mock.Anything, mock.MatchedBy(func(m *pulsar.ProducerMessage) bool {
		var res contracts.StreamChunk
		protojson.Unmarshal(m.Payload, &res)
		finalResult = res.Result
		return true
	})).Return(nil, nil)

	result, err := h.handleExec(context.Background(), req)

	assert.NoError(t, err)
	assert.Equal(t, dlq.Success, result)
	assert.Equal(t, "part 1part 2", finalResult)

	mockPlanner.AssertExpectations(t)
	mockExecutor.AssertExpectations(t)
	mockCompletionProd.AssertExpectations(t)
}
