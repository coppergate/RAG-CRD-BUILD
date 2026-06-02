package pulsar

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/otel"

	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"app-builds/common/contracts"
	"app-builds/common/logging"
	pulsarCommon "app-builds/common/pulsar"
	"app-builds/llm-gateway/internal/config"
)

type pulsarClient struct {
	client         *pulsarCommon.Client
	producer       pulsar.Producer
	promptProducer pulsar.Producer
	streams        sync.Map // correlationID -> context.CancelFunc
	requestTimeout time.Duration
}

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

	pc := &pulsarClient{
		client:         client,
		producer:       producer,
		promptProducer: promptProducer,
		requestTimeout: cfg.RequestTimeout,
	}

	return pc, nil
}

func (pc *pulsarClient) SendRequest(ctx context.Context, id string, payload proto.Message) (*contracts.StreamChunk, error) {
	ctx, span := otel.Tracer("pulsar-client").Start(ctx, "SendRequest")
	defer span.End()

	// Subscribe to the per-request session topic BEFORE publishing to avoid
	// a race where a very fast worker publishes chunks before we are ready.
	topic := pc.SessionTopic(id)
	consumer, err := pc.client.Subscribe(pulsar.ConsumerOptions{
		Topic:            topic,
		SubscriptionName: fmt.Sprintf("gateway-sync-%s", id),
		Type:             pulsar.Exclusive,
	})
	if err != nil {
		return nil, fmt.Errorf("subscribe session topic %s: %w", topic, err)
	}
	defer consumer.Close()

	if _, err := pulsarCommon.SendProto(ctx, pc.producer, payload); err != nil {
		return nil, err
	}

	timeoutCtx, cancel := context.WithTimeout(ctx, pc.requestTimeout)
	defer cancel()

	var finalRes *contracts.StreamChunk
	for {
		msg, err := consumer.Receive(timeoutCtx)
		if err != nil {
			if timeoutCtx.Err() != nil {
				return nil, fmt.Errorf("request timed out after %s", pc.requestTimeout)
			}
			return nil, fmt.Errorf("session topic receive error: %w", err)
		}

		chunk := &contracts.StreamChunk{}
		if protojson.Unmarshal(msg.Payload(), chunk) != nil {
			consumer.Ack(msg)
			continue
		}
		consumer.Ack(msg)

		if chunk.Error != "" {
			return nil, fmt.Errorf("worker error: %s", chunk.Error)
		}
		if finalRes == nil {
			finalRes = proto.Clone(chunk).(*contracts.StreamChunk)
		} else {
			finalRes.Result += chunk.Result
			if chunk.PlanningResponse != "" {
				finalRes.PlanningResponse = chunk.PlanningResponse
			}
			if chunk.Metadata != nil {
				finalRes.Metadata = chunk.Metadata
			}
		}
		if chunk.IsLast {
			return finalRes, nil
		}
	}
}

func (pc *pulsarClient) SendPromptEvent(ctx context.Context, id string, sessionID int64, content string, tags []int64) error {
	payload := map[string]interface{}{
		"id":         id,
		"session_id": sessionID,
		"content":    content,
		"tags":       tags,
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
			logging.Printf("[%s] Failed to subscribe to session topic %s: %v", id, topic, err)
			return
		}
		defer consumer.Close()

		for {
			msg, err := consumer.Receive(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				logging.Printf("[%s] Consumer receive error: %v", id, err)
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
