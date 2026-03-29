package config

import (
	"time"

	"app-builds/common/envutil"
	"app-builds/common/tlsutil"
)

type Config struct {
	PulsarURL          string
	PulsarIngressTopic string
	PulsarPlanTopic    string
	PulsarExecTopic    string
	PulsarStatusTopic  string
	PulsarResultsTopic string
	PulsarSubscription string
	QdrantHost         string
	QdrantPort         string
	PlannerURL         string
	PlannerModel       string
	PlannerPromptType  string
	ExecutorURL        string
	ExecutorModel      string
	ExecutorPromptType string
	QdrantOpsTopic     string
	QdrantResultsTopic string

	// Configurable values (previously hardcoded)
	QdrantCollection   string
	QdrantSearchLimit  int
	QdrantSearchTimeout time.Duration
	RecursionBudget    float64
	ShutdownTimeout    time.Duration

	TLSCert            string
	TLSKey             string
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
		PulsarURL:          envutil.GetEnv("PULSAR_URL", pulsarDefault),
		PulsarIngressTopic: envutil.GetEnv("PULSAR_INGRESS_TOPIC", "persistent://rag-pipeline/stage/ingress"),
		PulsarPlanTopic:    envutil.GetEnv("PULSAR_PLAN_TOPIC", "persistent://rag-pipeline/stage/plan"),
		PulsarExecTopic:    envutil.GetEnv("PULSAR_EXEC_TOPIC", "persistent://rag-pipeline/stage/exec"),
		PulsarStatusTopic:  envutil.GetEnv("PULSAR_STATUS_TOPIC", "persistent://rag-pipeline/stage/status"),
		PulsarResultsTopic: envutil.GetEnv("PULSAR_RESULTS_TOPIC", "persistent://rag-pipeline/stage/results"),
		PulsarSubscription: envutil.GetEnv("PULSAR_SUBSCRIPTION", "rag-worker-sub"),
		QdrantHost:         envutil.GetEnv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local"),
		QdrantPort:         envutil.GetEnv("QDRANT_PORT", "6333"),
		PlannerURL:         envutil.GetEnv("PLANNER_URL", plannerDefault),
		PlannerModel:       envutil.GetEnv("PLANNER_MODEL", "llama3.1"),
		PlannerPromptType:  envutil.GetEnv("PLANNER_PROMPT_TYPE", "llama3"),
		ExecutorURL:        envutil.GetEnv("EXECUTOR_URL", executorDefault),
		ExecutorModel:      envutil.GetEnv("EXECUTOR_MODEL", "granite3.1-dense:8b"),
		ExecutorPromptType: envutil.GetEnv("EXECUTOR_PROMPT_TYPE", "granite31"),
		QdrantOpsTopic:     envutil.GetEnv("PULSAR_QDRANT_OPS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops"),
		QdrantResultsTopic: envutil.GetEnv("PULSAR_QDRANT_RESULTS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops-results"),

		QdrantCollection:    envutil.GetEnv("QDRANT_COLLECTION", "vectors"),
		QdrantSearchLimit:   envutil.GetEnvInt("QDRANT_SEARCH_LIMIT", 5),
		QdrantSearchTimeout: envutil.GetEnvDuration("QDRANT_SEARCH_TIMEOUT", 30*time.Second),
		RecursionBudget:     envutil.GetEnvFloat("RECURSION_BUDGET", 2.0),
		ShutdownTimeout:     envutil.GetEnvDuration("SHUTDOWN_TIMEOUT", 30*time.Second),

		TLSCert:             envutil.GetEnv("TLS_CERT", ""),
		TLSKey:              envutil.GetEnv("TLS_KEY", ""),
	}
}
