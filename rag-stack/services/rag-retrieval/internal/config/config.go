package config

import (
	"strings"
	"time"

	"app-builds/common/envutil"
	"app-builds/common/tlsutil"
)

// EmbedTransport selects how a query is turned into a vector.
type EmbedTransport string

const (
	// TransportOllama calls a node-local Ollama pod directly. Lowest floor, and
	// the only path that existed before embed-gateway grew an HTTP route.
	TransportOllama EmbedTransport = "ollama"
	// TransportGateway calls embed-gateway's synchronous /embed route, reusing
	// its node-local discovery and fallback.
	TransportGateway EmbedTransport = "gateway"
)

type Config struct {
	ListenAddr string
	TLSCert    string
	TLSKey     string

	// Upstreams
	QdrantURL          string
	OllamaEmbedURL     string
	EmbedGatewayURL    string
	DBAdapterURL       string
	MemoryControllerURL string

	// Embedding
	EmbedTransport EmbedTransport
	EmbeddingModel string
	VectorSize     int

	// Retrieval defaults
	Collection      string
	DefaultTopK     int
	PlannerTopK     int
	ExecutorTopK    int
	MaxTopK         int
	DefaultMaxTokens int

	// Tag profile weighting (§10.5 convention). Comma-separated tag names.
	PlannerTags  []string
	ExecutorTags []string

	// Limits and timeouts
	MaxBodyBytes   int64
	EmbedTimeout   time.Duration
	SearchTimeout  time.Duration
	MemoryTimeout  time.Duration
	TagCacheTTL    time.Duration

	// Pulsar (ingest/turn)
	PulsarURL        string
	IngestTurnTopic  string
	IngestEnabled    bool
}

func Load() *Config {
	insecure := tlsutil.IsInsecureAllowed()

	qdrantDefault := "https://qdrant.rag-system.svc.cluster.local:6333"
	dbDefault := "https://db-adapter.rag-system.svc.cluster.local:443"
	memDefault := "https://memory-controller.rag-system.svc.cluster.local:443"
	pulsarDefault := "pulsar+ssl://pulsar-proxy.apache-pulsar.svc.cluster.local:6651"
	if insecure {
		qdrantDefault = "http://qdrant.rag-system.svc.cluster.local:6333"
		dbDefault = "http://db-adapter.rag-system.svc.cluster.local:443"
		memDefault = "http://memory-controller.rag-system.svc.cluster.local:443"
		pulsarDefault = "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650"
	}

	return &Config{
		ListenAddr: envutil.GetEnv("LISTEN_ADDR", ":8080"),
		TLSCert:    envutil.GetEnv("TLS_CERT", ""),
		TLSKey:     envutil.GetEnv("TLS_KEY", ""),

		QdrantURL: envutil.GetEnv("QDRANT_URL", qdrantDefault),
		// embed-gateway has no TLS today and its probes are plain HTTP, so this
		// default is http:// regardless of the insecure flag.
		OllamaEmbedURL:      envutil.GetEnv("OLLAMA_EMBED_URL", "http://ollama-embed.llms-ollama.svc.cluster.local:11434"),
		EmbedGatewayURL:     envutil.GetEnv("EMBED_GATEWAY_URL", "http://embed-gateway.rag-system.svc.cluster.local:8080"),
		DBAdapterURL:        envutil.GetEnv("DB_ADAPTER_URL", dbDefault),
		MemoryControllerURL: envutil.GetEnv("MEMORY_CONTROLLER_URL", memDefault),

		EmbedTransport: parseTransport(envutil.GetEnv("EMBED_TRANSPORT", string(TransportOllama))),
		// MUST match the model the corpus was ingested with: the collection name
		// encodes model and dims (contracts.BuildEmbeddingCollection), so a
		// mismatch searches a collection that does not exist and silently
		// returns nothing. See OPERATIONS.md.
		EmbeddingModel: envutil.GetEnv("EMBEDDING_MODEL", "all-minilm:l6-v2"),
		VectorSize:     envutil.GetEnvInt("VECTOR_SIZE", 0),

		Collection:       envutil.GetEnv("QDRANT_COLLECTION", "vectors"),
		DefaultTopK:      envutil.GetEnvInt("RAG_DEFAULT_TOP_K", 6),
		PlannerTopK:      envutil.GetEnvInt("RAG_PLANNER_TOP_K", 10),
		ExecutorTopK:     envutil.GetEnvInt("RAG_EXECUTOR_TOP_K", 4),
		MaxTopK:          envutil.GetEnvInt("RAG_MAX_TOP_K", 50),
		DefaultMaxTokens: envutil.GetEnvInt("RAG_INJECT_MAX_TOKENS", 4096),

		PlannerTags:  splitTags(envutil.GetEnv("RAG_PLANNER_TAGS", "stack-docs")),
		ExecutorTags: splitTags(envutil.GetEnv("RAG_EXECUTOR_TAGS", "stack-go")),

		// 32 MiB, not the 1 MiB that bites llm-gateway (spec §A.7).
		MaxBodyBytes:  int64(envutil.GetEnvInt("RAG_MAX_BODY_BYTES", 32<<20)),
		EmbedTimeout:  envutil.GetEnvDuration("EMBED_TIMEOUT", 10*time.Second),
		SearchTimeout: envutil.GetEnvDuration("SEARCH_TIMEOUT", 10*time.Second),
		MemoryTimeout: envutil.GetEnvDuration("MEMORY_TIMEOUT", 5*time.Second),
		TagCacheTTL:   envutil.GetEnvDuration("TAG_CACHE_TTL", 60*time.Second),

		PulsarURL:       envutil.GetEnv("PULSAR_URL", pulsarDefault),
		IngestTurnTopic: envutil.GetEnv("PULSAR_INGEST_TURN_TOPIC", "persistent://rag-pipeline/data/agent-turns"),
		IngestEnabled:   envutil.GetEnvBool("RAG_INGEST_ENABLED", true),
	}
}

func parseTransport(v string) EmbedTransport {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case string(TransportGateway):
		return TransportGateway
	default:
		return TransportOllama
	}
}

func splitTags(v string) []string {
	parts := strings.Split(v, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if t := strings.TrimSpace(p); t != "" {
			out = append(out, t)
		}
	}
	return out
}
