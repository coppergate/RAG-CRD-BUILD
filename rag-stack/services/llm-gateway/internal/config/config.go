package config

import (
	"time"

	"app-builds/common/envutil"
	"app-builds/common/tlsutil"
)

type Config struct {
	PulsarURL       string
	RequestTopic    string
	ResponseTopic   string
	ListenAddr      string
	PulsarNamespace string
	DBConnString    string
	PromptTopic     string

	// Configurable values (previously hardcoded)
	RequestTimeout time.Duration
}

func Load() *Config {
	insecure := tlsutil.IsInsecureAllowed()

	pulsarDefault := "pulsar+ssl://pulsar-proxy.apache-pulsar.svc.cluster.local:6651"
	dbDefault := "postgres://app:app@timescaledb-rw.timescaledb.svc.cluster.local:5432/app?sslmode=require"
	if insecure {
		pulsarDefault = "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650"
		dbDefault = "postgres://app:app@timescaledb-rw.timescaledb.svc.cluster.local:5432/app?sslmode=disable"
	}

	return &Config{
		PulsarURL:       envutil.GetEnv("PULSAR_URL", pulsarDefault),
		RequestTopic:    envutil.GetEnv("PULSAR_REQUEST_TOPIC", "persistent://rag-pipeline/stage/ingress"),
		ResponseTopic:   envutil.GetEnv("PULSAR_RESPONSE_TOPIC", "persistent://rag-pipeline/stage/results"),
		ListenAddr:      envutil.GetEnv("LISTEN_ADDR", ":8080"),
		PulsarNamespace: envutil.GetEnv("PULSAR_NAMESPACE", "apache-pulsar"),
		DBConnString:    envutil.GetEnv("DB_CONN_STRING", dbDefault),
		PromptTopic:     envutil.GetEnv("PULSAR_PROMPT_TOPIC", "persistent://rag-pipeline/data/chat-prompts"),

		RequestTimeout: envutil.GetEnvDuration("REQUEST_TIMEOUT", 120*time.Second),
	}
}
