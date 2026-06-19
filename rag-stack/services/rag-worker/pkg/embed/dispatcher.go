package embed

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"

	"github.com/apache/pulsar-client-go/pulsar"

	"app-builds/common/logging"
)

// EmbedJob is published by rag-worker to the embed/jobs Pulsar topic.
// It must stay in sync with the identical struct in embed-gateway.
type EmbedJob struct {
	RequestID        string `json:"request_id"`
	SubQueryIndex    int    `json:"sub_query_index"`
	SubQuery         string `json:"sub_query"`
	EmbeddingModel   string `json:"embedding_model"`
	VectorSize       int    `json:"vector_size"`
	WorkerInstanceID string `json:"worker_instance_id"`
	DeadlineUnix     int64  `json:"deadline_unix"`
}

// EmbedResult is sent by embed-gateway to the per-worker result topic.
// It must stay in sync with the identical struct in embed-gateway.
type EmbedResult struct {
	RequestID      string    `json:"request_id"`
	SubQueryIndex  int       `json:"sub_query_index"`
	EmbeddingModel string    `json:"embedding_model"`
	Vector         []float32 `json:"vector"`
	Error          string    `json:"error"`
	DurationMs     int64     `json:"duration_ms"`
	GatewayID      string    `json:"gateway_id"`
}

// ResultDispatcher owns a single Pulsar consumer on the per-worker result topic
// (persistent://rag-pipeline/embed/results-{workerInstanceID}) and dispatches
// incoming results to the correct in-flight request channel by request_id.
//
// One dispatcher runs per rag-worker pod for the process lifetime.
type ResultDispatcher struct {
	mu       sync.RWMutex
	pending  map[string]chan EmbedResult // requestID → buffered channel
	consumer pulsar.Consumer
	topic    string
}

// NewResultDispatcher subscribes to the per-worker result topic and returns a
// dispatcher. The caller must start the dispatcher via Run in a goroutine.
func NewResultDispatcher(pulsarClient pulsar.Client, workerInstanceID string) (*ResultDispatcher, error) {
	topic := fmt.Sprintf("persistent://rag-pipeline/embed/results-%s", workerInstanceID)
	consumer, err := pulsarClient.Subscribe(pulsar.ConsumerOptions{
		Topic:            topic,
		SubscriptionName: "embed-results-sub",
		Type:             pulsar.Exclusive,
	})
	if err != nil {
		return nil, fmt.Errorf("result dispatcher subscribe to %s: %w", topic, err)
	}
	return &ResultDispatcher{
		pending:  make(map[string]chan EmbedResult),
		consumer: consumer,
		topic:    topic,
	}, nil
}

// Register allocates a buffered channel for an in-flight request.
// Must be called BEFORE publishing embed jobs to avoid missing results.
// n = number of results expected (len(subQueries) × len(embeddingModels)).
func (d *ResultDispatcher) Register(requestID string, n int) <-chan EmbedResult {
	ch := make(chan EmbedResult, n)
	d.mu.Lock()
	d.pending[requestID] = ch
	d.mu.Unlock()
	return ch
}

// Deregister removes the channel mapping. Must be called in a defer after
// the gather phase completes to prevent memory leaks.
func (d *ResultDispatcher) Deregister(requestID string) {
	d.mu.Lock()
	delete(d.pending, requestID)
	d.mu.Unlock()
}

// Run is the dispatcher's main loop. Runs as a background goroutine for the
// lifetime of the rag-worker process. Returns when ctx is cancelled.
func (d *ResultDispatcher) Run(ctx context.Context) {
	logging.Printf("[result-dispatcher] started on topic %s", d.topic)
	for {
		msg, err := d.consumer.Receive(ctx)
		if err != nil {
			if ctx.Err() != nil {
				logging.Printf("[result-dispatcher] shutting down: %v", ctx.Err())
				return
			}
			logging.Printf("[result-dispatcher] receive error: %v — retrying", err)
			continue
		}

		var result EmbedResult
		if err := json.Unmarshal(msg.Payload(), &result); err != nil {
			logging.Printf("[result-dispatcher] malformed result message — discarding: %v", err)
			d.consumer.Ack(msg)
			continue
		}

		d.mu.RLock()
		ch, ok := d.pending[result.RequestID]
		d.mu.RUnlock()

		if ok {
			ch <- result
			logging.Printf("[result-dispatcher] dispatched result request=%s sub_query=%d model=%s gateway=%s duration=%dms",
				result.RequestID, result.SubQueryIndex, result.EmbeddingModel,
				result.GatewayID, result.DurationMs)
		} else {
			// Stale result — request already timed out or completed.
			logging.Printf("[result-dispatcher] stale result request=%s sub_query=%d model=%s gateway=%s — no pending handler (request may have timed out)",
				result.RequestID, result.SubQueryIndex, result.EmbeddingModel, result.GatewayID)
		}
		d.consumer.Ack(msg)
	}
}

// Close shuts down the underlying Pulsar consumer.
func (d *ResultDispatcher) Close() {
	d.consumer.Close()
}
