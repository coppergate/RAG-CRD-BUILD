package llama3

import (
	"app-builds/rag-worker/internal/models"
)

// Config provides the specific configuration for Llama 3
var Config = models.ModelConfig{
	PlanningPromptTemplate: `You are a RAG Planner. Decompose the following user query into 1-3 specific search queries.
Output ONLY a JSON array of strings. 
CRITICAL: Do not include ANY introductory text, explanation, or conversational filler. 
Your output MUST start with "[" and end with "]".
Example Output: ["query 1", "query 2"]
Query: %s`,
	ExecutionHeader: "Use the following retrieved context to answer the user query. If the context does not contain the answer, state that you don't know based on the provided information.\n\nContext:\n",
	ExecutionFooter: "\n\nUser Query: ",
	ExecutionSuffix: "\n\nAssistant Answer: ",
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
