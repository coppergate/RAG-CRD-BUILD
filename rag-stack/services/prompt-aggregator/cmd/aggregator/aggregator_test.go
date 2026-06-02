package main

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	"app-builds/common/contracts"
)

// MockPulsarClient is a mock of pulsar.Client
type MockPulsarClient struct {
	mock.Mock
	pulsar.Client
}

func (m *MockPulsarClient) CreateReader(options pulsar.ReaderOptions) (pulsar.Reader, error) {
	args := m.Called(options)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(pulsar.Reader), args.Error(1)
}

// MockPulsarReader is a mock of pulsar.Reader
type MockPulsarReader struct {
	mock.Mock
	pulsar.Reader
}

func (m *MockPulsarReader) Next(ctx context.Context) (pulsar.Message, error) {
	args := m.Called(ctx)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(pulsar.Message), args.Error(1)
}

func (m *MockPulsarReader) HasNext() bool {
	args := m.Called()
	return args.Bool(0)
}

func (m *MockPulsarReader) Close() {
	m.Called()
}

// MockMessage is a mock of pulsar.Message
type MockMessage struct {
	pulsar.Message
	payload []byte
}

func (m *MockMessage) Payload() []byte {
	return m.payload
}

func TestAssemble(t *testing.T) {
	chunks := map[int32]*contracts.StreamChunk{
		1: {SequenceNumber: 1, Result: " world"},
		0: {SequenceNumber: 0, Result: "Hello"},
	}
	
	content := assemble(chunks)
	
	assert.Equal(t, "Hello world", content)
}

func TestAggregateChunks_Success(t *testing.T) {
	mockClient := new(MockPulsarClient)
	mockReader := new(MockPulsarReader)
	
	comp := &contracts.ResponseCompletion{
		Id: "req-1",
	}
	
	mockClient.On("CreateReader", mock.Anything).Return(mockReader, nil)
	mockReader.On("HasNext").Return(true).Twice()
	mockReader.On("HasNext").Return(false)
	
	c0 := &contracts.StreamChunk{Id: "req-1", SequenceNumber: 0, Result: "Part 1"}
	b0, _ := json.Marshal(c0)
	msg0 := &MockMessage{payload: b0}
	
	c1 := &contracts.StreamChunk{Id: "req-1", SequenceNumber: 1, Result: " Part 2", IsLast: true}
	b1, _ := json.Marshal(c1)
	msg1 := &MockMessage{payload: b1}
	
	mockReader.On("Next", mock.Anything).Return(msg0, nil).Once()
	mockReader.On("Next", mock.Anything).Return(msg1, nil).Once()
	mockReader.On("Close").Return()
	
	content, _, err := aggregateChunks(context.Background(), mockClient, "topic", comp, 30*time.Second)
	
	assert.NoError(t, err)
	assert.Equal(t, "Part 1 Part 2", content)
}

func TestAggregateChunks_Timeout(t *testing.T) {
	mockClient := new(MockPulsarClient)
	mockReader := new(MockPulsarReader)
	
	comp := &contracts.ResponseCompletion{
		Id: "req-1",
	}
	
	mockClient.On("CreateReader", mock.Anything).Return(mockReader, nil)
	mockReader.On("HasNext").Return(true)
	
	// Simulate reader hanging or taking too long
	mockReader.On("Next", mock.Anything).Run(func(args mock.Arguments) {
		ctx := args.Get(0).(context.Context)
		select {
		case <-ctx.Done():
		case <-time.After(100 * time.Millisecond):
		}
	}).Return(nil, context.DeadlineExceeded)
	
	mockReader.On("Close").Return()
	
	// Use a short context to trigger timeout
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	
	_, _, err := aggregateChunks(ctx, mockClient, "topic", comp, 30*time.Second)
	
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "context deadline exceeded")
}
