package dlq

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"app-builds/common/telemetry"
	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
)

const (
	defaultMaxRetries = 3
	retryCountProp    = "dlq-retry-count"
	origTopicProp     = "dlq-original-topic"
	firstFailureProp  = "dlq-first-failure"
	lastErrorProp     = "dlq-last-error"
)

// Handler wraps a Pulsar consumer with retry and DLQ routing logic.
type Handler struct {
	maxRetries  int
	dlqProducer pulsar.Producer
	serviceName string

	dlqRouted    metric.Int64Counter
	dlqRetried   metric.Int64Counter
	dlqSucceeded metric.Int64Counter
}

// NewHandler creates a DLQ handler. It creates a DLQ producer on the
// topic "persistent://rag-pipeline/dlq/<serviceName>".
// maxRetries defaults to 3 if <= 0.
func NewHandler(client pulsar.Client, serviceName string) (*Handler, error) {
	maxRetries := defaultMaxRetries
	if v := os.Getenv("DLQ_MAX_RETRIES"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			maxRetries = n
		}
	}

	dlqTopic := fmt.Sprintf("persistent://rag-pipeline/dlq/%s", serviceName)
	prod, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: dlqTopic,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create DLQ producer for %s: %w", dlqTopic, err)
	}

	log.Printf("DLQ handler initialized for %s (max_retries=%d, dlq_topic=%s)", serviceName, maxRetries, dlqTopic)

	meter := telemetry.Meter("dlq")
	dlqRouted, _ := meter.Int64Counter("dlq_routed_total",
		metric.WithDescription("Messages routed to DLQ (permanent failure)"))
	dlqRetried, _ := meter.Int64Counter("dlq_retried_total",
		metric.WithDescription("Messages NACK'd for retry (transient failure)"))
	dlqSucceeded, _ := meter.Int64Counter("dlq_succeeded_total",
		metric.WithDescription("Messages processed successfully"))

	return &Handler{
		maxRetries:   maxRetries,
		dlqProducer:  prod,
		serviceName:  serviceName,
		dlqRouted:    dlqRouted,
		dlqRetried:   dlqRetried,
		dlqSucceeded: dlqSucceeded,
	}, nil
}

// ProcessResult represents the outcome of message processing.
type ProcessResult int

const (
	// Success indicates the message was processed successfully.
	Success ProcessResult = iota
	// TransientFailure indicates a temporary error; the message should be retried.
	TransientFailure
	// PermanentFailure indicates a non-recoverable error; send to DLQ immediately.
	PermanentFailure
)

// HandleMessage processes a message with retry/DLQ logic.
// processFunc should return the processing result and an error (if any).
// The handler will ACK successful messages, NACK transient failures (up to
// maxRetries), and route to DLQ on permanent failures or exhausted retries.
func (h *Handler) HandleMessage(
	ctx context.Context,
	msg pulsar.Message,
	consumer pulsar.Consumer,
	processFunc func(ctx context.Context, msg pulsar.Message) (ProcessResult, error),
) {
	result, processErr := processFunc(ctx, msg)

	attrs := metric.WithAttributes(attribute.String("service", h.serviceName))

	switch result {
	case Success:
		h.dlqSucceeded.Add(ctx, 1, attrs)
		consumer.Ack(msg)
		return

	case PermanentFailure:
		h.dlqRouted.Add(ctx, 1, attrs)
		log.Printf("[DLQ] Permanent failure processing message on %s: %v", msg.Topic(), processErr)
		h.routeToDLQ(ctx, msg, processErr)
		consumer.Ack(msg) // ACK after DLQ routing to prevent redelivery
		return

	case TransientFailure:
		retryCount := h.getRetryCount(msg)
		if retryCount >= h.maxRetries {
			h.dlqRouted.Add(ctx, 1, attrs)
			log.Printf("[DLQ] Max retries (%d) exhausted for message on %s: %v", h.maxRetries, msg.Topic(), processErr)
			h.routeToDLQ(ctx, msg, processErr)
			consumer.Ack(msg)
			return
		}

		h.dlqRetried.Add(ctx, 1, attrs)
		log.Printf("[DLQ] Transient failure (retry %d/%d) on %s: %v", retryCount+1, h.maxRetries, msg.Topic(), processErr)
		consumer.Nack(msg)
	}
}

func (h *Handler) getRetryCount(msg pulsar.Message) int {
	if v, ok := msg.Properties()[retryCountProp]; ok {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return int(msg.RedeliveryCount())
}

func (h *Handler) routeToDLQ(ctx context.Context, msg pulsar.Message, processErr error) {
	props := make(map[string]string)
	// Copy original properties
	for k, v := range msg.Properties() {
		props[k] = v
	}
	props[origTopicProp] = msg.Topic()
	props[retryCountProp] = strconv.Itoa(h.getRetryCount(msg))
	props[firstFailureProp] = time.Now().Format(time.RFC3339)
	if processErr != nil {
		errMsg := processErr.Error()
		if len(errMsg) > 500 {
			errMsg = errMsg[:500]
		}
		props[lastErrorProp] = errMsg
	}

	// Log full payload for debugging
	payloadStr := string(msg.Payload())
	if len(payloadStr) > 2000 {
		payloadStr = payloadStr[:2000] + "...(truncated)"
	}
	log.Printf("[DLQ] Routing message to DLQ. Service=%s, OrigTopic=%s, Payload=%s", h.serviceName, msg.Topic(), payloadStr)

	_, err := h.dlqProducer.Send(ctx, &pulsar.ProducerMessage{
		Payload:    msg.Payload(),
		Properties: props,
	})
	if err != nil {
		log.Printf("[DLQ] CRITICAL: Failed to send message to DLQ: %v. Original payload: %s", err, payloadStr)
	}
}

// Close closes the DLQ producer.
func (h *Handler) Close() {
	h.dlqProducer.Close()
}

// DLQMessage represents a message in the DLQ for inspection/replay.
type DLQMessage struct {
	OriginalTopic string `json:"original_topic"`
	RetryCount    int    `json:"retry_count"`
	FirstFailure  string `json:"first_failure"`
	LastError     string `json:"last_error"`
	Payload       json.RawMessage `json:"payload"`
}
