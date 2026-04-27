package models

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
)

// ModelConfig defines model-specific strings and behavior for the GenericModel
type ModelConfig struct {
	PlanningPromptTemplate      string
	ExecutionHeader             string
	ExecutionFooter             string
	ExecutionSuffix             string
	InsufficientContextPhrases []string
}

// GenericModel implements both Planner and Executor using a ModelConfig
type GenericModel struct {
	BaseModel
	Config ModelConfig
}

// Plan decomposes a user query into specific search queries using the configured template
func (m *GenericModel) Plan(ctx context.Context, prompt string) ([]string, interface{}, error) {
	planningPrompt := fmt.Sprintf(m.Config.PlanningPromptTemplate, prompt)
	planResult, metrics, err := m.ChatSingleTurn(ctx, planningPrompt)
	if err != nil {
		return nil, nil, fmt.Errorf("planning Chat failed: %w", err)
	}

	subQueries := ParseJSONArray(planResult)
	if len(subQueries) == 0 {
		log.Printf("Planner output did not contain a valid JSON array or was empty: %s", planResult)
		subQueries = []string{prompt}
	}
	return subQueries, metrics, nil
}

// Execute performs the augmented query with provided contexts using configured templates
func (m *GenericModel) Execute(ctx context.Context, prompt string, contexts []interface{}) (string, interface{}, error) {
	augmentedPrompt := m.Config.ExecutionHeader
	for _, c := range contexts {
		augmentedPrompt += fmt.Sprintf("- %v\n\n", c)
	}
	augmentedPrompt += m.Config.ExecutionFooter + prompt + m.Config.ExecutionSuffix

	result, metrics, err := m.ChatSingleTurn(ctx, augmentedPrompt)
	if err != nil {
		return "", nil, fmt.Errorf("execution Chat failed: %w", err)
	}
	return result, metrics, nil
}

// ExecuteStream performs the augmented query with provided contexts and returns a stream of results
func (m *GenericModel) ExecuteStream(ctx context.Context, prompt string, contexts []interface{}) (<-chan string, <-chan interface{}, <-chan error) {
	augmentedPrompt := m.Config.ExecutionHeader
	for _, c := range contexts {
		augmentedPrompt += fmt.Sprintf("- %v\n\n", c)
	}
	augmentedPrompt += m.Config.ExecutionFooter + prompt + m.Config.ExecutionSuffix

	messages := []map[string]string{
		{"role": "user", "content": augmentedPrompt},
	}
	return m.Client.ChatStream(messages)
}

// IsInsufficientContext checks if the model result indicates missing information based on configured phrases
func (m *GenericModel) IsInsufficientContext(result string) bool {
	r := strings.ToLower(result)
	for _, phrase := range m.Config.InsufficientContextPhrases {
		if strings.Contains(r, strings.ToLower(phrase)) {
			return true
		}
	}
	return false
}

// BaseModel provides common functionality for all model implementations
type BaseModel struct {
	Client ChatClient
}

// GetEmbeddings is a common implementation for the Planner interface
func (m *BaseModel) GetEmbeddings(ctx context.Context, text string) ([]float32, error) {
	return m.Client.GetEmbeddings(text)
}

// ChatSingleTurn sends a single user message to the LLM
func (m *BaseModel) ChatSingleTurn(ctx context.Context, prompt string) (string, interface{}, error) {
	messages := []map[string]string{
		{"role": "user", "content": prompt},
	}
	return m.Client.Chat(messages)
}

// ParseJSONArray attempts to extract a JSON array of strings from a string
func ParseJSONArray(s string) []string {
	var result []string
	start := strings.Index(s, "[")
	end := strings.LastIndex(s, "]")
	if start == -1 || end == -1 || end <= start {
		return nil
	}
	jsonStr := s[start : end+1]
	// Clean common LLM JSON mistakes (trailing commas)
	jsonStr = strings.ReplaceAll(jsonStr, ",]", "]")
	jsonStr = strings.ReplaceAll(jsonStr, ", }", "}")
	jsonStr = strings.ReplaceAll(jsonStr, ",}", "}")
	if err := json.Unmarshal([]byte(jsonStr), &result); err != nil {
		return nil
	}
	return result
}
