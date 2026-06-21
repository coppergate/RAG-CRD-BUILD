package gateway

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"

	"app-builds/common/logging"
	"app-builds/embed-gateway/internal/config"
	"app-builds/embed-gateway/internal/discovery"
)

// ollamaEmbedRequest matches the /api/embeddings request body.
type ollamaEmbedRequest struct {
	Model  string `json:"model"`
	Prompt string `json:"prompt"`
}

// ollamaEmbedResponse matches the /api/embeddings response body.
type ollamaEmbedResponse struct {
	Embedding []float32 `json:"embedding"`
}

// Gateway consumes embed jobs from Pulsar and dispatches them to node-local Ollama.
type Gateway struct {
	cfg         *config.Config
	consumer    pulsar.Consumer
	pulsarCli   pulsar.Client
	discover    *discovery.NodeLocalURLs
	httpClient  *http.Client

	// producerCache is keyed by reply topic name.
	producerMu    sync.Mutex
	producerCache map[string]pulsar.Producer
}

// New creates a Gateway. The caller must call Run to start processing.
func New(cfg *config.Config, pulsarCli pulsar.Client, consumer pulsar.Consumer, discover *discovery.NodeLocalURLs) *Gateway {
	return &Gateway{
		cfg:           cfg,
		consumer:      consumer,
		pulsarCli:     pulsarCli,
		discover:      discover,
		httpClient:    &http.Client{Timeout: cfg.OllamaTimeout},
		producerCache: make(map[string]pulsar.Producer),
	}
}

// Run starts the worker pool. It blocks until ctx is cancelled.
func (g *Gateway) Run(ctx context.Context) {
	sem := make(chan struct{}, g.cfg.Workers)

	logging.Printf("[%s] embed-gateway started: workers=%d jobs_topic=%s node=%s",
		g.cfg.GatewayID, g.cfg.Workers, g.cfg.EmbedJobsTopic, g.cfg.NodeName)

	for {
		msg, err := g.consumer.Receive(ctx)
		if err != nil {
			if ctx.Err() != nil {
				logging.Printf("[%s] shutting down", g.cfg.GatewayID)
				return
			}
			logging.Printf("[%s] consumer receive error: %v", g.cfg.GatewayID, err)
			continue
		}

		sem <- struct{}{}
		go func(m pulsar.Message) {
			defer func() { <-sem }()
			g.processJob(ctx, m)
		}(msg)
	}
}

func (g *Gateway) processJob(ctx context.Context, msg pulsar.Message) {
	var job EmbedJob
	if err := json.Unmarshal(msg.Payload(), &job); err != nil {
		logging.Printf("[%s] malformed embed job — acking and discarding: %v", g.cfg.GatewayID, err)
		g.consumer.Ack(msg)
		return
	}

	if time.Now().Unix() > job.DeadlineUnix {
		logging.Printf("[%s] embed job for request=%s sub_query=%d expired (deadline %d) — discarding",
			g.cfg.GatewayID, job.RequestID, job.SubQueryIndex, job.DeadlineUnix)
		g.consumer.Ack(msg)
		return
	}

	start := time.Now()
	vector, err := g.ollamaEmbed(ctx, job.SubQuery, job.EmbeddingModel)
	durationMs := time.Since(start).Milliseconds()

	result := EmbedResult{
		RequestID:      job.RequestID,
		SubQueryIndex:  job.SubQueryIndex,
		EmbeddingModel: job.EmbeddingModel,
		DurationMs:     durationMs,
		GatewayID:      g.cfg.GatewayID,
	}

	if err != nil {
		logging.Printf("[%s] Ollama embed failed request=%s sub_query=%d model=%s: %v",
			g.cfg.GatewayID, job.RequestID, job.SubQueryIndex, job.EmbeddingModel, err)
		result.Error = err.Error()
		if isTransientOllamaError(err) {
			g.consumer.NackID(msg.ID())
			return
		}
	} else {
		result.Vector = vector
		logging.Printf("[%s] embed complete request=%s sub_query=%d model=%s dims=%d duration=%dms",
			g.cfg.GatewayID, job.RequestID, job.SubQueryIndex, job.EmbeddingModel, len(vector), durationMs)
	}

	replyTopic := fmt.Sprintf("persistent://rag-pipeline/embed/results-%s", job.WorkerInstanceID)
	if err := g.publishResult(ctx, replyTopic, result); err != nil {
		logging.Printf("[%s] failed to publish result request=%s sub_query=%d topic=%s: %v",
			g.cfg.GatewayID, job.RequestID, job.SubQueryIndex, replyTopic, err)
		g.consumer.NackID(msg.ID())
		return
	}

	g.consumer.Ack(msg)
}

// ollamaEmbed calls the Ollama /api/embeddings endpoint on a node-local pod.
// On connection failure, it triggers re-discovery and retries once against the fallback.
func (g *Gateway) ollamaEmbed(ctx context.Context, text, model string) ([]float32, error) {
	ollamaURL, isLocal := g.discover.Next()

	vector, err := g.callOllamaEmbed(ctx, ollamaURL, text, model)
	if err == nil {
		return vector, nil
	}

	// If local pod failed, re-discover and try fallback.
	if isLocal && isTransientOllamaError(err) {
		logging.Printf("[%s] node-local Ollama at %s failed (%v) — refreshing discovery and retrying via fallback",
			g.cfg.GatewayID, ollamaURL, err)
		g.discover.Refresh()
		fallbackURL, _ := g.discover.Next()
		return g.callOllamaEmbed(ctx, fallbackURL, text, model)
	}

	return nil, err
}

func (g *Gateway) callOllamaEmbed(ctx context.Context, baseURL, text, model string) ([]float32, error) {
	body, err := json.Marshal(ollamaEmbedRequest{Model: model, Prompt: text})
	if err != nil {
		return nil, fmt.Errorf("marshal embed request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(baseURL, "/")+"/api/embeddings", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := g.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("ollama http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		rawBody, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("ollama returned %d: %s", resp.StatusCode, strings.TrimSpace(string(rawBody)))
	}

	var embedResp ollamaEmbedResponse
	if err := json.NewDecoder(resp.Body).Decode(&embedResp); err != nil {
		return nil, fmt.Errorf("decode embed response: %w", err)
	}
	if len(embedResp.Embedding) == 0 {
		return nil, fmt.Errorf("ollama returned empty embedding for model %s", model)
	}
	return embedResp.Embedding, nil
}

// publishResult sends an EmbedResult to the given Pulsar topic using a cached producer.
func (g *Gateway) publishResult(ctx context.Context, topic string, result EmbedResult) error {
	producer, err := g.getOrCreateProducer(topic)
	if err != nil {
		return fmt.Errorf("get producer for %s: %w", topic, err)
	}

	payload, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("marshal result: %w", err)
	}

	_, err = producer.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
		Properties: map[string]string{
			"request_id": result.RequestID,
			"gateway_id": result.GatewayID,
		},
	})
	return err
}

func (g *Gateway) getOrCreateProducer(topic string) (pulsar.Producer, error) {
	g.producerMu.Lock()
	defer g.producerMu.Unlock()

	if p, ok := g.producerCache[topic]; ok {
		return p, nil
	}

	p, err := g.pulsarCli.CreateProducer(pulsar.ProducerOptions{
		Topic:           topic,
		CompressionType: pulsar.LZ4,
	})
	if err != nil {
		return nil, err
	}
	g.producerCache[topic] = p
	logging.Printf("[%s] created producer for result topic %s", g.cfg.GatewayID, topic)
	return p, nil
}

// Close releases all cached producers.
func (g *Gateway) Close() {
	g.producerMu.Lock()
	defer g.producerMu.Unlock()
	for topic, p := range g.producerCache {
		p.Close()
		logging.Printf("[%s] closed producer for %s", g.cfg.GatewayID, topic)
	}
}

// isTransientOllamaError returns true for errors that warrant a nack/retry
// rather than a permanent failure.
func isTransientOllamaError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "connection refused") ||
		strings.Contains(msg, "connection reset") ||
		strings.Contains(msg, "timeout") ||
		strings.Contains(msg, "503") ||
		strings.Contains(msg, "502") ||
		strings.Contains(msg, "no such host") ||
		strings.Contains(msg, "eof")
}
