package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"

	"github.com/apache/pulsar-client-go/pulsar"

	"app-builds/common/health"
	"app-builds/common/logging"
	"app-builds/embed-gateway/internal/config"
	"app-builds/embed-gateway/internal/discovery"
	"app-builds/embed-gateway/internal/gateway"
)

func main() {
	cfg := config.LoadConfig()

	healthSrv := health.NewServer()

	// The HTTP surface is served from our own mux rather than health.Server's,
	// because it now carries the synchronous /embed route alongside the probes.
	// The route is registered before the Gateway exists so that /healthz and
	// /readyz stay available during Pulsar init, exactly as they did when
	// healthSrv.Start was called here; /embed answers 503 until Run is reached.
	var ready atomic.Pointer[gateway.Gateway]
	mux := http.NewServeMux()
	healthSrv.RegisterRoutes(mux)
	mux.HandleFunc("/embed", func(w http.ResponseWriter, r *http.Request) {
		gw := ready.Load()
		if gw == nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"error":"embed-gateway is still starting"}`))
			return
		}
		gw.HandleEmbed(w, r)
	})
	startHTTP(cfg, mux)

	pulsarCli := initPulsar(cfg)
	defer pulsarCli.Close()

	consumer := subscribeToJobsTopic(cfg, pulsarCli)
	defer consumer.Close()

	healthSrv.RegisterCheck("pulsar", func() error {
		// Pulsar client has no Ping; consumer being open is sufficient.
		return nil
	})

	var discover *discovery.NodeLocalURLs
	if cfg.NodeName != "" {
		var err error
		discover, err = discovery.NewNodeLocalURLs(cfg.NodeName, cfg.OllamaNamespace, cfg.OllamaFallbackURL)
		if err != nil {
			logging.Printf("[%s] k8s node-local discovery unavailable (%v) — will use fallback URL only", cfg.GatewayID, err)
			discover = nil
		} else {
			discover.Refresh()
		}
	} else {
		logging.Printf("[%s] NODE_NAME not set — node-local embed discovery disabled; using fallback URL", cfg.GatewayID)
	}

	// If discovery is unavailable, synthesize a no-op discoverer that always returns the fallback.
	if discover == nil {
		discover = newFallbackDiscoverer(cfg.OllamaFallbackURL)
	}

	gw := gateway.New(cfg, pulsarCli, consumer, discover)
	defer gw.Close()
	ready.Store(gw)

	ctx, cancel := context.WithCancel(context.Background())
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		logging.Printf("[%s] shutdown signal received", cfg.GatewayID)
		cancel()
	}()

	gw.Run(ctx)
	logging.Printf("[%s] embed-gateway shutdown complete", cfg.GatewayID)
}

// startHTTP serves the probe and /embed routes in the background, mirroring
// health.Server.Start/StartTLS's TLS selection.
func startHTTP(cfg *config.Config, mux *http.ServeMux) {
	server := &http.Server{Addr: ":8080", Handler: mux}
	go func() {
		var err error
		if cfg.TLSCert != "" && cfg.TLSKey != "" {
			logging.Printf("[%s] starting HTTPS server on :8080 (probes + /embed)", cfg.GatewayID)
			err = server.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey)
		} else {
			logging.Printf("[%s] starting HTTP server on :8080 (probes + /embed)", cfg.GatewayID)
			err = server.ListenAndServe()
		}
		if err != nil && err != http.ErrServerClosed {
			logging.Printf("[%s] http server stopped: %v", cfg.GatewayID, err)
		}
	}()
}

func initPulsar(cfg *config.Config) pulsar.Client {
	opts := pulsar.ClientOptions{
		URL: cfg.PulsarURL,
	}
	client, err := pulsar.NewClient(opts)
	if err != nil {
		logging.Printf("[%s] FATAL: could not create Pulsar client: %v", cfg.GatewayID, err)
		os.Exit(1)
	}
	return client
}

func subscribeToJobsTopic(cfg *config.Config, client pulsar.Client) pulsar.Consumer {
	consumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            cfg.EmbedJobsTopic,
		SubscriptionName: cfg.EmbedSubscription,
		Type:             pulsar.Shared,
	})
	if err != nil {
		logging.Printf("[%s] FATAL: could not subscribe to %s: %v", cfg.GatewayID, cfg.EmbedJobsTopic, err)
		os.Exit(1)
	}
	return consumer
}

// newFallbackDiscoverer returns a NodeLocalURLs configured with only the fallback URL.
// Used when NODE_NAME is not set or in-cluster config is unavailable.
func newFallbackDiscoverer(fallbackURL string) *discovery.NodeLocalURLs {
	d := discovery.NewFallback(fallbackURL)
	return d
}
