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
	TLSCert            string
	TLSKey             string
}

func Load() *Config {
	return &Config{
		ListenAddr:          envutil.GetEnv("LISTEN_ADDR", ":8080"),
		DBAdapterURL:        envutil.GetEnv("DB_ADAPTER_URL", "http://db-adapter.rag.svc.cluster.local:8080"),
		S3ManagerURL:        envutil.GetEnv("S3_MANAGER_URL", "http://object-store-mgr.rag.svc.cluster.local:8080"),
		QdrantAdapterURL:    envutil.GetEnv("QDRANT_ADAPTER_URL", "http://qdrant-adapter.rag.svc.cluster.local:8080"),
		LLMGatewayURL:       envutil.GetEnv("LLM_GATEWAY_URL", "http://llm-gateway.rag.svc.cluster.local:8080"),
		MemoryControllerURL: envutil.GetEnv("MEMORY_CONTROLLER_URL", "http://memory-controller.rag.svc.cluster.local:8080"),
		TLSCert:             envutil.GetEnv("TLS_CERT", ""),
		TLSKey:              envutil.GetEnv("TLS_KEY", ""),
	}
}
