package granite31

import (
	"app-builds/rag-worker/internal/models"
)

// Config provides the specific configuration for Granite 3.1
var Config = models.ModelConfig{
	PlanningPromptTemplate: `You are a RAG Planner. Decompose the user query into 1-3 search queries.
Output ONLY a JSON array of strings.
Query: %s`,
	ExecutionHeader: "Relevant Context:\n",
	ExecutionFooter: "\nUser Query: ",
	ExecutionSuffix: "\nPlease answer based on the context above. Answer: ",
	InsufficientContextPhrases: []string{
		"insufficient context",
		"i don't have enough information",
		"not mentioned in the context",
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
