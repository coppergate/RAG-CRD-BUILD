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
		logging.Warn("failed to initialize tracer", "error", err)
	} else {
		defer shutdown(context.Background())
	}

	entClient, err := ent.Open("postgres", cfg.DBConnString)
	if err != nil {
		logging.Error("failed to connect to DB", "error", err)
		os.Exit(1)
	}
	defer entClient.Close()

	healthSrv.RegisterCheck("database", func() error {
		// Verify DB connectivity
		_, err := entClient.Session.Query().Limit(1).Count(context.Background())
		return err
	})

	mux := http.NewServeMux()
	
	healthSrv.RegisterRoutes(mux)
	
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
			logging.Info("starting Memory Controller with TLS", "addr", cfg.ListenAddr)
			if err := server.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey); err != nil && err != http.ErrServerClosed {
				logging.Error("listen error", "error", err)
				os.Exit(1)
			}
		} else {
			logging.Info("starting Memory Controller", "addr", cfg.ListenAddr)
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				logging.Error("listen error", "error", err)
				os.Exit(1)
			}
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	logging.Info("shutting down memory-controller")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	server.Shutdown(ctx)
}
