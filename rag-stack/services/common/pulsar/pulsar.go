package pulsar

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"

	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"

	"app-builds/common/tlsutil"
)

// Config holds the common Pulsar configuration.
type Config struct {
	URL            string
	RequestTimeout time.Duration
}

// Client is a wrapper around the Pulsar client that provides common utilities.
type Client struct {
	pulsar.Client
}

// NewClient creates a new Pulsar client with standard RAG stack defaults and TLS configuration.
func NewClient(cfg Config) (*Client, error) {
	opts := pulsar.ClientOptions{
		URL: cfg.URL,
	}

	if certPath := tlsutil.PulsarTLSCertPath(cfg.URL); certPath != "" {
		opts.TLSTrustCertsFilePath = certPath
	}

	client, err := pulsar.NewClient(opts)
	if err != nil {
		return nil, fmt.Errorf("could not create pulsar client: %w", err)
	}

	return &Client{Client: client}, nil
}

// NewProducer creates a producer with standard error handling.
func (c *Client) NewProducer(topic string) (pulsar.Producer, error) {
	producer, err := c.Client.CreateProducer(pulsar.ProducerOptions{
		Topic: topic,
	})
	if err != nil {
		return nil, fmt.Errorf("could not create producer for topic %s: %w", topic, err)
	}
	return producer, nil
}

// NewSharedConsumer creates a shared consumer with standard error handling.
func (c *Client) NewSharedConsumer(topic, subscription string) (pulsar.Consumer, error) {
	consumer, err := c.Client.Subscribe(pulsar.ConsumerOptions{
		Topic:            topic,
		SubscriptionName: subscription,
		Type:             pulsar.Shared,
	})
	if err != nil {
		return nil, fmt.Errorf("could not subscribe to topic %s: %w", topic, err)
	}
	return consumer, nil
}

// SendJSON marshals the payload to JSON and sends it with tracing context.
func SendJSON(ctx context.Context, producer pulsar.Producer, payload interface{}) (pulsar.MessageID, error) {
	data, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal payload: %w", err)
	}

	msg := &pulsar.ProducerMessage{
		Payload:    data,
		Properties: make(map[string]string),
	}

	// Inject tracing context
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msg.Properties))

	id, err := producer.Send(ctx, msg)
	if err != nil {
		return nil, fmt.Errorf("failed to send pulsar message: %w", err)
	}

	return id, nil
}

// SendProto marshals the Protobuf payload using protojson and sends it with tracing context.
func SendProto(ctx context.Context, producer pulsar.Producer, payload proto.Message) (pulsar.MessageID, error) {
	marshaller := protojson.MarshalOptions{
		UseProtoNames: true,
	}
	data, err := marshaller.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal proto payload: %w", err)
	}

	log.Printf("[PULSAR] Sending marshaled proto: %s", string(data))

	msg := &pulsar.ProducerMessage{
		Payload:    data,
		Properties: make(map[string]string),
	}

	// Inject tracing context
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msg.Properties))

	id, err := producer.Send(ctx, msg)
	if err != nil {
		return nil, fmt.Errorf("failed to send pulsar message: %w", err)
	}

	return id, nil
}

const (
	HealthTopic = "persistent://rag-pipeline/internal/health-ping"
)

// Ping checks if the client is healthy by checking topic partitions.
func (c *Client) Ping() error {
	if c.Client == nil {
		return fmt.Errorf("pulsar client is nil")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	// TopicPartitions is a lightweight call that requires broker connectivity.
	partitions, err := c.Client.TopicPartitions(HealthTopic)
	if err != nil {
		// If topic doesn't exist, we try to create a producer briefly to ensure it exists for next time.
		// Note: Most Pulsar setups auto-create topics.
		if strings.Contains(err.Error(), "TopicNotFound") || strings.Contains(err.Error(), "not found") {
			p, pErr := c.Client.CreateProducer(pulsar.ProducerOptions{
				Topic: HealthTopic,
			})
			if pErr == nil {
				p.Close()
				return nil
			}
		}

		// Only connection-level errors indicate a real failure.
		errMsg := err.Error()
		if strings.Contains(errMsg, "connection refused") ||
			strings.Contains(errMsg, "i/o timeout") ||
			strings.Contains(errMsg, "no such host") ||
			strings.Contains(errMsg, "Context deadline exceeded") {
			return fmt.Errorf("pulsar broker unreachable: %w", err)
		}
	}
	_ = partitions
	return nil
}
