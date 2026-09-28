// Command retrieval serves the synchronous RAG retrieval API that backs
// opencode's rag_search tool and the plugin's context injection.
//
// It is deliberately separate from llm-gateway: that service's Pulsar
// round-trip, single-prompt contract and int64 session identity are all wrong
// for this shape, and sharing a process would only couple them (spec §6).
package main

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"app-builds/common/health"
	"app-builds/common/logging"
	pulsarCommon "app-builds/common/pulsar"
	"app-builds/common/telemetry"
	"app-builds/rag-retrieval/internal/config"
	"app-builds/rag-retrieval/internal/embed"
	"app-builds/rag-retrieval/internal/handlers"
	"app-builds/rag-retrieval/internal/memory"
	"app-builds/rag-retrieval/internal/qdrant"
	"app-builds/rag-retrieval/internal/session"
	"app-builds/rag-retrieval/internal/tags"
)

func main() {
	cfg := config.Load()

	shutdown, err := telemetry.InitTracer("rag-retrieval")
	if err != nil {
		logging.Warn("failed to initialize tracer", "error", err)
	} else {
		defer shutdown(context.Background())
	}

	embedder, err := embed.New(cfg)
	if err != nil {
		logging.Fatalf("failed to create embed client: %v", err)
	}

	qdrantClient, err := qdrant.NewClient(cfg.QdrantURL, cfg.SearchTimeout)
	if err != nil {
		logging.Fatalf("failed to create qdrant client: %v", err)
	}

	tagResolver, err := tags.NewResolver(cfg.DBAdapterURL, cfg.TagCacheTTL, cfg.MemoryTimeout)
	if err != nil {
		logging.Fatalf("failed to create tag resolver: %v", err)
	}

	memClient, err := memory.NewClient(cfg.MemoryControllerURL, cfg.MemoryTimeout)
	if err != nil {
		logging.Fatalf("failed to create memory client: %v", err)
	}

	sessionMapper, err := session.NewMapper(cfg.DBAdapterURL, cfg.MemoryTimeout)
	if err != nil {
		logging.Fatalf("failed to create session mapper: %v", err)
	}

	var publisher handlers.Publisher
	var pulsarCloser func()
	if cfg.IngestEnabled {
		p, closer, err := newPulsarPublisher(cfg)
		if err != nil {
			// Ingest is an optional capability; retrieval is the critical path.
			// Start without it rather than refusing to serve.
			logging.Warn("turn ingest disabled: pulsar unavailable", "error", err)
		} else {
			publisher, pulsarCloser = p, closer
			defer pulsarCloser()
		}
	}

	h := &handlers.Handler{
		Cfg:       cfg,
		Embedder:  embedder,
		Qdrant:    qdrantClient,
		Tags:      tagResolver,
		Memory:    memClient,
		Sessions:  sessionMapper,
		Publisher: publisher,
	}

	healthSrv := health.NewServer()
	// Readiness gates on the two dependencies retrieval cannot work without.
	// Memory, tags and Pulsar are all degradable, so they are deliberately not
	// readiness checks — a dead memory-controller must not take retrieval out
	// of the load balancer.
	healthSrv.RegisterCheck("qdrant", func() error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return qdrantClient.Ping(ctx)
	})
	healthSrv.RegisterCheck("embedder", func() error {
		ctx, cancel := context.WithTimeout(context.Background(), cfg.EmbedTimeout)
		defer cancel()
		_, err := embedder.Embed(ctx, "readiness probe", "")
		return err
	})

	mux := http.NewServeMux()
	healthSrv.RegisterRoutes(mux)

	mux.HandleFunc("/v1/rag/retrieve", h.HandleRetrieve)
	mux.HandleFunc("/v1/rag/ingest/turn", h.HandleIngestTurn)
	mux.HandleFunc("/v1/rag/tags", h.HandleTags)

	server := &http.Server{
		Addr:    cfg.ListenAddr,
		Handler: otelhttp.NewHandler(mux, "rag-retrieval"),
		// Retrieval is a sub-second endpoint; these bound a stuck client
		// without interfering with the 800ms budget.
		ReadHeaderTimeout: 10 * time.Second,
		WriteTimeout:      60 * time.Second,
	}

	go func() {
		logging.Info("starting rag-retrieval",
			"addr", cfg.ListenAddr,
			"embed_transport", embedder.Transport(),
			"embedding_model", cfg.EmbeddingModel,
			"collection", cfg.Collection,
			"qdrant", cfg.QdrantURL,
			"ingest_enabled", cfg.IngestEnabled && publisher != nil,
			"tls", cfg.TLSCert != "" && cfg.TLSKey != "")

		var err error
		if cfg.TLSCert != "" && cfg.TLSKey != "" {
			err = server.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey)
		} else {
			err = server.ListenAndServe()
		}
		if err != nil && err != http.ErrServerClosed {
			logging.Error("listen error", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	logging.Info("shutting down rag-retrieval")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		logging.Error("shutdown error", "error", err)
	}
}

// pulsarPublisher adapts the shared Pulsar client to handlers.Publisher,
// caching one producer per topic.
type pulsarPublisher struct {
	client *pulsarCommon.Client

	// Handlers run concurrently, so producer creation has to be serialised even
	// though the configured topic is pre-created below and the lazy path is
	// effectively unreachable today.
	mu        sync.Mutex
	producers map[string]pulsar.Producer
}

func newPulsarPublisher(cfg *config.Config) (handlers.Publisher, func(), error) {
	client, err := pulsarCommon.NewClient(pulsarCommon.Config{URL: cfg.PulsarURL})
	if err != nil {
		return nil, nil, err
	}

	producer, err := client.NewProducer(cfg.IngestTurnTopic)
	if err != nil {
		client.Close()
		return nil, nil, err
	}

	p := &pulsarPublisher{
		client:    client,
		producers: map[string]pulsar.Producer{cfg.IngestTurnTopic: producer},
	}
	closer := func() {
		p.mu.Lock()
		defer p.mu.Unlock()
		for _, prod := range p.producers {
			prod.Close()
		}
		client.Close()
	}
	return p, closer, nil
}

func (p *pulsarPublisher) Publish(topic string, payload any) error {
	p.mu.Lock()
	producer, ok := p.producers[topic]
	if !ok {
		newProducer, err := p.client.NewProducer(topic)
		if err != nil {
			p.mu.Unlock()
			return err
		}
		p.producers[topic] = newProducer
		producer = newProducer
	}
	p.mu.Unlock()

	// SendJSON takes any payload; marshal-check first so a bad payload is a
	// clear error rather than a broker-side surprise.
	if _, err := json.Marshal(payload); err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_, err := pulsarCommon.SendJSON(ctx, producer, payload)
	return err
}
