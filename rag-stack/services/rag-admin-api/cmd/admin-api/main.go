package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"app-builds/common/health"
	"app-builds/common/telemetry"
	"app-builds/rag-admin-api/internal/config"
	"app-builds/rag-admin-api/internal/handlers"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
	cfg := config.Load()

	healthSrv := health.NewServer()

	shutdown, err := telemetry.InitTracer("rag-admin-api")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	h := &handlers.AdminHandler{Cfg: cfg}

	// Health Aggregation
	mux := http.NewServeMux()
	
	healthSrv.RegisterRoutes(mux)
	
	// S3 Object Browser Proxy
	mux.HandleFunc("/api/s3/", h.ProxyTo(cfg.S3ManagerURL, "/api/s3"))
	
	// TimescaleDB Explorer Proxy
	mux.HandleFunc("/api/db/", h.ProxyTo(cfg.DBAdapterURL, "/api/db"))
	
	// Qdrant Vector Explorer Proxy
	mux.HandleFunc("/api/qdrant/", h.ProxyTo(cfg.QdrantAdapterURL, "/api/qdrant"))
	
	// Memory Controller Proxy
	mux.HandleFunc("/api/memory/", h.ProxyTo(cfg.MemoryControllerURL, "/api/memory"))
	
	// LLM Gateway Proxy (for chat and streaming)
	mux.HandleFunc("/api/chat/", h.ProxyTo(cfg.LLMGatewayURL, "/api/chat"))
	
	// Health Aggregation
	mux.HandleFunc("/api/health/all", h.HandleHealthAggregation)

	otelHandler := otelhttp.NewHandler(mux, "rag-admin-api")

	server := &http.Server{
		Addr:    cfg.ListenAddr,
		Handler: otelHandler,
	}

	go func() {
		if cfg.TLSCert != "" && cfg.TLSKey != "" {
			log.Printf("Starting RAG Admin API with TLS on %s", cfg.ListenAddr)
			if err := server.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey); err != nil && err != http.ErrServerClosed {
				log.Fatalf("Listen error: %v", err)
			}
		} else {
			log.Printf("Starting RAG Admin API on %s", cfg.ListenAddr)
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Fatalf("Listen error: %v", err)
			}
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	log.Println("Shutting down admin-api...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	server.Shutdown(ctx)
}
