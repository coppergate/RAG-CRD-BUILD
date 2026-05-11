package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"

	"app-builds/common/ent"
	"app-builds/common/health"
	"app-builds/common/telemetry"
	"app-builds/memory-controller/internal/config"
	"app-builds/memory-controller/internal/handlers"
	_ "github.com/lib/pq"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
	cfg := config.Load()
	healthSrv := health.NewServer()

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

	healthSrv.RegisterCheck("database", func() error {
		// Verify DB connectivity
		_, err := entClient.Session.Query().Limit(1).Count(context.Background())
		return err
	})

	mux := http.NewServeMux()
	
	healthSrv.RegisterRoutes(mux)
	mux.Handle("/metrics", promhttp.Handler())
	
	memoryHandler := handlers.NewMemoryHandler(entClient)
	mux.HandleFunc("/items", memoryHandler.HandleItems)
	mux.HandleFunc("/retrieve", memoryHandler.HandleRetrieve)
	mux.HandleFunc("/sessions", memoryHandler.HandleSessions)
	mux.HandleFunc("/sessions/", memoryHandler.HandleSessions)

	// Behavioral Rule Management (Iteration 9)
	behavioralHandler := handlers.NewBehavioralHandler(entClient)
	mux.HandleFunc("/behavior/rules", behavioralHandler.HandleRules)
	mux.HandleFunc("/behavior/rules/", behavioralHandler.HandleRules)
	mux.HandleFunc("/behavior/identifiers", behavioralHandler.HandleIdentifiers)
	mux.HandleFunc("/behavior/audit", behavioralHandler.HandleAudit)
	mux.HandleFunc("/behavior/learn", behavioralHandler.HandleLearn)
	mux.HandleFunc("/behavior/session/override", behavioralHandler.HandleSessionOverride)
	mux.HandleFunc("/behavior/session/reset", behavioralHandler.HandleResetSession)

	otelHandler := otelhttp.NewHandler(mux, "memory-controller")

	server := &http.Server{
		Addr:    cfg.ListenAddr,
		Handler: otelHandler,
	}

	go func() {
		if cfg.TLSCert != "" && cfg.TLSKey != "" {
			log.Printf("Starting Memory Controller with TLS on %s", cfg.ListenAddr)
			if err := server.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey); err != nil && err != http.ErrServerClosed {
				log.Fatalf("Listen error: %v", err)
			}
		} else {
			log.Printf("Starting Memory Controller on %s", cfg.ListenAddr)
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Fatalf("Listen error: %v", err)
			}
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
