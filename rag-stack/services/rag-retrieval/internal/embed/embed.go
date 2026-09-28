// Package embed turns a query string into a vector.
//
// Two transports exist deliberately. embed-gateway is Pulsar-only in its
// original form, so the direct-Ollama path was the only synchronous option; the
// gateway path reuses embed-gateway's node-local discovery and fallback. Spec
// §7.3 makes the choice between them a measurement (M2/M3) rather than an
// assumption, so both ship behind EMBED_TRANSPORT.
package embed

import (
	"context"
	"fmt"

	"app-builds/rag-retrieval/internal/config"
)

// Client embeds a single piece of text.
type Client interface {
	// Embed returns the vector for text. model may be empty, in which case the
	// implementation's configured default is used.
	Embed(ctx context.Context, text, model string) ([]float32, error)
	// Transport names the backend, for logging and the X-RAG-* response headers.
	Transport() string
}

// New selects a transport from configuration.
func New(cfg *config.Config) (Client, error) {
	switch cfg.EmbedTransport {
	case config.TransportGateway:
		return NewGatewayClient(cfg)
	case config.TransportOllama:
		return NewOllamaClient(cfg)
	default:
		return nil, fmt.Errorf("unknown embed transport %q", cfg.EmbedTransport)
	}
}
