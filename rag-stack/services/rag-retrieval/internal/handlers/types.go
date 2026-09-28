package handlers

import (
	"app-builds/rag-retrieval/internal/memory"
	"app-builds/rag-retrieval/internal/qdrant"
)

// RetrieveRequest is the body of POST /v1/rag/retrieve.
//
// Every field is optional except Query. Unknown fields are ignored rather than
// rejected, matching the tolerance the OpenAI surface requires (§2.2).
type RetrieveRequest struct {
	Query          string   `json:"query"`
	Session        string   `json:"session"`
	Project        string   `json:"project"`
	Tags           []string `json:"tags"`
	IncludeGlobal  *bool    `json:"include_global"`
	TopK           int      `json:"top_k"`
	MaxTokens      int      `json:"max_tokens"`
	EmbeddingModel string   `json:"embedding_model"`
	IncludeMemory  *bool    `json:"include_memory"`
	Format         string   `json:"format"`  // "block" | "chunks"
	Profile        string   `json:"profile"` // "auto" | "planner" | "executor" | "none"
	Agent          string   `json:"agent"`
	Model          string   `json:"model"`
}

type Timings struct {
	Embed    int64 `json:"embed"`
	Search   int64 `json:"search"`
	Memory   int64 `json:"memory,omitempty"`
	Assemble int64 `json:"assemble"`
	Total    int64 `json:"total"`
}

// RetrieveResponse mirrors spec §4 B.2, with the corrections from the code:
// chunks carry `path` + `chunk` (and `start_line`/`end_line` when ingested with
// them) rather than the spec's `source` + unconditional line range.
type RetrieveResponse struct {
	CorrelationID string          `json:"correlation_id"`
	SessionID     int64           `json:"session_id,omitempty"`
	Profile       string          `json:"profile"`
	Block         string          `json:"block,omitempty"`
	Chunks        []qdrant.Chunk  `json:"chunks"`
	Memory        []memory.Item   `json:"memory,omitempty"`
	Tokens        int             `json:"tokens"`
	Truncated     bool            `json:"truncated"`
	Collection    string          `json:"collection,omitempty"`
	Timings       Timings         `json:"timings_ms"`

	// CollectionMissing distinguishes "the corpus has not been ingested" from
	// "the query matched nothing". Both return zero chunks; only one is a
	// configuration problem. Spec §10.4.
	CollectionMissing bool `json:"collection_missing,omitempty"`

	// UnknownTags names requested tags that do not exist, so a typo does not
	// silently widen retrieval to the entire corpus.
	UnknownTags []string `json:"unknown_tags,omitempty"`

	// Degraded records non-fatal failures (memory lookup, session mapping).
	// Retrieval is never allowed to fail the caller, so problems are reported
	// in-band instead of as a status code.
	Degraded []string `json:"degraded,omitempty"`
}

type IngestTurnRequest struct {
	Session  string         `json:"session"`
	Project  string         `json:"project"`
	Kind     string         `json:"kind"` // user_turn | tool_result | assistant_turn
	Tool     string         `json:"tool"`
	Text     string         `json:"text"`
	Metadata map[string]any `json:"metadata"`
}

type errorBody struct {
	Error errorDetail `json:"error"`
}

type errorDetail struct {
	Message string `json:"message"`
	Code    string `json:"code,omitempty"`
}
