package search

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"google.golang.org/protobuf/encoding/protojson"

	"app-builds/common/contracts"
	"app-builds/rag-worker/internal/config"
)

// QdrantSearcher handles Qdrant search operations via Pulsar message passing.
type QdrantSearcher struct {
	cfg      *config.Config
	producer pulsar.Producer
	pending  sync.Map // correlationID -> chan []interface{}
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

			var resp contracts.QdrantResponse
			if err := protojson.Unmarshal(msg.Payload(), &resp); err == nil {
				if resp.Error != "" {
					log.Printf("[%s] Qdrant search returned error: %s", resp.Id, resp.Error)
				}
				if ch, ok := s.pending.Load(resp.Id); ok {
					val := contracts.FromValue(resp.Result)
					if res, ok := val.([]interface{}); ok {
						log.Printf("[%s] Qdrant search returned %d items", resp.Id, len(res))
						ch.(chan []interface{}) <- res
					} else {
						log.Printf("[%s] Qdrant search result was not a list: %T", resp.Id, val)
						ch.(chan []interface{}) <- nil
					}
				} else {
					log.Printf("[%s] Received Qdrant result but no pending request found", resp.Id)
				}
			} else {
				log.Printf("Failed to unmarshal Qdrant response: %v", err)
			}
		}
	}()
}

// Search sends a search request to Qdrant via Pulsar and waits for the result.
func (s *QdrantSearcher) Search(ctx context.Context, vector []float32, tags []int64, sessionID int64, includeGlobal bool) ([]interface{}, error) {
	if len(vector) == 0 && len(tags) == 0 {
		log.Printf("DEBUG: Skipping Qdrant search for session %d - empty vector and no tags", sessionID)
		return nil, nil
	}
	id := fmt.Sprintf("search-%d", time.Now().UnixNano())
	resChan := make(chan []interface{}, 1)
	s.pending.Store(id, resChan)
	defer s.pending.Delete(id)

	op := contracts.QdrantOp{
		Id:            id,
		Action:        "search",
		Collection:    s.cfg.QdrantCollection,
		VectorSize:    int32(len(vector)),
		Vector:        vector,
		Limit:         int32(s.cfg.QdrantSearchLimit),
		Tags:          tags,
		SessionId:     sessionID,
		IncludeGlobal: includeGlobal,
	}
	marshaller := protojson.MarshalOptions{
		UseProtoNames: true,
	}
	payload, err := marshaller.Marshal(&op)
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

// RetrieveByPaths fetches all points for the given paths.
func (s *QdrantSearcher) RetrieveByPaths(ctx context.Context, paths []string) ([]interface{}, error) {
	if len(paths) == 0 {
		return nil, nil
	}
	id := fmt.Sprintf("paths-%d", time.Now().UnixNano())
	resChan := make(chan []interface{}, 1)
	s.pending.Store(id, resChan)
	defer s.pending.Delete(id)

	op := contracts.QdrantOp{
		Id:         id,
		Action:     "retrieve_paths",
		Collection: s.cfg.QdrantCollection,
		Paths:      paths,
	}
	marshaller := protojson.MarshalOptions{
		UseProtoNames: true,
	}
	payload, err := marshaller.Marshal(&op)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal paths request: %w", err)
	}

	if _, err := s.producer.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		return nil, fmt.Errorf("failed to send paths request: %w", err)
	}

	select {
	case res := <-resChan:
		return res, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(s.cfg.QdrantSearchTimeout):
		return nil, fmt.Errorf("qdrant paths retrieval timed out after %s", s.cfg.QdrantSearchTimeout)
	}
}
