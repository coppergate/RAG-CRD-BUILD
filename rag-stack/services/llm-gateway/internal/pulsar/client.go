package pulsar

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"

	"app-builds/common/tlsutil"
	"app-builds/llm-gateway/internal/config"
)

type PulsarClient struct {
	client         pulsar.Client
	producer       pulsar.Producer
	promptProducer pulsar.Producer
	consumer       pulsar.Consumer
	pending        sync.Map // correlationID -> chan response
	requestTimeout time.Duration
}

type response struct {
	ID     string `json:"id"`
	Result string `json:"result"`
	Error  string `json:"error"`
}

func NewPulsarClient(cfg *config.Config) (*PulsarClient, error) {
	opts := pulsar.ClientOptions{
		URL: cfg.PulsarURL,
	}
	if certPath := tlsutil.PulsarTLSCertPath(cfg.PulsarURL); certPath != "" {
		opts.TLSTrustCertsFilePath = certPath
	}

	client, err := pulsar.NewClient(opts)
	if err != nil {
		return nil, fmt.Errorf("could not create pulsar client: %w", err)
	}

	producer, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.RequestTopic,
	})
	if err != nil {
		client.Close()
		return nil, fmt.Errorf("could not create pulsar producer: %w", err)
	}

	promptProducer, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.PromptTopic,
	})
	if err != nil {
		producer.Close()
		client.Close()
		return nil, fmt.Errorf("could not create prompt producer: %w", err)
	}

	consumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.ResponseTopic,
		SubscriptionName: "gateway-results-sub",
		Type:             pulsar.Shared,
	})
	if err != nil {
		promptProducer.Close()
		producer.Close()
		client.Close()
		return nil, fmt.Errorf("could not subscribe to results topic %s: %w", cfg.ResponseTopic, err)
	}

	pc := &PulsarClient{
		client:         client,
		producer:       producer,
		promptProducer: promptProducer,
		consumer:       consumer,
		requestTimeout: cfg.RequestTimeout,
	}

	go pc.consumeResults()

	return pc, nil
}

func (pc *PulsarClient) consumeResults() {
	for {
		msg, err := pc.consumer.Receive(context.Background())
		if err != nil {
			fmt.Printf("Error receiving message: %v\n", err)
			continue
		}

		var resp response
		if err := json.Unmarshal(msg.Payload(), &resp); err == nil {
			if ch, ok := pc.pending.Load(resp.ID); ok {
				ch.(chan response) <- resp
			}
		}
		pc.consumer.Ack(msg)
	}
}

func (pc *PulsarClient) SendRequest(ctx context.Context, id string, payload interface{}) (string, error) {
	tracer := otel.Tracer("pulsar-client")
	ctx, span := tracer.Start(ctx, "SendRequest")
	defer span.End()

	resChan := make(chan response, 1)
	pc.pending.Store(id, resChan)
	defer pc.pending.Delete(id)

	data, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	msg := &pulsar.ProducerMessage{
		Payload: data,
	}

	// Inject tracing context into Pulsar message properties
	if msg.Properties == nil {
		msg.Properties = make(map[string]string)
	}
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msg.Properties))

	_, err = pc.producer.Send(ctx, msg)
	if err != nil {
		return "", err
	}

	select {
	case res := <-resChan:
		if res.Error != "" {
			return "", fmt.Errorf("worker error: %s", res.Error)
		}
		return res.Result, nil
	case <-ctx.Done():
		return "", ctx.Err()
	case <-time.After(pc.requestTimeout):
		return "", fmt.Errorf("request timed out after %s", pc.requestTimeout)
	}
}

func (pc *PulsarClient) SendPromptEvent(ctx context.Context, id, sessionID, content string) error {
	payload := map[string]string{
		"id":         id,
		"session_id": sessionID,
		"content":    content,
	}
	data, err := json.Marshal(payload)
	if err != nil {
		log.Printf("[%s] Failed to marshal prompt event: %v", id, err)
		return fmt.Errorf("marshal prompt event: %w", err)
	}
	_, err = pc.promptProducer.Send(ctx, &pulsar.ProducerMessage{
		Payload: data,
	})
	return err
}

func (pc *PulsarClient) Close() {
	pc.consumer.Close()
	pc.producer.Close()
	pc.promptProducer.Close()
	pc.client.Close()
}
