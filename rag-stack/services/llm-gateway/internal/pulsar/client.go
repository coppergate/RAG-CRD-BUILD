package pulsar

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"

	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"app-builds/common/contracts"
	pulsarCommon "app-builds/common/pulsar"
	"app-builds/llm-gateway/internal/config"
)

type pulsarClient struct {
	client         *pulsarCommon.Client
	producer       pulsar.Producer
	promptProducer pulsar.Producer
	consumer       pulsar.Consumer
	pending        sync.Map // correlationID -> chan response
	streams        sync.Map // correlationID -> context.CancelFunc
	requestTimeout time.Duration
}

type response = *contracts.StreamChunk

func NewPulsarClient(cfg *config.Config) (Client, error) {
	client, err := pulsarCommon.NewClient(pulsarCommon.Config{URL: cfg.PulsarURL})
	if err != nil {
		return nil, fmt.Errorf("could not create pulsar client: %w", err)
	}

	producer, err := client.NewProducer(cfg.RequestTopic)
	if err != nil {
		client.Close()
		return nil, fmt.Errorf("could not create pulsar producer: %w", err)
	}

	promptProducer, err := client.NewProducer(cfg.PromptTopic)
	if err != nil {
		producer.Close()
		client.Close()
		return nil, fmt.Errorf("could not create prompt producer: %w", err)
	}

	consumer, err := client.NewSharedConsumer(cfg.ResponseTopic, "gateway-results-sub")
	if err != nil {
		promptProducer.Close()
		producer.Close()
		client.Close()
		return nil, fmt.Errorf("could not subscribe to results topic %s: %w", cfg.ResponseTopic, err)
	}

	pc := &pulsarClient{
		client:         client,
		producer:       producer,
		promptProducer: promptProducer,
		consumer:       consumer,
		requestTimeout: cfg.RequestTimeout,
	}

	go pc.consumeResults()

	return pc, nil
}

func (pc *pulsarClient) consumeResults() {
	for {
		msg, err := pc.consumer.Receive(context.Background())
		if err != nil {
			fmt.Printf("Error receiving message: %v\n", err)
			continue
		}

		resp := &contracts.StreamChunk{}
		if err := protojson.Unmarshal(msg.Payload(), resp); err == nil {
			if ch, ok := pc.pending.Load(resp.Id); ok {
				ch.(chan response) <- resp
			}
		}
		pc.consumer.Ack(msg)
	}
}

func (pc *pulsarClient) SendRequest(ctx context.Context, id string, payload proto.Message) (*contracts.StreamChunk, error) {
	tracer := otel.Tracer("pulsar-client")
	ctx, span := tracer.Start(ctx, "SendRequest")
	defer span.End()

	resChan := make(chan response, 10) // Buffered channel for multiple chunks
	pc.pending.Store(id, resChan)
	defer pc.pending.Delete(id)

	_, err := pulsarCommon.SendProto(ctx, pc.producer, payload)
	if err != nil {
		return nil, err
	}

	var finalRes *contracts.StreamChunk
	for {
		select {
		case res := <-resChan:
			if res.Error != "" {
				return nil, fmt.Errorf("worker error: %s", res.Error)
			}
			if finalRes == nil {
				// Clone the first response
				finalRes = proto.Clone(res).(*contracts.StreamChunk)
			} else {
				// Accumulate
				finalRes.Result += res.Result
				if res.PlanningResponse != "" {
					finalRes.PlanningResponse = res.PlanningResponse
				}
			}
			if res.IsLast {
				return finalRes, nil
			}
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(pc.requestTimeout):
			return nil, fmt.Errorf("request timed out after %s", pc.requestTimeout)
		}
	}
}

func (pc *pulsarClient) SendPromptEvent(ctx context.Context, id string, sessionID int64, content string) error {
	payload := map[string]interface{}{
		"id":         id,
		"session_id": sessionID,
		"content":    content,
	}
	_, err := pulsarCommon.SendJSON(ctx, pc.promptProducer, payload)
	return err
}

func (pc *pulsarClient) SessionTopic(id string) string {
	return fmt.Sprintf("persistent://rag-pipeline/sessions/%s", id)
}

func (pc *pulsarClient) SubscribeStream(id string, ch chan *contracts.StreamChunk) {
	ctx, cancel := context.WithCancel(context.Background())
	pc.streams.Store(id, cancel)

	go func() {
		defer cancel()
		topic := pc.SessionTopic(id)
		consumer, err := pc.client.Subscribe(pulsar.ConsumerOptions{
			Topic:            topic,
			SubscriptionName: fmt.Sprintf("gateway-%s", id),
			Type:             pulsar.Exclusive,
		})
		if err != nil {
			log.Printf("[%s] Failed to subscribe to session topic %s: %v", id, topic, err)
			return
		}
		defer consumer.Close()

		for {
			msg, err := consumer.Receive(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				log.Printf("[%s] Consumer receive error: %v", id, err)
				return
			}

			chunk := &contracts.StreamChunk{}
			if err := protojson.Unmarshal(msg.Payload(), chunk); err == nil {
				ch <- chunk
				if chunk.IsLast {
					consumer.Ack(msg)
					return
				}
			}
			consumer.Ack(msg)
		}
	}()
}

func (pc *pulsarClient) UnsubscribeStream(id string) {
	if cancel, ok := pc.streams.LoadAndDelete(id); ok {
		cancel.(context.CancelFunc)()
	}
}

func (pc *pulsarClient) SendRawRequest(ctx context.Context, payload proto.Message) error {
	_, err := pulsarCommon.SendProto(ctx, pc.producer, payload)
	return err
}

func (pc *pulsarClient) Close() {
	pc.consumer.Close()
	pc.producer.Close()
	pc.promptProducer.Close()
	pc.client.Close()
}

// Ping checks if the client is healthy.
func (pc *pulsarClient) Ping() error {
	if pc.client == nil {
		return fmt.Errorf("pulsar client is nil")
	}
	return nil
}
