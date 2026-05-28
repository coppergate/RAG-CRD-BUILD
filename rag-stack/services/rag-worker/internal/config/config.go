package config

import (
	"time"

	"app-builds/common/envutil"
	"app-builds/common/tlsutil"
)

type Config struct {
	PulsarURL             string
	PulsarIngressTopic    string
	PulsarPlanTopic       string
	PulsarExecTopic       string
	PulsarSearchTopic     string
	PulsarStatusTopic     string
	PulsarResultsTopic    string
	PulsarCompletionTopic string
	PulsarSubscription    string
	QdrantHost            string
	QdrantPort            string
	PlannerURL            string
	PlannerModel          string
	PlannerPromptType     string
	ExecutorURL           string
	ExecutorModel         string
	ExecutorPromptType    string
	EmbeddingModel        string
	QdrantOpsTopic        string
	QdrantResultsTopic    string

	// Configurable values (previously hardcoded)
	QdrantCollection      string
	QdrantSearchLimit     int
	QdrantRetrievalLimit  int
	ChunkVectorLimit      int
	QdrantSearchTimeout   time.Duration
	RecursionBudget       float64
	MaxRecursionCount     int
	MaxTotalChunks        int
	MaxChunksPerRecursion int
	ShutdownTimeout       time.Duration
	StreamIntermediate    bool

	StreamAccumulationCount int

	MemoryControllerURL string
	QdrantAdapterURL    string
	IngestionURL        string
	DBAdapterURL        string

	TLSCert string
	TLSKey  string
}

func LoadConfig() *Config {
	insecure := tlsutil.IsInsecureAllowed()

	pulsarDefault := "pulsar+ssl://pulsar-proxy.apache-pulsar.svc.cluster.local:6651"
	plannerDefault := "https://ollama.llms-ollama.svc.cluster.local:11434"
	executorDefault := "https://ollama-code.llms-ollama.svc.cluster.local:11434"
	if insecure {
		pulsarDefault = "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650"
		plannerDefault = "http://ollama.llms-ollama.svc.cluster.local:11434"
		executorDefault = "http://ollama-code.llms-ollama.svc.cluster.local:11434"
	}

	return &Config{
		PulsarURL:             envutil.GetEnv("PULSAR_URL", pulsarDefault),
		PulsarIngressTopic:    envutil.GetEnv("PULSAR_INGRESS_TOPIC", "persistent://rag-pipeline/stage/ingress"),
		PulsarPlanTopic:       envutil.GetEnv("PULSAR_PLAN_TOPIC", "persistent://rag-pipeline/stage/plan"),
		PulsarExecTopic:       envutil.GetEnv("PULSAR_EXEC_TOPIC", "persistent://rag-pipeline/stage/exec"),
		PulsarSearchTopic:     envutil.GetEnv("PULSAR_SEARCH_TOPIC", "persistent://rag-pipeline/stage/search"),
		PulsarStatusTopic:     envutil.GetEnv("PULSAR_STATUS_TOPIC", "persistent://rag-pipeline/stage/status"),
		PulsarResultsTopic:    envutil.GetEnv("PULSAR_RESULTS_TOPIC", "persistent://rag-pipeline/stage/results"),
		PulsarCompletionTopic: envutil.GetEnv("PULSAR_COMPLETION_TOPIC", "persistent://rag-pipeline/stage/completion"),
		PulsarSubscription:    envutil.GetEnv("PULSAR_SUBSCRIPTION", "rag-worker-sub"),
		QdrantHost:            envutil.GetEnv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local"),
		QdrantPort:            envutil.GetEnv("QDRANT_PORT", "6333"),
		PlannerURL:            envutil.GetEnv("PLANNER_URL", plannerDefault),
		PlannerModel:          envutil.GetEnv("PLANNER_MODEL", "llama3.1:latest"),
		PlannerPromptType:     envutil.GetEnv("PLANNER_PROMPT_TYPE", "llama3"),
		ExecutorURL:           envutil.GetEnv("EXECUTOR_URL", executorDefault),
		ExecutorModel:         envutil.GetEnv("EXECUTOR_MODEL", "granite3.1-dense:8b"),
		ExecutorPromptType:    envutil.GetEnv("EXECUTOR_PROMPT_TYPE", "granite31"),
		EmbeddingModel:        envutil.GetEnv("EMBEDDING_MODEL", "llama3.1:latest"),
		QdrantOpsTopic:        envutil.GetEnv("PULSAR_QDRANT_OPS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops"),
		QdrantResultsTopic:    envutil.GetEnv("PULSAR_QDRANT_RESULTS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops-results"),

		QdrantCollection:        envutil.GetEnv("QDRANT_COLLECTION", "vectors"),
		QdrantSearchLimit:       envutil.GetEnvInt("QDRANT_SEARCH_LIMIT", 50),
		QdrantRetrievalLimit:    envutil.GetEnvInt("QDRANT_RETRIEVAL_LIMIT", 10000),
		ChunkVectorLimit:        envutil.GetEnvInt("CHUNK_VECTOR_LIMIT", 50),
		QdrantSearchTimeout:     envutil.GetEnvDuration("QDRANT_SEARCH_TIMEOUT", 30*time.Second),
		RecursionBudget:         envutil.GetEnvFloat("RECURSION_BUDGET", 2.0),
		MaxRecursionCount:       envutil.GetEnvInt("MAX_RECURSION_COUNT", 3),
		MaxTotalChunks:          envutil.GetEnvInt("MAX_TOTAL_CHUNKS", 100),
		MaxChunksPerRecursion:   envutil.GetEnvInt("MAX_CHUNKS_PER_RECURSION", 10),
		ShutdownTimeout:         envutil.GetEnvDuration("SHUTDOWN_TIMEOUT", 30*time.Second),
		StreamAccumulationCount: envutil.GetEnvInt("STREAM_ACCUMULATION_COUNT", 10),
		StreamIntermediate:      envutil.GetEnvBool("STREAM_INTERMEDIATE", true),

		MemoryControllerURL: envutil.GetEnv("MEMORY_CONTROLLER_URL", "https://memory-controller.rag-system.svc.cluster.local"),
		QdrantAdapterURL:    envutil.GetEnv("QDRANT_ADAPTER_URL", "https://qdrant-adapter.rag-system.svc.cluster.local:8082"),
		IngestionURL:        envutil.GetEnv("RAG_INGESTION_URL", "https://rag-ingestion.rag-system.svc.cluster.local"),
		DBAdapterURL:        envutil.GetEnv("DB_ADAPTER_URL", "https://db-adapter.rag-system.svc.cluster.local"),

		TLSCert: envutil.GetEnv("TLS_CERT", ""),
		TLSKey:  envutil.GetEnv("TLS_KEY", ""),
	}
}
