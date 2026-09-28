package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"app-builds/common/logging"
	"app-builds/rag-retrieval/internal/assemble"
	"app-builds/rag-retrieval/internal/profile"
	"app-builds/rag-retrieval/internal/qdrant"
)

// HandleRetrieve implements POST /v1/rag/retrieve.
//
// Contract: this endpoint does not fail the caller for retrieval reasons. A
// missing collection, an empty corpus, a dead memory-controller or an
// unresolvable session all produce 200 with an explanatory field. Only a
// malformed request or a dead embedder/Qdrant is an error status, because those
// mean we cannot answer at all.
func (h *Handler) HandleRetrieve(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "use POST")
		return
	}

	start := time.Now()
	correlationID := uuid.NewString()

	r.Body = http.MaxBytesReader(w, r.Body, h.Cfg.MaxBodyBytes)
	var req RetrieveRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "could not decode request body: "+err.Error())
		return
	}

	applyHeaders(&req, r)

	req.Query = strings.TrimSpace(req.Query)
	if req.Query == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "query is required")
		return
	}

	resp := RetrieveResponse{CorrelationID: correlationID, Chunks: []qdrant.Chunk{}}

	// ── Profile ───────────────────────────────────────────────────────────────
	prof := profile.Derive(profile.Parse(req.Profile), req.Agent, req.Model)
	resp.Profile = string(prof)

	if prof == profile.None {
		// Titles and other small-model work retrieve nothing at all (§5.5).
		resp.Timings.Total = time.Since(start).Milliseconds()
		setResponseHeaders(w, correlationID, 0, 0, string(prof))
		writeJSON(w, http.StatusOK, resp)
		return
	}

	topK := h.resolveTopK(req.TopK, prof)
	maxTokens := req.MaxTokens
	if maxTokens <= 0 {
		maxTokens = h.Cfg.DefaultMaxTokens
	}

	// ── Tags ──────────────────────────────────────────────────────────────────
	wanted := req.Tags
	if len(wanted) == 0 {
		wanted = h.profileTags(prof)
	}
	tagIDs, unknown := h.Tags.Resolve(r.Context(), wanted)
	resp.UnknownTags = unknown

	// include_global defaults true: with no resolvable tags we search the whole
	// corpus rather than returning nothing. When it is explicitly false and no
	// tag resolved, an unfiltered search would silently ignore the caller's
	// scoping, so return empty instead.
	includeGlobal := req.IncludeGlobal == nil || *req.IncludeGlobal
	if len(tagIDs) == 0 && !includeGlobal {
		resp.Degraded = append(resp.Degraded,
			"no requested tag resolved and include_global=false; returning no context")
		resp.Timings.Total = time.Since(start).Milliseconds()
		setResponseHeaders(w, correlationID, 0, 0, string(prof))
		writeJSON(w, http.StatusOK, resp)
		return
	}

	// ── Session (non-fatal) ───────────────────────────────────────────────────
	if req.Session != "" {
		sessCtx, cancel := context.WithTimeout(r.Context(), h.Cfg.MemoryTimeout)
		sid, err := h.Sessions.Resolve(sessCtx, req.Session, "opencode")
		cancel()
		if err != nil {
			logging.Printf("[retrieval] session mapping failed corr=%s session=%q: %v",
				correlationID, req.Session, err)
			resp.Degraded = append(resp.Degraded, "session mapping unavailable")
		}
		resp.SessionID = sid
	}

	// ── Embed ─────────────────────────────────────────────────────────────────
	embedStart := time.Now()
	embedCtx, cancelEmbed := context.WithTimeout(r.Context(), h.Cfg.EmbedTimeout)
	vector, err := h.Embedder.Embed(embedCtx, req.Query, req.EmbeddingModel)
	cancelEmbed()
	resp.Timings.Embed = time.Since(embedStart).Milliseconds()
	if err != nil {
		// No vector means no retrieval is possible. This is a real failure, but
		// the plugin is required to degrade to passthrough on any non-200, so
		// the coding session still continues.
		logging.Printf("[retrieval] embed failed corr=%s transport=%s: %v",
			correlationID, h.Embedder.Transport(), err)
		writeError(w, http.StatusBadGateway, "embed_failed", "query embedding failed: "+err.Error())
		return
	}

	// ── Search ────────────────────────────────────────────────────────────────
	searchStart := time.Now()
	searchCtx, cancelSearch := context.WithTimeout(r.Context(), h.Cfg.SearchTimeout)
	chunks, collection, err := h.Qdrant.Search(searchCtx, qdrant.SearchParams{
		Collection:     h.Cfg.Collection,
		EmbeddingModel: firstNonEmpty(req.EmbeddingModel, h.Cfg.EmbeddingModel),
		VectorSize:     h.Cfg.VectorSize,
		Vector:         vector,
		Limit:          topK,
		Tags:           tagIDs,
	})
	cancelSearch()
	resp.Timings.Search = time.Since(searchStart).Milliseconds()
	resp.Collection = collection

	if err != nil {
		if errors.Is(err, qdrant.ErrCollectionMissing) {
			// The corpus has not been ingested for this model. Report it as
			// empty-and-explained, not as a failure — §10.4.
			logging.Printf("[retrieval] collection missing corr=%s collection=%q model=%q: %v",
				correlationID, collection, firstNonEmpty(req.EmbeddingModel, h.Cfg.EmbeddingModel), err)
			resp.CollectionMissing = true
			resp.Degraded = append(resp.Degraded, fmt.Sprintf(
				"collection %q does not exist; corpus not ingested for embedding model %q",
				collection, firstNonEmpty(req.EmbeddingModel, h.Cfg.EmbeddingModel)))
			resp.Timings.Total = time.Since(start).Milliseconds()
			setResponseHeaders(w, correlationID, 0, 0, string(prof))
			writeJSON(w, http.StatusOK, resp)
			return
		}
		logging.Printf("[retrieval] search failed corr=%s: %v", correlationID, err)
		writeError(w, http.StatusBadGateway, "search_failed", "vector search failed: "+err.Error())
		return
	}

	for i := range chunks {
		chunks[i].TagNames = h.Tags.Names(chunks[i].Tags)
	}
	resp.Chunks = chunks

	// ── Memory (planner only, non-fatal) ──────────────────────────────────────
	includeMemory := prof == profile.Planner
	if req.IncludeMemory != nil {
		includeMemory = *req.IncludeMemory
	}
	if includeMemory && resp.SessionID != 0 {
		memStart := time.Now()
		memCtx, cancelMem := context.WithTimeout(r.Context(), h.Cfg.MemoryTimeout)
		items, memErr := h.Memory.Retrieve(memCtx, resp.SessionID, req.Query, topK)
		cancelMem()
		resp.Timings.Memory = time.Since(memStart).Milliseconds()
		if memErr != nil {
			logging.Printf("[retrieval] memory lookup failed corr=%s: %v", correlationID, memErr)
			resp.Degraded = append(resp.Degraded, "memory lookup unavailable")
		} else {
			resp.Memory = items
		}
	}

	// ── Assemble ──────────────────────────────────────────────────────────────
	if strings.ToLower(req.Format) != "chunks" {
		asmStart := time.Now()
		built := assemble.Build(assemble.Input{
			Chunks:    resp.Chunks,
			Memory:    resp.Memory,
			Tags:      h.Tags.Names(tagIDs),
			Profile:   string(prof),
			TopK:      topK,
			MaxTokens: maxTokens,
		})
		resp.Timings.Assemble = time.Since(asmStart).Milliseconds()
		resp.Block = built.Block
		resp.Tokens = built.Tokens
		resp.Truncated = built.Truncated
	}

	resp.Timings.Total = time.Since(start).Milliseconds()
	setResponseHeaders(w, correlationID, len(resp.Chunks), resp.Tokens, string(prof))

	logging.Printf("[retrieval] corr=%s profile=%s collection=%q tags=%v chunks=%d tokens=%d transport=%s total=%dms",
		correlationID, prof, collection, tagIDs, len(resp.Chunks), resp.Tokens,
		h.Embedder.Transport(), resp.Timings.Total)

	writeJSON(w, http.StatusOK, resp)
}

// applyHeaders lets the X-RAG-* control surface (§A.4) override body fields.
// Headers win because the plugin's chat.headers hook knows things the body
// does not, notably the agent name.
func applyHeaders(req *RetrieveRequest, r *http.Request) {
	if v := r.Header.Get("X-RAG-Session"); v != "" {
		req.Session = v
	}
	if v := r.Header.Get("X-RAG-Project"); v != "" {
		req.Project = v
	}
	if v := r.Header.Get("X-RAG-Agent"); v != "" {
		req.Agent = v
	}
	if v := r.Header.Get("X-RAG-Profile"); v != "" {
		req.Profile = v
	}
	if v := r.Header.Get("X-RAG-Embedding-Model"); v != "" {
		req.EmbeddingModel = v
	}
	if v := r.Header.Get("X-RAG-Tags"); v != "" {
		parts := strings.Split(v, ",")
		req.Tags = req.Tags[:0]
		for _, p := range parts {
			if t := strings.TrimSpace(p); t != "" {
				req.Tags = append(req.Tags, t)
			}
		}
	}
	if v := r.Header.Get("X-RAG-Top-K"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			req.TopK = n
		}
	}
	if v := r.Header.Get("X-RAG-Include-Global"); v != "" {
		if b, err := strconv.ParseBool(v); err == nil {
			req.IncludeGlobal = &b
		}
	}
	// X-RAG-Mode: off is a client-side kill switch for retrieval.
	if strings.EqualFold(r.Header.Get("X-RAG-Mode"), "off") {
		req.Profile = "none"
	}
}

func setResponseHeaders(w http.ResponseWriter, correlationID string, retrieved, tokens int, mode string) {
	w.Header().Set("X-RAG-Correlation-Id", correlationID)
	w.Header().Set("X-RAG-Retrieved", strconv.Itoa(retrieved))
	w.Header().Set("X-RAG-Injected-Tokens", strconv.Itoa(tokens))
	w.Header().Set("X-RAG-Mode-Applied", mode)
}

func (h *Handler) resolveTopK(requested int, prof profile.Profile) int {
	k := requested
	if k <= 0 {
		switch prof {
		case profile.Planner:
			k = h.Cfg.PlannerTopK
		case profile.Executor:
			k = h.Cfg.ExecutorTopK
		default:
			k = h.Cfg.DefaultTopK
		}
	}
	if k > h.Cfg.MaxTopK {
		k = h.Cfg.MaxTopK
	}
	if k <= 0 {
		k = 1
	}
	return k
}

func (h *Handler) profileTags(prof profile.Profile) []string {
	switch prof {
	case profile.Planner:
		return h.Cfg.PlannerTags
	case profile.Executor:
		return h.Cfg.ExecutorTags
	default:
		return nil
	}
}
