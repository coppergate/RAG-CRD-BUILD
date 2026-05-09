package search

import (
	"context"
	"testing"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	"app-builds/rag-worker/internal/config"
)

type MockProducer struct {
	mock.Mock
	pulsar.Producer
}

func (m *MockProducer) Send(ctx context.Context, msg *pulsar.ProducerMessage) (pulsar.MessageID, error) {
	args := m.Called(ctx, msg)
	return nil, args.Error(1)
}

type MockConsumer struct {
	mock.Mock
	pulsar.Consumer
}

func (m *MockConsumer) Receive(ctx context.Context) (pulsar.Message, error) {
	args := m.Called(ctx)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(pulsar.Message), args.Error(1)
}

func (m *MockConsumer) Ack(msg pulsar.Message) {
	m.Called(msg)
}

type MockMessage struct {
	pulsar.Message
	payload []byte
}

func (m *MockMessage) Payload() []byte {
	return m.payload
}

func TestSearch_Success(t *testing.T) {
	mockProd := new(MockProducer)
	cfg := &config.Config{
		QdrantCollection:    "test-coll",
		QdrantSearchTimeout: 1 * time.Second,
	}
	s := NewQdrantSearcher(cfg, mockProd)

	mockProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	// In a real scenario, StartResultConsumer would populate resChan.
	// We simulate this by manually putting something in the pending map.
	id := ""
	go func() {
		// Wait for ID to be stored
		for {
			s.pending.Range(func(key, value interface{}) bool {
				id = key.(string)
				value.(chan []interface{}) <- []interface{}{map[string]interface{}{"found": true}}
				return false
			})
			if id != "" {
				break
			}
			time.Sleep(10 * time.Millisecond)
		}
	}()

	res, err := s.Search(context.Background(), []float32{0.1}, nil, 1, false)
	assert.NoError(t, err)
	assert.Len(t, res, 1)
}

func TestSearch_Timeout(t *testing.T) {
	mockProd := new(MockProducer)
	cfg := &config.Config{
		QdrantCollection:    "test-coll",
		QdrantSearchTimeout: 50 * time.Millisecond,
	}
	s := NewQdrantSearcher(cfg, mockProd)

	mockProd.On("Send", mock.Anything, mock.Anything).Return(nil, nil)

	// Don't populate resChan, let it timeout
	res, err := s.Search(context.Background(), []float32{0.1}, nil, 1, false)
	
	assert.Error(t, err)
	assert.Nil(t, res)
	assert.Contains(t, err.Error(), "timed out")
}

func TestSearch_Empty(t *testing.T) {
	s := &QdrantSearcher{}
	res, err := s.Search(context.Background(), nil, nil, 1, false)
	assert.NoError(t, err)
	assert.Nil(t, res)
}
