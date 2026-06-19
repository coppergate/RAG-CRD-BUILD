package config

import (
	"time"

	"app-builds/common/envutil"
	"app-builds/common/tlsutil"
)

// Config holds embed-gateway runtime configuration loaded from environment variables.
type Config struct {
	PulsarURL         string
	EmbedJobsTopic    string
	EmbedSubscription string
	Workers           int

	// GatewayID is the pod name injected via the downward API (metadata.name).
	// Used as the gateway_id in result messages.
	GatewayID string

	// NodeName is the k8s node this pod is running on (spec.nodeName).
	// Used to find co-located Ollama embed pods.
	NodeName string

	OllamaNamespace   string
	OllamaFallbackURL string
	OllamaTimeout     time.Duration

	TLSCert string
	TLSKey  string
}

// LoadConfig populates Config from environment variables with sensible defaults.
func LoadConfig() *Config {
	insecure := tlsutil.IsInsecureAllowed()

	pulsarDefault := "pulsar+ssl://pulsar-proxy.apache-pulsar.svc.cluster.local:6651"
	if insecure {
		pulsarDefault = "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650"
	}

	fallbackDefault := "https://ollama-embed.llms-ollama.svc.cluster.local:11434"
	if insecure {
		fallbackDefault = "http://ollama-embed.llms-ollama.svc.cluster.local:11434"
	}

	return &Config{
		PulsarURL:         envutil.GetEnv("PULSAR_URL", pulsarDefault),
		EmbedJobsTopic:    envutil.GetEnv("EMBED_JOBS_TOPIC", "persistent://rag-pipeline/embed/jobs"),
		EmbedSubscription: envutil.GetEnv("EMBED_SUBSCRIPTION", "embed-gw-sub"),
		Workers:           envutil.GetEnvInt("EMBED_GATEWAY_WORKERS", 8),
		GatewayID:         envutil.GetEnv("EMBED_GATEWAY_ID", "embed-gateway-unknown"),
		NodeName:          envutil.GetEnv("NODE_NAME", ""),
		OllamaNamespace:   envutil.GetEnv("OLLAMA_EMBED_NAMESPACE", "llms-ollama"),
		OllamaFallbackURL: envutil.GetEnv("OLLAMA_EMBED_FALLBACK_URL", fallbackDefault),
		OllamaTimeout:     envutil.GetEnvDuration("OLLAMA_TIMEOUT", 120*time.Second),
		TLSCert:           envutil.GetEnv("TLS_CERT", ""),
		TLSKey:            envutil.GetEnv("TLS_KEY", ""),
	}
}
