package contracts

type InternalRequest struct {
	ID             string                 `json:"id"`
	SessionID      string                 `json:"session_id"`
	Prompt         string                 `json:"prompt"`
	SystemPrompt   string                 `json:"system_prompt,omitempty"`
	PlannerModel   string                 `json:"planner_model,omitempty"`
	ExecutorModel  string                 `json:"executor_model,omitempty"`
	Metadata       map[string]interface{} `json:"metadata,omitempty"`
	Tags           []string               `json:"tags,omitempty"`
	Timestamp      string                 `json:"timestamp"`
}
