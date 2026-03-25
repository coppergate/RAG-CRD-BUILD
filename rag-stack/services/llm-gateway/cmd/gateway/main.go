package main

import (
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"app-builds/llm-gateway/internal/config"
	"app-builds/llm-gateway/internal/handlers"
	"app-builds/llm-gateway/internal/pulsar"
	"app-builds/common/ent"
	"app-builds/common/telemetry"
	"context"
	_ "github.com/lib/pq"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
	cfg := config.Load()

	shutdown, err := telemetry.InitTracer("llm-gateway")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	log.Printf("Starting LLM Gateway on %s", cfg.ListenAddr)
	log.Printf("Pulsar URL: %s", cfg.PulsarURL)
	log.Printf("Request Topic: %s", cfg.RequestTopic)

	entClient, err := ent.Open("postgres", cfg.DBConnString)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer entClient.Close()

	pc, err := pulsar.NewPulsarClient(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize Pulsar: %v", err)
	}
	defer pc.Close()

	openAIHandler := &handlers.OpenAIHandler{
		Pulsar: pc,
		Ent:    entClient,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/chat/completions", openAIHandler.HandleChatCompletions)
	mux.HandleFunc("/v1/rag/chat", openAIHandler.HandleGenericChat)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	otelHandler := otelhttp.NewHandler(mux, "llm-gateway")

	server := &http.Server{
		Addr:    cfg.ListenAddr,
		Handler: otelHandler,
	}

	go func() {
		certFile := os.Getenv("TLS_CERT")
		keyFile := os.Getenv("TLS_KEY")
		if certFile != "" && keyFile != "" {
			log.Printf("Listening with TLS on %s", cfg.ListenAddr)
			if err := server.ListenAndServeTLS(certFile, keyFile); err != nil && err != http.ErrServerClosed {
				log.Fatalf("Listen error: %v", err)
			}
		} else {
			log.Printf("Listening without TLS on %s", cfg.ListenAddr)
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Fatalf("Listen error: %v", err)
			}
		}
	}()

	// Graceful shutdown
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	log.Println("Shutting down gateway...")
}
