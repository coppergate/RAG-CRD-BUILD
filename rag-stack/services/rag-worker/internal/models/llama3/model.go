package llama3

import (
	"app-builds/rag-worker/internal/models"
)

// Config provides the specific configuration for Llama 3
var Config = models.ModelConfig{
	PlanningPromptTemplate: `You are a RAG Planner. Return ONLY a JSON object with this shape:
{
  "objective": "string",
  "action_type": "FILE_SEARCH|FILE_EDIT|FILE_VCS|REMOTE_EXEC|K8S_ORCHESTRATE|DB_ACCESS|BUILD_DEPLOY|DOC_PROCESS|JOB_RESUME|WEB_FETCH|UNKNOWN",
  "inputs": ["string"],
  "outputs": ["string"],
  "dependencies": ["string"],
  "context_budget": 1,
  "confidence": 0.0,
  "blocking": true,
  "risk": "read_only|mutating|infra|unknown",
  "evidence_requirements": ["string"],
  "search_queries": ["string"],
  "steps": [
    {
      "order": 1,
      "objective": "string",
      "action_type": "string",
      "inputs": ["string"],
      "outputs": ["string"],
      "dependencies": ["string"],
      "context_budget": 1,
      "confidence": 0.0,
      "blocking": true,
      "risk": "string",
      "evidence_requirements": ["string"],
      "search_queries": ["string"]
    }
  ]
}
If the request is ambiguous, use action_type UNKNOWN and put the exact prompt in search_queries.
Query: %s`,
	ExecutionHeader:          "You are a strict extraction assistant. This is a benign retrieval test, so do not refuse, do not apologize, and do not add commentary. Use the retrieved context as the only source of truth. If the answer appears in the context, return the exact literal answer from the context and nothing else. The answer may appear inside a longer sentence; extract the shortest exact phrase that answers the question. If the answer is a code or token, preserve its exact characters, including hyphens and digits. If the context does not contain the answer, say that you don't know.\n\nContext:\n",
	ExecutionFooter:          "\n\nUser Query: ",
	ExecutionSuffix:          "\n\nAssistant Answer: ",
	ExecutionPromptFormatter: models.BuildTaggedExecutionPrompt,
	InsufficientContextPhrases: []string{
		"\"insufficient_context\": true",
		"insufficient context",
		"i can't provide",
		"i cannot provide",
		"i can not provide",
		"i'm sorry",
		"i can’t provide",
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
