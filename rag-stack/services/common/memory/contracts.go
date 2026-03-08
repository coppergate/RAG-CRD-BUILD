package memory

import "time"

type MemoryType string

const (
	ShortTermMemory  MemoryType = "short_term_memory"
	LongTermMemory   MemoryType = "long_term_memory"
	PersistentMemory MemoryType = "persistent_memory"
)

type MemoryScope struct {
	SessionID string   `json:"session_id,omitempty"`
	UserID    string   `json:"user_id,omitempty"`
	ProjectID string   `json:"project_id,omitempty"`
	Tags      []string `json:"tags,omitempty"`
}

type SourceRef struct {
	SourceKind   string                 `json:"source_kind"`
	SourceID     string                 `json:"source_id"`
	RelationType string                 `json:"relation_type"`
	Weight       float64                `json:"weight,omitempty"`
	Metadata     map[string]interface{} `json:"metadata,omitempty"`
}

type MemoryWriteItem struct {
	MemoryID      string                 `json:"memory_id,omitempty"`
	MemoryType    MemoryType             `json:"memory_type"`
	Summary       string                 `json:"summary"`
	Content       string                 `json:"content,omitempty"`
	SalienceHint  *float64               `json:"salience_hint,omitempty"`
	RetentionHint *float64               `json:"retention_hint,omitempty"`
	Pinned        bool                   `json:"pinned,omitempty"`
	ExpiresAt     *time.Time             `json:"expires_at,omitempty"`
	Metadata      map[string]interface{} `json:"metadata,omitempty"`
	SourceRefs    []SourceRef            `json:"source_refs,omitempty"`
}

type MemoryWriteRequest struct {
	RequestID     string            `json:"request_id"`
	CorrelationID string            `json:"correlation_id,omitempty"`
	Scope         MemoryScope       `json:"scope"`
	Writes        []MemoryWriteItem `json:"writes"`
}

type MemoryRetrieveLimits struct {
	MaxItems         int `json:"max_items"`
	MaxTokens        int `json:"max_tokens"`
	ShortTermTokens  int `json:"short_term_tokens,omitempty"`
	LongTermTokens   int `json:"long_term_tokens,omitempty"`
	PersistentTokens int `json:"persistent_tokens,omitempty"`
}

type MemoryRetrieveFilters struct {
	MemoryTypes       []MemoryType `json:"memory_types,omitempty"`
	MinSalience       *float64     `json:"min_salience,omitempty"`
	MinRetentionScore *float64     `json:"min_retention_score,omitempty"`
	PinnedOnly        bool         `json:"pinned_only,omitempty"`
}

type MemoryRetrieveRequest struct {
	RequestID      string                `json:"request_id"`
	CorrelationID  string                `json:"correlation_id,omitempty"`
	MemoryMode     string                `json:"memory_mode,omitempty"`
	Scope          MemoryScope           `json:"scope"`
	QueryText      string                `json:"query_text"`
	QueryEmbedding []float64             `json:"query_embedding,omitempty"`
	Filters        MemoryRetrieveFilters `json:"filters,omitempty"`
	Limits         MemoryRetrieveLimits  `json:"limits"`
	Debug          bool                  `json:"debug,omitempty"`
}

type MemoryPackItem struct {
	MemoryID       string                 `json:"memory_id"`
	MemoryType     MemoryType             `json:"memory_type"`
	Summary        string                 `json:"summary"`
	Content        string                 `json:"content,omitempty"`
	Salience       float64                `json:"salience,omitempty"`
	RetentionScore float64                `json:"retention_score,omitempty"`
	RankScore      float64                `json:"rank_score"`
	TokenEstimate  int                    `json:"token_estimate,omitempty"`
	WhySelected    string                 `json:"why_selected,omitempty"`
	SourceRefs     []SourceRef            `json:"source_refs,omitempty"`
	Metadata       map[string]interface{} `json:"metadata,omitempty"`
}

type MemoryPackBudget struct {
	MaxTokens      int `json:"max_tokens"`
	UsedTokens     int `json:"used_tokens"`
	ShortTermUsed  int `json:"short_term_used,omitempty"`
	LongTermUsed   int `json:"long_term_used,omitempty"`
	PersistentUsed int `json:"persistent_used,omitempty"`
}

type MemoryDrop struct {
	MemoryID string `json:"memory_id"`
	Reason   string `json:"reason"`
}

type MemoryConflict struct {
	WinnerMemoryID string `json:"winner_memory_id"`
	LoserMemoryID  string `json:"loser_memory_id"`
	Resolution     string `json:"resolution"`
}

type MemoryPack struct {
	RequestID     string           `json:"request_id"`
	CorrelationID string           `json:"correlation_id,omitempty"`
	GeneratedAt   time.Time        `json:"generated_at"`
	Mode          string           `json:"mode,omitempty"`
	Items         []MemoryPackItem `json:"items"`
	TokenBudget   MemoryPackBudget `json:"token_budget"`
	Dropped       []MemoryDrop     `json:"dropped,omitempty"`
	Conflicts     []MemoryConflict `json:"conflicts,omitempty"`
}
