package llama3

import (
	"app-builds/rag-worker/internal/models"
)

// Config provides the specific configuration for Llama 3
var Config = models.ModelConfig{
	PlanningPromptTemplate: `You are a RAG Planner. Decompose the following user query into 1-3 specific search queries.
Output ONLY a JSON array of strings. Do not include any other text or markdown formatting.
Example Output: ["query 1", "query 2"]
Query: %s`,
	ExecutionHeader: "Context:\n",
	ExecutionFooter: "\nQuery: ",
	ExecutionSuffix: "\nAnswer: ",
	InsufficientContextPhrases: []string{
		"\"insufficient_context\": true",
		"insufficient context",
	},
}

// NewPlanner returns a Planner implementation for Llama 3
func NewPlanner(client models.ChatClient) models.Planner {
	return &models.GenericModel{
		BaseModel: models.BaseModel{Client: client},
		Config:    Config,
	}
}

// NewExecutor returns an Executor implementation for Llama 3
func NewExecutor(client models.ChatClient) models.Executor {
	return &models.GenericModel{
		BaseModel: models.BaseModel{Client: client},
		Config:    Config,
	}
}
