package handlers

import (
	"encoding/json"
	"net/http"

	"app-builds/common/logging"
	"app-builds/rag-retrieval/internal/config"
	"app-builds/rag-retrieval/internal/embed"
	"app-builds/rag-retrieval/internal/memory"
	"app-builds/rag-retrieval/internal/qdrant"
	"app-builds/rag-retrieval/internal/session"
	"app-builds/rag-retrieval/internal/tags"
)

// Publisher publishes an ingest event. Satisfied by the Pulsar producer in
// main, and by a no-op when ingest is disabled.
type Publisher interface {
	Publish(topic string, payload any) error
}

type Handler struct {
	Cfg       *config.Config
	Embedder  embed.Client
	Qdrant    *qdrant.Client
	Tags      *tags.Resolver
	Memory    *memory.Client
	Sessions  *session.Mapper
	Publisher Publisher
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		logging.Printf("[retrieval] failed to write response: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, errorBody{Error: errorDetail{Message: msg, Code: code}})
}

// firstNonEmpty picks the first populated value, used to let headers override
// body fields without either being mandatory.
func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
