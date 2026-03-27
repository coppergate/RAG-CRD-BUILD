package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"app-builds/common/ent"
	"app-builds/common/telemetry"
	"app-builds/memory-controller/internal/config"
	_ "github.com/lib/pq"
)

func main() {
	cfg := config.Load()

	shutdown, err := telemetry.InitTracer("memory-controller")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	entClient, err := ent.Open("postgres", cfg.DBConnString)
	if err != nil {
		log.Fatalf("Failed to connect to DB: %v", err)
	}
	defer entClient.Close()

	mux := http.NewServeMux()
	
	mux.HandleFunc("/api/memory/items", func(w http.ResponseWriter, r *http.Request) {
		// Mock implementation for now, should query db-adapter or use entClient
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`[]`))
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	server := &http.Server{
		Addr:    cfg.ListenAddr,
		Handler: mux,
	}

	go func() {
		log.Printf("Starting Memory Controller on %s", cfg.ListenAddr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Listen error: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	log.Println("Shutting down memory-controller...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	server.Shutdown(ctx)
}
