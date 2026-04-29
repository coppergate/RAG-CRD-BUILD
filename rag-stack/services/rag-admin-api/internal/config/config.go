package config

import (
	"app-builds/common/envutil"
)

type Config struct {
	ListenAddr         string
	DBAdapterURL       string
	S3ManagerURL       string
	QdrantAdapterURL   string
	LLMGatewayURL      string
	MemoryControllerURL string
	IngestionURL       string
	QdrantDirectURL    string
	GrafanaURL         string
	TLSCert            string
	TLSKey             string
}

func Load() *Config {
	return &Config{
		ListenAddr:          envutil.GetEnv("LISTEN_ADDR", ":8080"),
		DBAdapterURL:        envutil.GetEnv("DB_ADAPTER_URL", "https://db-adapter.rag-system.svc.cluster.local"),
		S3ManagerURL:        envutil.GetEnv("S3_MANAGER_URL", "https://object-store-mgr.rag-system.svc.cluster.local"),
		QdrantAdapterURL:    envutil.GetEnv("QDRANT_ADAPTER_URL", "https://qdrant-adapter.rag-system.svc.cluster.local"),
		LLMGatewayURL:       envutil.GetEnv("LLM_GATEWAY_URL", "https://llm-gateway.rag-system.svc.cluster.local"),
		MemoryControllerURL: envutil.GetEnv("MEMORY_CONTROLLER_URL", "https://memory-controller.rag-system.svc.cluster.local"),
		IngestionURL:        envutil.GetEnv("INGESTION_URL", "https://rag-ingestion-service.rag-system.svc.cluster.local"),
		QdrantDirectURL:     envutil.GetEnv("QDRANT_DIRECT_URL", "https://qdrant.rag-system.svc.cluster.local:6333"),
		GrafanaURL:          envutil.GetEnv("GRAFANA_URL", "https://grafana.rag.hierocracy.home"),
		TLSCert:             envutil.GetEnv("TLS_CERT", ""),
		TLSKey:              envutil.GetEnv("TLS_KEY", ""),
	}
}
