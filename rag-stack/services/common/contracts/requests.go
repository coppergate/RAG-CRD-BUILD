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
	ID             string `json:"id"`
	SessionID      string `json:"session_id"`
	StartTimestamp string `json:"start_timestamp"` // RFC3339
	Model          string `json:"model"`
	Status         string `json:"status"` // COMPLETED, FAILED
}
