package gateway

import (
	"encoding/json"
	"net/http"
	"time"

	"app-builds/common/logging"
)

// EmbedHTTPRequest is the body of POST /embed.
type EmbedHTTPRequest struct {
	Text  string `json:"text"`
	Model string `json:"model"`
}

// EmbedHTTPResponse is the body of a successful POST /embed.
type EmbedHTTPResponse struct {
	Vector     []float32 `json:"vector"`
	Dims       int       `json:"dims"`
	DurationMs int64     `json:"duration_ms"`
	GatewayID  string    `json:"gateway_id"`
	Error      string    `json:"error,omitempty"`
}

// HandleEmbed serves a synchronous embedding request.
//
// The Pulsar path this service was built for is asynchronous by design, but
// retrieval sits on the critical path of every coding-agent turn and cannot
// round-trip a broker. This route exposes the same node-local discovery and
// fallback logic (ollamaEmbed) over HTTP so rag-retrieval can reuse it instead
// of reimplementing pod selection. See EMBED_TRANSPORT in rag-retrieval.
func (g *Gateway) HandleEmbed(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeEmbedError(w, http.StatusMethodNotAllowed, "use POST")
		return
	}

	var req EmbedHTTPRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		writeEmbedError(w, http.StatusBadRequest, "could not decode request body: "+err.Error())
		return
	}
	if req.Text == "" {
		writeEmbedError(w, http.StatusBadRequest, "text is required")
		return
	}
	if req.Model == "" {
		writeEmbedError(w, http.StatusBadRequest, "model is required")
		return
	}

	start := time.Now()
	vector, err := g.ollamaEmbed(r.Context(), req.Text, req.Model)
	durationMs := time.Since(start).Milliseconds()

	if err != nil {
		logging.Printf("[%s] sync embed failed model=%s chars=%d duration=%dms: %v",
			g.cfg.GatewayID, req.Model, len(req.Text), durationMs, err)
		// 502: the failure is upstream in Ollama, not in the request.
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadGateway)
		_ = json.NewEncoder(w).Encode(EmbedHTTPResponse{
			DurationMs: durationMs,
			GatewayID:  g.cfg.GatewayID,
			Error:      err.Error(),
		})
		return
	}

	logging.Printf("[%s] sync embed complete model=%s chars=%d dims=%d duration=%dms",
		g.cfg.GatewayID, req.Model, len(req.Text), len(vector), durationMs)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(EmbedHTTPResponse{
		Vector:     vector,
		Dims:       len(vector),
		DurationMs: durationMs,
		GatewayID:  g.cfg.GatewayID,
	})
}

func writeEmbedError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(EmbedHTTPResponse{Error: msg})
}
