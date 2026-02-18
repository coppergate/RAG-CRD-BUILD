package config

import (
	"os"
)

type Config struct {
	PulsarURL      string
	PromptTopic    string
	ResponseTopic  string
	DBConnString   string
	Subscription   string
	DBOpsTopic     string
}

func Load() *Config {
	return &Config{
		PulsarURL:     getEnv("PULSAR_URL", "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650"),
		PromptTopic:   getEnv("PULSAR_PROMPT_TOPIC", "persistent://rag-pipeline/data/chat-prompts"),
		ResponseTopic: getEnv("PULSAR_RESPONSE_TOPIC", "persistent://rag-pipeline/data/chat-responses"),
		DBConnString:  getEnv("DB_CONN_STRING", "postgres://app:app@timescaledb-rw.timescaledb.svc.cluster.local:5432/app?sslmode=disable"),
		Subscription:  getEnv("PULSAR_SUBSCRIPTION", "db-adapter-sub"),
		DBOpsTopic:    getEnv("PULSAR_DB_OPS_TOPIC", "persistent://rag-pipeline/operations/db-ops"),
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
