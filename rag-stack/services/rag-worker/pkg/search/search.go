package search

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"

	"app-builds/rag-worker/internal/config"
)

// QdrantSearcher handles Qdrant search operations via Pulsar message passing.
type QdrantSearcher struct {
	cfg      *config.Config
	producer pulsar.Producer
	pending  sync.Map // correlationID -> chan []string
}

// NewQdrantSearcher creates a new Qdrant searcher that sends search requests
// via the given producer and receives results via the StartResultConsumer goroutine.
func NewQdrantSearcher(cfg *config.Config, producer pulsar.Producer) *QdrantSearcher {
	return &QdrantSearcher{
		cfg:      cfg,
		producer: producer,
	}
}

// StartResultConsumer starts a goroutine that listens for Qdrant search results
// and routes them to pending search requests.
func (s *QdrantSearcher) StartResultConsumer(consumer pulsar.Consumer) {
	go func() {
		for {
			msg, err := consumer.Receive(context.Background())
			if err != nil {
				log.Printf("Error receiving Qdrant result: %v", err)
				continue
			}
			consumer.Ack(msg)

			var resp struct {
				ID     string   `json:"id"`
				Result []string `json:"result"`
				Error  string   `json:"error"`
			}
			if err := json.Unmarshal(msg.Payload(), &resp); err == nil {
				if resp.Error != "" {
					log.Printf("[%s] Qdrant search returned error: %s", resp.ID, resp.Error)
				}
				if ch, ok := s.pending.Load(resp.ID); ok {
					ch.(chan []string) <- resp.Result
				}
			}
		}
	}()
}

// Search sends a search request to Qdrant via Pulsar and waits for the result.
func (s *QdrantSearcher) Search(ctx context.Context, vector []float32, tags []string, sessionID string) ([]string, error) {
	if len(vector) == 0 {
		log.Printf("DEBUG: Skipping Qdrant search for session %s - empty vector", sessionID)
		return nil, nil
	}
	id := fmt.Sprintf("search-%d", time.Now().UnixNano())
	resChan := make(chan []string, 1)
	s.pending.Store(id, resChan)
	defer s.pending.Delete(id)

	op := map[string]interface{}{
		"id":          id,
		"action":      "search",
		"collection":  s.cfg.QdrantCollection,
		"vector_size": len(vector),
		"vector":      vector,
		"limit":       s.cfg.QdrantSearchLimit,
		"tags":        tags,
		"session_id":  sessionID,
	}
	payload, err := json.Marshal(op)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal search request: %w", err)
	}

	if _, err := s.producer.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		return nil, fmt.Errorf("failed to send search request: %w", err)
	}

	select {
	case res := <-resChan:
		return res, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(s.cfg.QdrantSearchTimeout):
		return nil, fmt.Errorf("qdrant search timed out after %s", s.cfg.QdrantSearchTimeout)
	}
}
