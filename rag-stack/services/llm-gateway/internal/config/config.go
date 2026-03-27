package config

import (
	"os"

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
		PulsarURL:       getEnv("PULSAR_URL", pulsarDefault),
		RequestTopic:    getEnv("PULSAR_REQUEST_TOPIC", "persistent://rag-pipeline/stage/ingress"),
		ResponseTopic:   getEnv("PULSAR_RESPONSE_TOPIC", "persistent://rag-pipeline/stage/results"),
		ListenAddr:      getEnv("LISTEN_ADDR", ":8080"),
		PulsarNamespace: getEnv("PULSAR_NAMESPACE", "apache-pulsar"),
		DBConnString:    getEnv("DB_CONN_STRING", dbDefault),
		PromptTopic:     getEnv("PULSAR_PROMPT_TOPIC", "persistent://rag-pipeline/data/chat-prompts"),
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
