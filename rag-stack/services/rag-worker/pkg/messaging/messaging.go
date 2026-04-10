package messaging

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"

	"app-builds/common/contracts"
	"app-builds/common/tlsutil"
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
	client    pulsar.Client
	Producers Producers
}

func (c *Client) SessionTopic(id string) string {
	return fmt.Sprintf("persistent://rag-pipeline/sessions/%s", id)
}

// NewClient creates a Pulsar client and all required producers.
func NewClient(cfg *config.Config) (*Client, error) {
	opts := pulsar.ClientOptions{
		URL: cfg.PulsarURL,
	}
	if certPath := tlsutil.PulsarTLSCertPath(cfg.PulsarURL); certPath != "" {
		opts.TLSTrustCertsFilePath = certPath
	}

	client, err := pulsar.NewClient(opts)
	if err != nil {
		return nil, fmt.Errorf("could not instantiate Pulsar client: %w", err)
	}

	results, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.PulsarResultsTopic})
	if err != nil {
		client.Close()
		return nil, fmt.Errorf("could not create Results producer: %w", err)
	}

	status, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.PulsarStatusTopic})
	if err != nil {
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Status producer: %w", err)
	}

	plan, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.PulsarPlanTopic})
	if err != nil {
		status.Close()
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Plan producer: %w", err)
	}
	
	search, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.PulsarSearchTopic})
	if err != nil {
		plan.Close()
		status.Close()
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Search producer: %w", err)
	}

	exec, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.PulsarExecTopic})
	if err != nil {
		search.Close()
		plan.Close()
		status.Close()
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Exec producer: %w", err)
	}

	qOps, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.QdrantOpsTopic})
	if err != nil {
		exec.Close()
		plan.Close()
		status.Close()
		results.Close()
		client.Close()
		return nil, fmt.Errorf("could not create Qdrant ops producer: %w", err)
	}

	completion, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.PulsarCompletionTopic})
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
	payload, err := json.Marshal(map[string]interface{}{
		"id":         id,
		"session_id": sessionID,
		"state":      state,
		"details":    details,
		"timestamp":  "",
	})
	if err != nil {
		log.Printf("[%s] Failed to marshal status: %v", id, err)
		return
	}
	if _, err := c.Producers.Status.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		log.Printf("[%s] Failed to send status message: %v", id, err)
	}
}

// SendResult sends a result message as a single chunk for consistency with the aggregator.
func (c *Client) SendResult(ctx context.Context, id, sessionID, result, model string, metadata map[string]interface{}) {
	log.Printf("[%s] Sending non-streaming result as final chunk", id)
	c.SendStreamChunk(ctx, id, sessionID, result, 0, true, model, true, metadata)
}

func (c *Client) SendStreamChunk(ctx context.Context, id, sessionID, chunk string, sequence int, isLast bool, model string, inConversation bool, metadata map[string]interface{}) {
	topic := c.SessionTopic(id)
	producer, err := c.client.CreateProducer(pulsar.ProducerOptions{
		Topic: topic,
	})
	if err != nil {
		log.Printf("[%s] Failed to create session producer for %s: %v", id, topic, err)
		return
	}
	defer producer.Close()

	msgPayload := contracts.StreamChunk{
		ID:             id,
		SessionID:      sessionID,
		Chunk:          chunk,
		SequenceNumber: sequence,
		IsLast:         isLast,
		Model:          model,
		InConversation: inConversation,
		Metadata:       metadata,
	}

	payload, err := json.Marshal(msgPayload)
	if err != nil {
		log.Printf("[%s] Failed to marshal stream chunk: %v", id, err)
		return
	}

	msg := &pulsar.ProducerMessage{
		Payload:    payload,
		Properties: make(map[string]string),
	}
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msg.Properties))

	if _, err := producer.Send(ctx, msg); err != nil {
		log.Printf("[%s] Failed to send stream chunk to topic %s: %v", id, topic, err)
	}
}

func (c *Client) SendError(ctx context.Context, id, errMsg string, inConversation bool) {
	topic := c.SessionTopic(id)
	producer, err := c.client.CreateProducer(pulsar.ProducerOptions{
		Topic: topic,
	})
	if err != nil {
		log.Printf("[%s] Failed to create session producer for error %s: %v", id, topic, err)
		return
	}
	defer producer.Close()

	msgPayload := contracts.StreamChunk{
		ID:             id,
		Error:          errMsg,
		InConversation: inConversation,
	}

	payload, err := json.Marshal(msgPayload)
	if err != nil {
		log.Printf("[%s] Failed to marshal error: %v", id, err)
		return
	}
	if _, err := producer.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		log.Printf("[%s] Failed to send error to topic %s: %v", id, topic, err)
	}
}

// SendCompletion sends a completion event to the completion topic.
func (c *Client) SendCompletion(ctx context.Context, id, sessionID, startTS, model, status string) {
	log.Printf("[%s] Sending completion event (status: %s)", id, status)
	payload, err := json.Marshal(map[string]interface{}{
		"id":               id,
		"session_id":       sessionID,
		"start_timestamp":  startTS,
		"model":            model,
		"status":           status,
	})
	if err != nil {
		log.Printf("[%s] Failed to marshal completion: %v", id, err)
		return
	}
	if _, err := c.Producers.Completion.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
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
