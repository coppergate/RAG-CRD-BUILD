package config

import (
	"app-builds/common/envutil"
	"app-builds/common/tlsutil"
)

type Config struct {
	PulsarURL     string
	PromptTopic   string
	ResponseTopic string
	DBConnString  string
	Subscription    string
	DBOpsTopic      string
	QdrantOpsTopic  string
	TLSCert         string
	TLSKey        string
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
		PulsarURL:     envutil.GetEnv("PULSAR_URL", pulsarDefault),
		PromptTopic:   envutil.GetEnv("PULSAR_PROMPT_TOPIC", "persistent://rag-pipeline/data/chat-prompts"),
		ResponseTopic: envutil.GetEnv("PULSAR_RESPONSE_TOPIC", "persistent://rag-pipeline/data/chat-responses"),
		DBConnString:  envutil.GetEnv("DB_CONN_STRING", dbDefault),
		Subscription:    envutil.GetEnv("PULSAR_SUBSCRIPTION", "db-adapter-sub"),
		DBOpsTopic:      envutil.GetEnv("PULSAR_DB_OPS_TOPIC", "persistent://rag-pipeline/operations/db-ops"),
		QdrantOpsTopic:  envutil.GetEnv("PULSAR_QDRANT_OPS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops"),
		TLSCert:         envutil.GetEnv("TLS_CERT", ""),
		TLSKey:        envutil.GetEnv("TLS_KEY", ""),
	}
}
