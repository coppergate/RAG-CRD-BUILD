package models

import (
	"app-builds/common/contracts"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"app-builds/common/logging"
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
func (m *GenericModel) Plan(ctx context.Context, prompt string, contexts []interface{}, history []interface{}) ([]string, interface{}, error) {
	var sb strings.Builder
	if len(contexts) > 0 {
		sb.WriteString("Use the following context to refine your search queries for the user query:\n\nContext:\n")
		for _, c := range contexts {
			sb.WriteString(fmt.Sprintf("- %v\n", c))
		}
		sb.WriteString("\n\n")
	}
	sb.WriteString(fmt.Sprintf(m.Config.PlanningPromptTemplate, prompt))
	planningPrompt := sb.String()

	messages := m.assembleMessages(planningPrompt, nil, history)
	planResult, metrics, err := m.Client.Chat(messages)
	if err != nil {
		return nil, nil, fmt.Errorf("planning Chat failed: %w", err)
	}

	subQueries := ParseJSONArray(planResult)
	if len(subQueries) == 0 {
		logging.Printf("Planner output did not contain a valid JSON array or was empty: %s", planResult)
		subQueries = []string{prompt}
	}
	return subQueries, metrics, nil
}

// Execute performs the augmented query with provided contexts using configured templates
func (m *GenericModel) Execute(ctx context.Context, prompt string, contexts []interface{}, history []interface{}) (string, interface{}, error) {
	messages := m.assembleMessages(prompt, contexts, history)
	return m.Client.Chat(messages)
}

// ExecuteStream performs the augmented query with provided contexts and returns a stream of results
func (m *GenericModel) ExecuteStream(ctx context.Context, prompt string, contexts []interface{}, history []interface{}) (<-chan string, <-chan interface{}, <-chan error) {
	messages := m.assembleMessages(prompt, contexts, history)
	return m.Client.ChatStream(messages)
}

func (m *GenericModel) assembleMessages(prompt string, contexts []interface{}, history []interface{}) []map[string]string {
	var messages []map[string]string

	// 1. Add Behavioral Rules as System Messages
	for _, h := range history {
		content, memType, role := m.extractMemoryFields(h)
		if memType == "behavioral_rule" && content != "" {
			messages = append(messages, map[string]string{"role": "system", "content": content})
		}
		_ = role // Not used for rules
	}

	// 2. Add Episodic History (Chat History)
	for _, h := range history {
		content, memType, role := m.extractMemoryFields(h)
		if memType != "behavioral_rule" && role != "" && content != "" {
			messages = append(messages, map[string]string{"role": role, "content": content})
		}
	}

	// 3. Add current augmented prompt
	var augmentedPrompt string
	if len(contexts) > 0 {
		augmentedPrompt = m.Config.ExecutionHeader
		for _, c := range contexts {
			augmentedPrompt += fmt.Sprintf("- %v\n\n", c)
		}
		augmentedPrompt += m.Config.ExecutionFooter + prompt + m.Config.ExecutionSuffix
	} else {
		augmentedPrompt = prompt
	}

	messages = append(messages, map[string]string{"role": "user", "content": augmentedPrompt})
	return messages
}

func (m *GenericModel) extractMemoryFields(item interface{}) (content, memType, role string) {
	// Handle *contracts.MemoryWriteItem
	if it, ok := item.(*contracts.MemoryWriteItem); ok {
		content = it.Content
		memType = it.MemoryType
		if it.Metadata != nil {
			meta := contracts.FromStruct(it.Metadata)
			role, _ = meta["role"].(string)
		}
		return
	}

	// Handle map[string]interface{} (from protojson unmarshal)
	if hMap, ok := item.(map[string]interface{}); ok {
		content, _ = hMap["content"].(string)
		memType, _ = hMap["memory_type"].(string)
		if meta, ok := hMap["metadata"].(map[string]interface{}); ok {
			role, _ = meta["role"].(string)
		}
		return
	}

	return
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
