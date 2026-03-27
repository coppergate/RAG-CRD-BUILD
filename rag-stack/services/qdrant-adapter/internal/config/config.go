package config

import (
	"fmt"
	"os"

	"app-builds/common/tlsutil"
)

type Config struct {
	PulsarURL           string
	PulsarRequestTopic  string
	PulsarResponseTopic string
	PulsarSubscription  string
	QdrantHost          string
	QdrantPort          string
	QdrantUseTLS        bool
	DefaultVectorSize   int
	OllamaURL           string
	OllamaModel         string
	QdrantOpsTopic      string
	QdrantResultsTopic  string
}

func LoadConfig() *Config {
	insecure := tlsutil.IsInsecureAllowed()

	pulsarDefault := "pulsar+ssl://pulsar-proxy.apache-pulsar.svc.cluster.local:6651"
	ollamaDefault := "https://ollama.llms-ollama.svc.cluster.local:11434"
	qdrantTLSDefault := "true"
	if insecure {
		pulsarDefault = "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650"
		ollamaDefault = "http://ollama.llms-ollama.svc.cluster.local:11434"
		qdrantTLSDefault = "false"
	}

	return &Config{
		PulsarURL:           getEnv("PULSAR_URL", pulsarDefault),
		PulsarRequestTopic:  getEnv("PULSAR_REQUEST_TOPIC", "persistent://rag-pipeline/data/llm-tasks"),
		PulsarResponseTopic: getEnv("PULSAR_RESPONSE_TOPIC", "persistent://rag-pipeline/data/chat-responses"),
		PulsarSubscription:  getEnv("PULSAR_SUBSCRIPTION", "rag-worker-sub"),
		QdrantHost:          getEnv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local"),
		QdrantPort:          getEnv("QDRANT_PORT", "6333"),
		QdrantUseTLS:        getEnv("QDRANT_USE_TLS", qdrantTLSDefault) == "true",
		DefaultVectorSize:   getEnvInt("DEFAULT_VECTOR_SIZE", 4096),
		OllamaURL:           getEnv("OLLAMA_URL", ollamaDefault),
		OllamaModel:         getEnv("OLLAMA_MODEL", "llama3.1"),
		QdrantOpsTopic:      getEnv("PULSAR_QDRANT_OPS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops"),
		QdrantResultsTopic:  getEnv("PULSAR_QDRANT_RESULTS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops-results"),
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if value, ok := os.LookupEnv(key); ok {
		var i int
		if _, err := fmt.Sscanf(value, "%d", &i); err == nil {
			return i
		}
	}
	return fallback
}
