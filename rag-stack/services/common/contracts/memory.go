package contracts

type MemoryScope struct {
	SessionID string   `json:"session_id,omitempty"`
	UserID    string   `json:"user_id,omitempty"`
	ProjectID string   `json:"project_id,omitempty"`
	Tags      []string `json:"tags,omitempty"`
}

type MemorySourceRef struct {
	SourceKind   string                 `json:"source_kind"`   // prompt, response, ingestion, manual, system
	SourceID     string                 `json:"source_id"`
	RelationType string                 `json:"relation_type"` // derived_from, supports, contradicts, corrects
	Weight       float64                `json:"weight,omitempty"`
	Metadata     map[string]interface{} `json:"metadata,omitempty"`
}

type MemoryWriteItem struct {
	MemoryID      string                 `json:"memory_id,omitempty"`
	MemoryType    string                 `json:"memory_type"` // short_term_memory, long_term_memory, persistent_memory
	Summary       string                 `json:"summary"`
	Content       string                 `json:"content,omitempty"`
	SalienceHint  float64                `json:"salience_hint,omitempty"`
	RetentionHint float64                `json:"retention_hint,omitempty"`
	Pinned        bool                   `json:"pinned,omitempty"`
	ExpiresAt     string                 `json:"expires_at,omitempty"`
	Metadata      map[string]interface{} `json:"metadata,omitempty"`
	SourceRefs    []MemorySourceRef      `json:"source_refs,omitempty"`
}

type MemoryWriteRequest struct {
	RequestID     string            `json:"request_id"`
	CorrelationID string            `json:"correlation_id,omitempty"`
	Scope         MemoryScope       `json:"scope"`
	Writes        []MemoryWriteItem `json:"writes"`
}

type MemoryRetrieveRequest struct {
	RequestID     string      `json:"request_id"`
	CorrelationID string      `json:"correlation_id,omitempty"`
	Scope         MemoryScope `json:"scope"`
	Query         string      `json:"query,omitempty"`
	Limit         int         `json:"limit,omitempty"`
	MinSalience   float64     `json:"min_salience,omitempty"`
}

type MemoryPack struct {
	Items []MemoryWriteItem `json:"items"`
}
