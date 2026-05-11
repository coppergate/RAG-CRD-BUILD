package search

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	"app-builds/common/contracts"
	"app-builds/rag-worker/internal/config"
)

type MockQdrantClient struct {
	mock.Mock
}

func (m *MockQdrantClient) Search(ctx context.Context, op *contracts.QdrantOp) (*contracts.QdrantResponse, error) {
	args := m.Called(ctx, op)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*contracts.QdrantResponse), args.Error(1)
}

func TestSearch_Success(t *testing.T) {
	mockClient := new(MockQdrantClient)
	cfg := &config.Config{
		QdrantCollection: "test-coll",
	}
	s := NewQdrantSearcher(cfg, mockClient)

	expectedResult := []interface{}{map[string]interface{}{"found": true}}
	mockClient.On("Search", mock.Anything, mock.Anything).Return(&contracts.QdrantResponse{
		Id:     "search-123",
		Result: contracts.ToValue(expectedResult),
	}, nil)

	res, err := s.Search(context.Background(), []float32{0.1}, nil, 1, false, 0)
	assert.NoError(t, err)
	assert.Equal(t, expectedResult, res)
}

func TestSearch_Empty(t *testing.T) {
	s := &QdrantSearcher{}
	res, err := s.Search(context.Background(), nil, nil, 1, false, 0)
	assert.NoError(t, err)
	assert.Nil(t, res)
}

func TestRetrieveByPaths_Success(t *testing.T) {
	mockClient := new(MockQdrantClient)
	cfg := &config.Config{
		QdrantCollection: "test-coll",
	}
	s := NewQdrantSearcher(cfg, mockClient)

	expectedResult := []interface{}{map[string]interface{}{"path": "test.txt"}}
	mockClient.On("Search", mock.Anything, mock.MatchedBy(func(op *contracts.QdrantOp) bool {
		return op.Action == "retrieve_paths" && len(op.Paths) == 1 && op.Paths[0] == "test.txt"
	})).Return(&contracts.QdrantResponse{
		Id:     "paths-123",
		Result: contracts.ToValue(expectedResult),
	}, nil)

	res, err := s.RetrieveByPaths(context.Background(), []string{"test.txt"})
	assert.NoError(t, err)
	assert.Equal(t, expectedResult, res)
}
