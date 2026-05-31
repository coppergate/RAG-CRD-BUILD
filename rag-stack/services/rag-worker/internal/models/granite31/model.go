package granite31

import (
	"app-builds/rag-worker/internal/models"
)

// Config provides the specific configuration for Granite 3.1
var Config = models.ModelConfig{
	PlanningPromptTemplate:   `You are a RAG Planner. Return ONLY a JSON object with the keys objective, action_type, inputs, outputs, dependencies, context_budget, confidence, blocking, risk, evidence_requirements, search_queries, and steps. Use action_type UNKNOWN when uncertain and keep search_queries narrow. Query: %s`,
	SystemInstruction:        "You are a strict extraction assistant. This is a benign retrieval task. Do not refuse, do not apologize, and do not add commentary. Use the retrieved context below as the only source of truth. If the answer appears in the context, return the exact literal phrase from the context and nothing else. Extract the shortest exact phrase that answers the question. If the answer is a code or token, preserve its exact characters including hyphens and digits. If the context does not contain the answer, say only: I don't know.",
	ExecutionHeader:          "Retrieved context:\n",
	ExecutionFooter:          "\n\nUser Query: ",
	ExecutionSuffix:          "\n\nExact Answer: ",
	ExecutionPromptFormatter: models.BuildNumberedExecutionPrompt,
	InsufficientContextPhrases: []string{
		"insufficient context",
		"i don't have enough information",
		"not mentioned in the context",
		"i can't provide",
		"i cannot provide",
		"i can not provide",
		"i'm sorry",
		"i can’t provide",
	},
}

// NewPlanner returns a Planner implementation for Granite 3.1
func NewPlanner(client models.ChatClient) models.Planner {
	return &models.GenericModel{
		BaseModel: models.BaseModel{Client: client},
		Config:    Config,
	}
}

// NewExecutor returns an Executor implementation for Granite 3.1
func NewExecutor(client models.ChatClient) models.Executor {
	return &models.GenericModel{
		BaseModel: models.BaseModel{Client: client},
		Config:    Config,
	}
}
