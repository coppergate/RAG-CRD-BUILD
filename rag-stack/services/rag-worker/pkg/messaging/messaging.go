package messaging

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"

	"app-builds/common/contracts"
	pulsarCommon "app-builds/common/pulsar"
	"app-builds/rag-worker/internal/config"
)

// Producers holds all Pulsar producers used by the worker.
type Producers struct {
	Results    pulsar.Producer
	Status     pulsar.Producer
	Plan       pulsar.Producer
	Search     pulsar.Producer
	Exec       pulsar.Producer
	QdrantOps  pulsar.Producer
	Completion pulsar.Producer
}

// Client wraps the Pulsar client and all producers/consumers for the worker.
type Client struct {
	client           *pulsarCommon.Client
	Producers        Producers
	sessionProducers sync.Map // map[string]pulsar.Producer
}

func (c *Client) SessionTopic(id string) string {
	return fmt.Sprintf("persistent://rag-pipeline/sessions/%s", id)
}

// NewClient creates a Pulsar client and all required producers.
func NewClient(cfg *config.Config) (*Client, error) {
	client, err := pulsarCommon.NewClient(pulsarCommon.Config{URL: cfg.PulsarURL})
	if err != nil {
		return nil, fmt.Errorf("could not instantiate Pulsar client: %w", err)
	}

	results, err := client.NewProducer(cfg.PulsarResultsTopic)
	if err != nil {
		client.Close()
		return nil, fmt.Errorf("could not create Results producer: %w", err)
	}

	status, err := client.NewProducer(cfg.PulsarStatusTopic)
	if err != nil {
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Status producer: %w", err)
	}

	plan, err := client.NewProducer(cfg.PulsarPlanTopic)
	if err != nil {
		status.Close()
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Plan producer: %w", err)
	}
	
	search, err := client.NewProducer(cfg.PulsarSearchTopic)
	if err != nil {
		plan.Close()
		status.Close()
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Search producer: %w", err)
	}

	exec, err := client.NewProducer(cfg.PulsarExecTopic)
	if err != nil {
		search.Close()
		plan.Close()
		status.Close()
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Exec producer: %w", err)
	}

	qOps, err := client.NewProducer(cfg.QdrantOpsTopic)
	if err != nil {
		exec.Close()
		plan.Close()
		status.Close()
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Qdrant ops producer: %w", err)
	}

	completion, err := client.NewProducer(cfg.PulsarCompletionTopic)
	if err != nil {
		qOps.Close()
		exec.Close()
		plan.Close()
		status.Close()
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create completion producer: %w", err)
	}

	return &Client{
		client: client,
		Producers: Producers{
			Results:    results,
			Status:     status,
			Plan:       plan,
			Search:     search,
			Exec:       exec,
			QdrantOps:  qOps,
			Completion: completion,
		},
	}, nil
}

// PulsarClient returns the underlying Pulsar client for consumer subscriptions.
func (c *Client) PulsarClient() pulsar.Client {
	return c.client
}

// Close closes all producers and the client.
func (c *Client) Close() {
	c.Producers.Completion.Close()
	c.Producers.QdrantOps.Close()
	c.Producers.Exec.Close()
	c.Producers.Search.Close()
	c.Producers.Plan.Close()
	c.Producers.Status.Close()
	c.Producers.Results.Close()
	c.client.Close()
}

// SendStatus sends a status message to the status topic.
func (c *Client) SendStatus(ctx context.Context, id, sessionID, state, details string) {
	payload := &contracts.StatusMessage{
		Id:        id,
		SessionId: sessionID,
		State:     state,
		Details:   details,
	}
	if _, err := pulsarCommon.SendProto(ctx, c.Producers.Status, payload); err != nil {
		log.Printf("[%s] Failed to send status message: %v", id, err)
	}
}

// SendResult sends a result message as a single chunk for consistency with the aggregator.
func (c *Client) SendResult(ctx context.Context, id, sessionID, result, model string, metadata map[string]interface{}) {
	log.Printf("[%s] Sending non-streaming result as final chunk", id)
	c.SendStreamChunk(ctx, id, sessionID, result, 0, true, model, true, metadata)
}

func (c *Client) getSessionProducer(topic string) (pulsar.Producer, error) {
	if p, ok := c.sessionProducers.Load(topic); ok {
		return p.(pulsar.Producer), nil
	}

	producer, err := c.client.NewProducer(topic)
	if err != nil {
		return nil, err
	}

	// Double check if another goroutine created it in the meantime
	if actual, loaded := c.sessionProducers.LoadOrStore(topic, producer); loaded {
		producer.Close() // Close the redundant one
		return actual.(pulsar.Producer), nil
	}

	return producer, nil
}

func (c *Client) SendStreamChunk(ctx context.Context, id, sessionID, result string, sequence int, isLast bool, model string, inConversation bool, metadata map[string]interface{}) {
	topic := c.SessionTopic(id)
	producer, err := c.getSessionProducer(topic)
	if err != nil {
		log.Printf("[%s] Failed to get session producer for %s: %v", id, topic, err)
		return
	}

	msgPayload := &contracts.StreamChunk{
		Id:             id,
		SessionId:      sessionID,
		Result:         result,
		SequenceNumber: int32(sequence),
		IsLast:         isLast,
		Model:          model,
		InConversation: inConversation,
		Metadata:       contracts.ToStruct(metadata),
	}

	if _, err := pulsarCommon.SendProto(ctx, producer, msgPayload); err != nil {
		log.Printf("[%s] Failed to send stream chunk to session topic %s: %v", id, topic, err)
	}

	// Also send to the global results topic for database persistence
	if _, err := pulsarCommon.SendProto(ctx, c.Producers.Results, msgPayload); err != nil {
		log.Printf("[%s] Failed to send stream chunk to global results topic: %v", id, err)
	}

	if isLast {
		c.sessionProducers.Delete(topic)
		// Close asynchronously to avoid blocking and allow in-flight sends to finish
		go func() {
			time.Sleep(2 * time.Second)
			producer.Close()
		}()
	}
}

func (c *Client) SendPlanningResponse(ctx context.Context, id, sessionID, planningResponse string) {
	topic := c.SessionTopic(id)
	producer, err := c.getSessionProducer(topic)
	if err != nil {
		log.Printf("[%s] Failed to get session producer for planning %s: %v", id, topic, err)
		return
	}

	msgPayload := &contracts.StreamChunk{
		Id:               id,
		SessionId:        sessionID,
		PlanningResponse: planningResponse,
		IsLast:           false,
	}

	if _, err := pulsarCommon.SendProto(ctx, producer, msgPayload); err != nil {
		log.Printf("[%s] Failed to send planning response to session topic %s: %v", id, topic, err)
	} else {
		log.Printf("[%s] Sent planning response to session topic %s", id, topic)
	}

	// Also send to the global results topic for database persistence
	if _, err := pulsarCommon.SendProto(ctx, c.Producers.Results, msgPayload); err != nil {
		log.Printf("[%s] Failed to send planning response to global results topic: %v", id, err)
	}
}

func (c *Client) SendError(ctx context.Context, id, errMsg string, inConversation bool) {
	topic := c.SessionTopic(id)
	producer, err := c.getSessionProducer(topic)
	if err != nil {
		log.Printf("[%s] Failed to get session producer for error %s: %v", id, topic, err)
		return
	}

	msgPayload := &contracts.StreamChunk{
		Id:             id,
		Error:          errMsg,
		InConversation: inConversation,
		IsLast:         true,
	}

	if _, err := pulsarCommon.SendProto(ctx, producer, msgPayload); err != nil {
		log.Printf("[%s] Failed to send error to topic %s: %v", id, topic, err)
	}

	c.sessionProducers.Delete(topic)
	go func() {
		time.Sleep(2 * time.Second)
		producer.Close()
	}()
}

// SendCompletion sends a completion event to the completion topic.
func (c *Client) SendCompletion(ctx context.Context, id, sessionID, startTS, model, status string, metrics *contracts.ExecutionMetrics) {
	log.Printf("[%s] Sending completion event (status: %s)", id, status)
	payload := &contracts.ResponseCompletion{
		Id:             id,
		SessionId:      sessionID,
		StartTimestamp: startTS,
		Model:          model,
		Status:         status,
		Metrics:        metrics,
	}
	if _, err := pulsarCommon.SendProto(ctx, c.Producers.Completion, payload); err != nil {
		log.Printf("[%s] Failed to send completion message: %v", id, err)
	}
}

// Ping checks if the client is healthy.
func (c *Client) Ping() error {
	if c.client == nil {
		return fmt.Errorf("pulsar client is nil")
	}
	// No direct ping method, so we verify the client isn't closed
	// (we can't easily check actual connectivity without sending a msg)
	return nil
}
