package contracts

type InternalRequest struct {
	ID             string                 `json:"id"`
	SessionID      string                 `json:"session_id"`
	SessionName    string                 `json:"session_name,omitempty"`
	Prompt         string                 `json:"prompt"`
	SystemPrompt   string                 `json:"system_prompt,omitempty"`
	PlannerModel   string                 `json:"planner_model,omitempty"`
	ExecutorModel  string                 `json:"executor_model,omitempty"`
	Metadata       map[string]interface{} `json:"metadata,omitempty"`
	Tags           []string               `json:"tags,omitempty"`
	Timestamp      string                 `json:"timestamp"`
	Stream         bool                   `json:"stream,omitempty"`
}

type StreamChunk struct {
	ID             string                 `json:"id"`
	SessionID      string                 `json:"session_id"`
	Chunk          string                 `json:"chunk"`
	SequenceNumber int                    `json:"sequence_number"`
	IsLast         bool                   `json:"is_last"`
	Model          string                 `json:"model,omitempty"`
	Metadata       map[string]interface{} `json:"metadata,omitempty"`
	Error          string                 `json:"error,omitempty"`
	InConversation bool                   `json:"in_conversation"`
}

type ResponseCompletion struct {
	ID             string            `json:"id"`
	SessionID      string            `json:"session_id"`
	StartTimestamp string            `json:"start_timestamp"` // RFC3339
	Model          string            `json:"model"`
	Status         string            `json:"status"` // COMPLETED, FAILED
	Metrics        *ExecutionMetrics `json:"metrics,omitempty"`
}

type ExecutionMetrics struct {
	PromptTokens          int     `json:"prompt_tokens"`
	CompletionTokens      int     `json:"completion_tokens"`
	TotalDurationUsec     int64   `json:"total_duration_usec"`
	LoadDurationUsec      int64   `json:"load_duration_usec"`
	PromptEvalDurationUsec int64   `json:"prompt_eval_duration_usec"`
	EvalDurationUsec      int64   `json:"eval_duration_usec"`
	TokensPerSecond       float64 `json:"tokens_per_second"`
	Hostname              string  `json:"hostname,omitempty"`
	ModelFamily           string  `json:"model_family,omitempty"`
}
