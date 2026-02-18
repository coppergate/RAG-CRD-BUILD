package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"database/sql"
	_ "github.com/lib/pq"

	"github.com/apache/pulsar-client-go/pulsar"
	"app-builds/rag-worker/internal/config"
	"app-builds/rag-worker/internal/ollama"
	"app-builds/rag-worker/internal/telemetry"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

type Worker struct {
	cfg      *config.Config
	pulsar   pulsar.Client
	ollama   *ollama.OllamaClient
	db       *sql.DB
	producer pulsar.Producer
	qOpsProd pulsar.Producer
	pending  sync.Map // correlationID -> chan []string
}

func main() {
	cfg := config.LoadConfig()

	shutdown, err := telemetry.InitTracer("rag-worker")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	db, err := sql.Open("postgres", os.Getenv("DB_CONN_STRING"))
	if err != nil {
		log.Printf("Warning: Could not connect to database: %v", err)
	} else {
		defer db.Close()
	}

	client, err := pulsar.NewClient(pulsar.ClientOptions{
		URL: cfg.PulsarURL,
	})
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer client.Close()

	producer, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.PulsarResponseTopic,
	})
	if err != nil {
		log.Fatalf("Could not create Pulsar producer: %v", err)
	}
	defer producer.Close()

	qOpsProd, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: cfg.QdrantOpsTopic,
	})
	if err != nil {
		log.Fatalf("Could not create Qdrant ops producer: %v", err)
	}
	defer qOpsProd.Close()

	worker := &Worker{
		cfg:      cfg,
		pulsar:   client,
		ollama:   ollama.NewClient(cfg),
		db:       db,
		producer: producer,
		qOpsProd: qOpsProd,
	}

	// Consumer for Qdrant Results (Search results)
	qResultsSub := fmt.Sprintf("rag-worker-q-res-%s", os.Getenv("HOSTNAME"))
	qResConsumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.QdrantResultsTopic,
		SubscriptionName: qResultsSub,
		Type:             pulsar.Exclusive,
	})
	if err != nil {
		log.Fatalf("Could not subscribe to Qdrant results: %v", err)
	}
	defer qResConsumer.Close()

	go func() {
		for {
			msg, err := qResConsumer.Receive(context.Background())
			if err != nil {
				log.Printf("Error receiving Qdrant result: %v", err)
				continue
			}
			qResConsumer.Ack(msg)

			var resp struct {
				ID     string   `json:"id"`
				Result []string `json:"result"`
				Error  string   `json:"error"`
			}
			if err := json.Unmarshal(msg.Payload(), &resp); err == nil {
				if ch, ok := worker.pending.Load(resp.ID); ok {
					ch.(chan []string) <- resp.Result
				}
			}
		}
	}()

	// Consumer for RAG Tasks
	consumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.PulsarRequestTopic,
		SubscriptionName: cfg.PulsarSubscription,
		Type:             pulsar.Shared,
	})
	if err != nil {
		log.Fatalf("Could not create Pulsar consumer: %v", err)
	}
	defer consumer.Close()

	log.Printf("RAG Worker started, listening on %s", cfg.PulsarRequestTopic)

	for {
		msg, err := consumer.Receive(context.Background())
		if err != nil {
			log.Printf("Error receiving message: %v", err)
			continue
		}

		// Extract tracing context from Pulsar message properties
		msgCtx := otel.GetTextMapPropagator().Extract(context.Background(), propagation.MapCarrier(msg.Properties()))

		go worker.handleMessage(msgCtx, msg, consumer)
	}
}

func (w *Worker) searchQdrant(ctx context.Context, collection string, vector []float32, tags []string) ([]string, error) {
	id := fmt.Sprintf("search-%d", time.Now().UnixNano())
	resChan := make(chan []string, 1)
	w.pending.Store(id, resChan)
	defer w.pending.Delete(id)

	op := map[string]interface{}{
		"id":         id,
		"action":     "search",
		"collection": collection,
		"vector":     vector,
		"limit":      5,
		"tags":       tags,
	}
	payload, _ := json.Marshal(op)

	_, err := w.qOpsProd.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
	})
	if err != nil {
		return nil, err
	}

	select {
	case res := <-resChan:
		return res, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(30 * time.Second):
		return nil, fmt.Errorf("qdrant search timed out")
	}
}

func (w *Worker) handleMessage(ctx context.Context, msg pulsar.Message, consumer pulsar.Consumer) {
	defer consumer.Ack(msg)

	tracer := otel.Tracer("rag-worker")
	ctx, span := tracer.Start(ctx, "handleMessage")
	defer span.End()

	var data map[string]interface{}
	if err := json.Unmarshal(msg.Payload(), &data); err != nil {
		log.Printf("Error unmarshaling payload: %v", err)
		return
	}

	correlationID, _ := data["id"].(string)
	sessionID, _ := data["session_id"].(string)

	// Extract prompt from payload.messages
	var prompt string
	if payload, ok := data["payload"].(map[string]interface{}); ok {
		if messages, ok := payload["messages"].([]interface{}); ok && len(messages) > 0 {
			if lastMsg, ok := messages[len(messages)-1].(map[string]interface{}); ok {
				prompt, _ = lastMsg["content"].(string)
			}
		}
	}

	if prompt == "" {
		log.Printf("[%s] Error: No prompt found in message", correlationID)
		w.sendError(ctx, correlationID, "No prompt found in message")
		return
	}

	collection := "codebase" // Default collection

	log.Printf("[%s] (Session: %s) Processing request: %s", correlationID, sessionID, prompt)

	// Fetch tags for this session
	var tags []string
	if w.db != nil && sessionID != "" {
		rows, err := w.db.Query("SELECT t.tag_name FROM tag t JOIN session_tag st ON t.tag_id = st.tag_id WHERE st.session_id = $1", sessionID)
		if err == nil {
			for rows.Next() {
				var tag string
				if err := rows.Scan(&tag); err == nil {
					tags = append(tags, tag)
				}
			}
			rows.Close()
		}
		log.Printf("[%s] Active tags for session: %v", correlationID, tags)
	}

	// 1. Get Embeddings for the prompt
	log.Printf("[%s] Getting embeddings from Ollama...", correlationID)
	vector, err := w.ollama.GetEmbeddings(prompt) // Should probably pass ctx to GetEmbeddings too
	if err != nil {
		log.Printf("[%s] Error getting embeddings: %v", correlationID, err)
		w.sendError(ctx, correlationID, fmt.Sprintf("Error getting embeddings: %v", err))
		return
	}
	log.Printf("[%s] Got embeddings (size: %d)", correlationID, len(vector))

	// 2. Search Qdrant for context via Pulsar
	log.Printf("[%s] Searching Qdrant context via Pulsar...", correlationID)
	contexts, err := w.searchQdrant(ctx, collection, vector, tags)
	if err != nil {
		log.Printf("[%s] Error searching Qdrant: %v", correlationID, err)
		// Fallback to no context or send error? Let's fallback with warning
	}
	log.Printf("[%s] Found %d context snippets", correlationID, len(contexts))

	// 3. Construct Augmented Prompt
	augmentedPrompt := "Context information is below.\n---------------------\n"
	augmentedPrompt += strings.Join(contexts, "\n\n")
	augmentedPrompt += "\n---------------------\nGiven the context information and not prior knowledge, answer the query.\n"
	augmentedPrompt += "Query: " + prompt + "\nAnswer: "

	messages := []map[string]string{
		{"role": "user", "content": augmentedPrompt},
	}

	// 4. Call Ollama
	log.Printf("[%s] Calling Ollama for chat completion...", correlationID)
	result, err := w.ollama.Chat(messages) // Should probably pass ctx to Chat too
	if err != nil {
		log.Printf("[%s] Error calling Ollama: %v", correlationID, err)
		w.sendError(ctx, correlationID, fmt.Sprintf("Error calling Ollama: %v", err))
		return
	}
	log.Printf("[%s] Got response from Ollama (%d chars)", correlationID, len(result))

	// 5. Send Result back to Pulsar
	w.sendResult(ctx, correlationID, sessionID, result)
}

func (w *Worker) sendResult(ctx context.Context, id, sessionID, result string) {
	payload, _ := json.Marshal(map[string]interface{}{
		"id":              id,
		"session_id":      sessionID,
		"result":          result,
		"sequence_number": 1, // Simplified for now, can be incremented if we support streaming/multiple chunks
		"model":           w.cfg.OllamaModel,
	})

	msg := &pulsar.ProducerMessage{
		Payload: payload,
	}
	// Inject tracing context
	if msg.Properties == nil {
		msg.Properties = make(map[string]string)
	}
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(msg.Properties))

	w.producer.Send(ctx, msg)
	log.Printf("[%s] Result sent", id)
}

func (w *Worker) sendError(ctx context.Context, id, errMsg string) {
	payload, _ := json.Marshal(map[string]string{
		"id":    id,
		"error": errMsg,
	})
	w.producer.Send(ctx, &pulsar.ProducerMessage{
		Payload: payload,
	})
}
