package config

import (
	"os"

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
	ExecutorURL        string
	ExecutorModel      string
	QdrantOpsTopic     string
	QdrantResultsTopic string
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
		PulsarURL:          getEnv("PULSAR_URL", pulsarDefault),
		PulsarIngressTopic: getEnv("PULSAR_INGRESS_TOPIC", "persistent://rag-pipeline/stage/ingress"),
		PulsarPlanTopic:    getEnv("PULSAR_PLAN_TOPIC", "persistent://rag-pipeline/stage/plan"),
		PulsarExecTopic:    getEnv("PULSAR_EXEC_TOPIC", "persistent://rag-pipeline/stage/exec"),
		PulsarStatusTopic:  getEnv("PULSAR_STATUS_TOPIC", "persistent://rag-pipeline/stage/status"),
		PulsarResultsTopic: getEnv("PULSAR_RESULTS_TOPIC", "persistent://rag-pipeline/stage/results"),
		PulsarSubscription: getEnv("PULSAR_SUBSCRIPTION", "rag-worker-sub"),
		QdrantHost:         getEnv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local"),
		QdrantPort:         getEnv("QDRANT_PORT", "6333"),
		PlannerURL:         getEnv("PLANNER_URL", plannerDefault),
		PlannerModel:       getEnv("PLANNER_MODEL", "llama3.1"),
		ExecutorURL:        getEnv("EXECUTOR_URL", executorDefault),
		ExecutorModel:      getEnv("EXECUTOR_MODEL", "granite3.1-dense:8b"),
		QdrantOpsTopic:     getEnv("PULSAR_QDRANT_OPS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops"),
		QdrantResultsTopic: getEnv("PULSAR_QDRANT_RESULTS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops-results"),
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
