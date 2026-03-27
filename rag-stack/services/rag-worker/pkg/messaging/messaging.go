package messaging

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"

	"app-builds/common/tlsutil"
	"app-builds/rag-worker/internal/config"
)

// Producers holds all Pulsar producers used by the worker.
type Producers struct {
	Results pulsar.Producer
	Status  pulsar.Producer
	Plan    pulsar.Producer
	Exec    pulsar.Producer
	QdrantOps pulsar.Producer
}

// Client wraps the Pulsar client and all producers/consumers for the worker.
type Client struct {
	client    pulsar.Client
	Producers Producers
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

	exec, err := client.CreateProducer(pulsar.ProducerOptions{Topic: cfg.PulsarExecTopic})
	if err != nil {
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

	return &Client{
		client: client,
		Producers: Producers{
			Results:   results,
			Status:    status,
			Plan:      plan,
			Exec:      exec,
			QdrantOps: qOps,
		},
	}, nil
}

// PulsarClient returns the underlying Pulsar client for consumer subscriptions.
func (c *Client) PulsarClient() pulsar.Client {
	return c.client
}

// Close closes all producers and the client.
func (c *Client) Close() {
	c.Producers.QdrantOps.Close()
	c.Producers.Exec.Close()
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

// SendResult sends a final result message to the results topic with tracing context.
func (c *Client) SendResult(ctx context.Context, id, sessionID, result, model string) {
	payload, err := json.Marshal(map[string]interface{}{
		"id":              id,
		"session_id":      sessionID,
		"result":          result,
		"sequence_number": 1,
		"model":           model,
	})
	if err != nil {
		log.Printf("[%s] Failed to marshal result: %v", id, err)
		return
	}

	msg := &pulsar.ProducerMessage{
		Payload:    payload,
		Properties: make(map[string]string),
	}
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msg.Properties))

	if _, err := c.Producers.Results.Send(ctx, msg); err != nil {
		log.Printf("[%s] Failed to send result to topic: %v", id, err)
	} else {
		log.Printf("[%s] Result sent", id)
	}
}

// SendStreamChunk sends a streaming result chunk to the results topic.
func (c *Client) SendStreamChunk(ctx context.Context, id, sessionID, chunk string, sequence int, isLast bool, model string) {
	payload, err := json.Marshal(map[string]interface{}{
		"id":              id,
		"session_id":      sessionID,
		"chunk":           chunk,
		"sequence_number": sequence,
		"is_last":         isLast,
		"model":           model,
	})
	if err != nil {
		log.Printf("[%s] Failed to marshal stream chunk: %v", id, err)
		return
	}

	msg := &pulsar.ProducerMessage{
		Payload:    payload,
		Properties: make(map[string]string),
	}
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msg.Properties))

	if _, err := c.Producers.Results.Send(ctx, msg); err != nil {
		log.Printf("[%s] Failed to send stream chunk to topic: %v", id, err)
	}
}

// SendError sends an error message to the results topic.
func (c *Client) SendError(ctx context.Context, id, errMsg string) {
	payload, err := json.Marshal(map[string]string{
		"id":    id,
		"error": errMsg,
	})
	if err != nil {
		log.Printf("[%s] Failed to marshal error: %v", id, err)
		return
	}
	if _, err := c.Producers.Results.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		log.Printf("[%s] Failed to send error to topic: %v", id, err)
	}
}
