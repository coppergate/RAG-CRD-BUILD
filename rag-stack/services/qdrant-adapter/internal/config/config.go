package config

import (
	"app-builds/common/envutil"
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
	TLSCert             string
	TLSKey              string
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
		PulsarURL:           envutil.GetEnv("PULSAR_URL", pulsarDefault),
		PulsarRequestTopic:  envutil.GetEnv("PULSAR_REQUEST_TOPIC", "persistent://rag-pipeline/data/llm-tasks"),
		PulsarResponseTopic: envutil.GetEnv("PULSAR_RESPONSE_TOPIC", "persistent://rag-pipeline/data/chat-responses"),
		PulsarSubscription:  envutil.GetEnv("PULSAR_SUBSCRIPTION", "rag-worker-sub"),
		QdrantHost:          envutil.GetEnv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local"),
		QdrantPort:          envutil.GetEnv("QDRANT_PORT", "6333"),
		QdrantUseTLS:        envutil.GetEnv("QDRANT_USE_TLS", qdrantTLSDefault) == "true",
		DefaultVectorSize:   envutil.GetEnvInt("DEFAULT_VECTOR_SIZE", 4096),
		OllamaURL:           envutil.GetEnv("OLLAMA_URL", ollamaDefault),
		OllamaModel:         envutil.GetEnv("OLLAMA_MODEL", "llama3.1:latest"),
		QdrantOpsTopic:      envutil.GetEnv("PULSAR_QDRANT_OPS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops"),
		QdrantResultsTopic:  envutil.GetEnv("PULSAR_QDRANT_RESULTS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops-results"),
		TLSCert:             envutil.GetEnv("TLS_CERT", ""),
		TLSKey:              envutil.GetEnv("TLS_KEY", ""),
	}
}
