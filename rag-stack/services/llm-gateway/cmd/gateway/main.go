package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"app-builds/common/ent"
	"app-builds/common/health"
	"app-builds/common/logging"
	"app-builds/common/telemetry"
	"app-builds/llm-gateway/internal/config"
	"app-builds/llm-gateway/internal/handlers"
	"app-builds/llm-gateway/internal/pulsar"
	_ "github.com/lib/pq"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
	cfg := config.Load()

	// Health server with deep readiness checks
	healthSrv := health.NewServer()

	shutdown, err := telemetry.InitTracer("llm-gateway")
	if err != nil {
		logging.Warn("failed to initialize tracer", "error", err)
	} else {
		defer shutdown(context.Background())
	}

	logging.Info("starting LLM Gateway", "addr", cfg.ListenAddr, "pulsar_url", cfg.PulsarURL, "request_topic", cfg.RequestTopic)

	entClient, err := ent.Open("postgres", cfg.DBConnString)
	if err != nil {
		logging.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer entClient.Close()

	pc, err := pulsar.NewPulsarClient(cfg)
	if err != nil {
		logging.Error("failed to initialize Pulsar", "error", err)
		os.Exit(1)
	}
	defer pc.Close()

	openAIHandler := &handlers.OpenAIHandler{
		Pulsar: pc,
		Ent:    entClient,
	}

	// Register readiness checks
	healthSrv.RegisterCheck("database", func() error {
		// Use a lightweight ent query to verify DB connectivity
		_, err := entClient.Session.Query().Limit(1).Count(context.Background())
		return err
	})

	healthSrv.RegisterCheck("pulsar", func() error {
		return pc.Ping()
	})

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/chat/completions", openAIHandler.HandleChatCompletions)
	mux.HandleFunc("/v1/rag/chat", openAIHandler.HandleGenericChat)
	mux.HandleFunc("/v1/rag/chat/stream", openAIHandler.HandleStreamingChat)
	healthSrv.RegisterRoutes(mux)

	otelHandler := otelhttp.NewHandler(mux, "llm-gateway")

	server := &http.Server{
		Addr:    cfg.ListenAddr,
		Handler: otelHandler,
	}

	go func() {
		certFile := os.Getenv("TLS_CERT")
		keyFile := os.Getenv("TLS_KEY")
		if certFile != "" && keyFile != "" {
			logging.Info("listening with TLS", "addr", cfg.ListenAddr)
			if err := server.ListenAndServeTLS(certFile, keyFile); err != nil && err != http.ErrServerClosed {
				logging.Error("listen error", "error", err)
				os.Exit(1)
			}
		} else {
			logging.Info("listening without TLS", "addr", cfg.ListenAddr)
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				logging.Error("listen error", "error", err)
				os.Exit(1)
			}
		}
	}()

	// Graceful shutdown
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	logging.Info("shutting down gateway")

	// 1. Stop accepting new HTTP requests, drain in-flight requests
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		logging.Error("HTTP server shutdown error", "error", err)
	} else {
		logging.Info("HTTP server shut down gracefully")
	}

	// 2. Close Pulsar resources (consumer, producers, client)
	pc.Close()
	logging.Info("pulsar resources closed")

	// 3. Close DB
	entClient.Close()
	logging.Info("database connection closed")

	logging.Info("gateway shutdown complete")
}
