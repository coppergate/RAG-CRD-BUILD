package pulsar

import (
    "context"
    "encoding/json"
    "fmt"
    "sync"
    "time"

    "github.com/apache/pulsar-client-go/pulsar"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/propagation"
    "app-builds/llm-gateway/internal/config"
)

type PulsarClient struct {
	client         pulsar.Client
	producer       pulsar.Producer
	promptProducer pulsar.Producer
	pending        sync.Map // correlationID -> chan response
}

type response struct {
	ID     string `json:"id"`
	Result string `json:"result"`
	Error  string `json:"error"`
}

func NewPulsarClient(cfg *config.Config) (*PulsarClient, error) {
	client, err := pulsar.NewClient(pulsar.ClientOptions{
		URL: cfg.PulsarURL,
	})
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

	pc := &PulsarClient{
		client:         client,
		producer:       producer,
		promptProducer: promptProducer,
	}

	go pc.consumeResults(cfg.ResponseTopic)

	return pc, nil
}

func (pc *PulsarClient) consumeResults(topic string) {
	consumer, err := pc.client.Subscribe(pulsar.ConsumerOptions{
		Topic:            topic,
		SubscriptionName: "gateway-results-sub",
		Type:             pulsar.Shared,
	})
	if err != nil {
		fmt.Printf("Error subscribing to results: %v\n", err)
		return
	}
	defer consumer.Close()

	for {
		msg, err := consumer.Receive(context.Background())
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

		consumer.Ack(msg)
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
	case <-time.After(120 * time.Second):
		return "", fmt.Errorf("request timed out")
	}
}

func (pc *PulsarClient) SendPromptEvent(ctx context.Context, id, sessionID, content string) error {
	payload := map[string]string{
		"id":         id,
		"session_id": sessionID,
		"content":    content,
	}
	data, _ := json.Marshal(payload)
	_, err := pc.promptProducer.Send(ctx, &pulsar.ProducerMessage{
		Payload: data,
	})
	return err
}

func (pc *PulsarClient) Close() {
	pc.producer.Close()
	pc.promptProducer.Close()
	pc.client.Close()
}
