package models

import (
	"app-builds/common/contracts"
	"app-builds/common/logging"
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// ModelConfig defines model-specific strings and behavior for the GenericModel
type ModelConfig struct {
	PlanningPromptTemplate string
	// SystemInstruction is sent as a "system" role message before any user
	// content. This carries higher behavioral weight than embedding the same
	// text inside the user message. Leave empty to use the legacy single-message
	// format (ExecutionHeader is prepended to the user message instead).
	SystemInstruction          string
	ExecutionHeader            string
	ExecutionFooter            string
	ExecutionSuffix            string
	ExecutionPromptFormatter   func(ModelConfig, string, []interface{}) string
	InsufficientContextPhrases []string
	// FormatterName is the string key used when loading config from YAML
	// ("default" | "numbered" | "tagged"). It mirrors ExecutionPromptFormatter.
	FormatterName string
}

// NewPlannerWithConfig wraps a ChatClient with the given ModelConfig as a Planner.
func NewPlannerWithConfig(client ChatClient, cfg ModelConfig) Planner {
	return &GenericModel{BaseModel: BaseModel{Client: client}, Config: cfg}
}

// NewExecutorWithConfig wraps a ChatClient with the given ModelConfig as an Executor.
func NewExecutorWithConfig(client ChatClient, cfg ModelConfig) Executor {
	return &GenericModel{BaseModel: BaseModel{Client: client}, Config: cfg}
}

// GenericModel implements both Planner and Executor using a ModelConfig
type GenericModel struct {
	BaseModel
	Config ModelConfig
}

// Plan decomposes a user query into a structured task plan using the configured template.
func (m *GenericModel) Plan(ctx context.Context, prompt string, contexts []interface{}, history []interface{}) (*contracts.PlannerTaskPlan, interface{}, error) {
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

	// Planning must not use the executor's SystemInstruction (extraction assistant) or
	// execution formatting (footer/suffix). Build a plain message list: history system
	// messages only (skip prior user turns to avoid confusing the planner), then the
	// planning prompt as a single user message.
	messages := m.assemblePlanningMessages(planningPrompt, history)
	planResult, metrics, err := m.Client.Chat(messages)
	if err != nil {
		return nil, nil, fmt.Errorf("planning Chat failed: %w", err)
	}

	plan := ParsePlannerTaskPlan(planResult, prompt)
	if plan == nil {
		logging.Printf("Planner output did not contain a valid structured plan: %s", planResult)
		plan = (&contracts.PlannerTaskPlan{Objective: prompt, ActionType: contracts.PlannerActionUnknown}).Normalize(prompt)
	}
	return plan, metrics, nil
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

	// If the model config supplies a dedicated system instruction, emit it as a
	// system role message so the model gives it appropriate behavioral weight.
	// This prevents the extraction instruction from being diluted by embedding
	// it inside the user turn alongside the context blocks.
	if instr := strings.TrimSpace(m.Config.SystemInstruction); instr != "" {
		messages = append(messages, map[string]string{"role": "system", "content": instr})
	}

	// Preserve the retrieval order chosen by the memory-controller.
	// Skip any user-role history item whose content exactly matches the current
	// prompt — the gateway often stores the user's question as the last history
	// entry before we append it again as the execution user turn, which would
	// produce two consecutive user messages and confuse most chat templates.
	promptTrimmed := strings.TrimSpace(prompt)
	for _, h := range history {
		content, memType, role := m.extractMemoryFields(h)
		if content == "" {
			continue
		}
		if role == "" {
			role = inferRoleFromMemoryType(memType)
		}
		if role == "" {
			role = "system"
		}
		if role == "user" && strings.TrimSpace(content) == promptTrimmed {
			continue
		}
		messages = append(messages, map[string]string{"role": role, "content": content})
	}

	if len(contexts) > 0 {
		messages = append(messages, map[string]string{"role": "user", "content": m.buildExecutionPrompt(prompt, contexts)})
		return messages
	}

	messages = append(messages, map[string]string{"role": "user", "content": m.buildExecutionPrompt(prompt, nil)})
	return messages
}

// assemblePlanningMessages builds a message list for the planner without the
// executor's SystemInstruction or execution-style formatting. Only system-role
// history items are forwarded so the planner has context rules but no prior
// user turns that would create an awkward multi-turn structure.
func (m *GenericModel) assemblePlanningMessages(planningPrompt string, history []interface{}) []map[string]string {
	var messages []map[string]string

	for _, h := range history {
		content, memType, role := m.extractMemoryFields(h)
		if content == "" {
			continue
		}
		if role == "" {
			role = inferRoleFromMemoryType(memType)
		}
		if role == "" {
			role = "system"
		}
		// Only forward system-role history items to the planner; prior user
		// turns are not relevant and can confuse the planning response.
		if role != "system" {
			continue
		}
		messages = append(messages, map[string]string{"role": role, "content": content})
	}

	messages = append(messages, map[string]string{"role": "user", "content": planningPrompt})
	return messages
}

func (m *GenericModel) buildExecutionPrompt(prompt string, contexts []interface{}) string {
	if formatter := m.Config.ExecutionPromptFormatter; formatter != nil {
		return formatter(m.Config, prompt, contexts)
	}
	return BuildDefaultExecutionPrompt(m.Config, prompt, contexts)
}

func BuildDefaultExecutionPrompt(config ModelConfig, prompt string, contexts []interface{}) string {
	if len(contexts) > 0 {
		var userPrompt strings.Builder
		header := strings.TrimSpace(config.ExecutionHeader)
		if header == "" {
			header = "Retrieved context:"
		}
		userPrompt.WriteString(header)
		userPrompt.WriteString("\n")
		for _, c := range contexts {
			userPrompt.WriteString(fmt.Sprintf("- %v\n", c))
		}
		userPrompt.WriteString("\n")
		footer := strings.TrimSpace(config.ExecutionFooter)
		if footer != "" {
			userPrompt.WriteString(footer)
			userPrompt.WriteString("\n")
		}
		userPrompt.WriteString(prompt)
		if suffix := config.ExecutionSuffix; suffix != "" {
			userPrompt.WriteString(suffix)
		}
		return userPrompt.String()
	}

	userPrompt := prompt
	if footer := config.ExecutionFooter; footer != "" {
		userPrompt = footer + userPrompt
	}
	if suffix := config.ExecutionSuffix; suffix != "" {
		userPrompt += suffix
	}
	return userPrompt
}

func BuildTaggedExecutionPrompt(config ModelConfig, prompt string, contexts []interface{}) string {
	if len(contexts) == 0 {
		return BuildDefaultExecutionPrompt(config, prompt, contexts)
	}

	var userPrompt strings.Builder
	header := strings.TrimSpace(config.ExecutionHeader)
	if header == "" {
		header = "Retrieved context:"
	}
	userPrompt.WriteString(header)
	userPrompt.WriteString("\n")
	for i, c := range contexts {
		if i > 0 {
			userPrompt.WriteString("\n")
		}
		content := strings.TrimSpace(fmt.Sprintf("%v", c))
		if content == "" {
			continue
		}
		userPrompt.WriteString(fmt.Sprintf("<<<CONTEXT %d>>>\n", i+1))
		userPrompt.WriteString(content)
		if !strings.HasSuffix(content, "\n") {
			userPrompt.WriteString("\n")
		}
		userPrompt.WriteString(fmt.Sprintf("<<<END CONTEXT %d>>>\n", i+1))
	}
	userPrompt.WriteString("\n")
	footer := strings.TrimSpace(config.ExecutionFooter)
	if footer != "" {
		userPrompt.WriteString(footer)
		userPrompt.WriteString("\n")
	}
	userPrompt.WriteString(prompt)
	if suffix := config.ExecutionSuffix; suffix != "" {
		userPrompt.WriteString(suffix)
	}
	return userPrompt.String()
}

func BuildNumberedExecutionPrompt(config ModelConfig, prompt string, contexts []interface{}) string {
	if len(contexts) == 0 {
		return BuildDefaultExecutionPrompt(config, prompt, contexts)
	}

	var userPrompt strings.Builder
	header := strings.TrimSpace(config.ExecutionHeader)
	if header == "" {
		header = "Retrieved context:"
	}
	userPrompt.WriteString(header)
	userPrompt.WriteString("\n")
	for i, c := range contexts {
		content := strings.TrimSpace(fmt.Sprintf("%v", c))
		if content == "" {
			continue
		}
		if i > 0 {
			userPrompt.WriteString("\n")
		}
		userPrompt.WriteString(fmt.Sprintf("Context %d:\n", i+1))
		userPrompt.WriteString(content)
		if !strings.HasSuffix(content, "\n") {
			userPrompt.WriteString("\n")
		}
	}
	userPrompt.WriteString("\n")
	footer := strings.TrimSpace(config.ExecutionFooter)
	if footer != "" {
		userPrompt.WriteString(footer)
		userPrompt.WriteString("\n")
	}
	userPrompt.WriteString(prompt)
	if suffix := config.ExecutionSuffix; suffix != "" {
		userPrompt.WriteString(suffix)
	}
	return userPrompt.String()
}

func (m *GenericModel) extractMemoryFields(item interface{}) (content, memType, role string) {
	// Handle *contracts.MemoryWriteItem
	if it, ok := item.(*contracts.MemoryWriteItem); ok {
		content = it.Content
		memType = it.MemoryType
		if it.Metadata != nil {
			meta := contracts.FromStruct(it.Metadata)
			role, _ = meta["role"].(string)
			if role == "" {
				if bucket, ok := meta["context_bucket"].(string); ok && bucket != "" {
					role = inferRoleFromContextBucket(bucket)
				}
			}
		}
		return
	}

	// Handle map[string]interface{} (from protojson unmarshal)
	if hMap, ok := item.(map[string]interface{}); ok {
		content, _ = hMap["content"].(string)
		memType, _ = hMap["memory_type"].(string)
		if meta, ok := hMap["metadata"].(map[string]interface{}); ok {
			role, _ = meta["role"].(string)
			if role == "" {
				if bucket, ok := meta["context_bucket"].(string); ok && bucket != "" {
					role = inferRoleFromContextBucket(bucket)
				}
			}
		}
		return
	}

	return
}

func inferRoleFromMemoryType(memType string) string {
	switch strings.ToLower(strings.TrimSpace(memType)) {
	case "behavioral_rule", "task_local_retrieval", "global_fallback_policy":
		return "system"
	case "chat_history":
		return ""
	default:
		return ""
	}
}

func inferRoleFromContextBucket(bucket string) string {
	switch strings.ToLower(strings.TrimSpace(bucket)) {
	case "behavioral_rules", "action_scoped_behavior", "global_fallback_policy", "task_local_retrieval":
		return "system"
	case "episodic_history":
		return ""
	default:
		return "system"
	}
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

// ParsePlannerTaskPlan extracts a structured plan from planner output.
// It accepts either a JSON object contract or the legacy JSON array of queries.
func ParsePlannerTaskPlan(rawResponse, prompt string) *contracts.PlannerTaskPlan {
	snippet := extractJSONSnippet(rawResponse)
	if snippet != "" && strings.HasPrefix(snippet, "{") {
		var plan contracts.PlannerTaskPlan
		if err := json.Unmarshal([]byte(snippet), &plan); err == nil {
			plan.Trace.RawResponse = rawResponse
			plan.Trace.ParserMode = "json_object"
			plan.Trace.Prompt = prompt
			return plan.Normalize(prompt)
		}
	}

	if queries := ParseJSONArray(rawResponse); len(queries) > 0 {
		return (&contracts.PlannerTaskPlan{
			Objective:     prompt,
			ActionType:    contracts.PlannerActionUnknown,
			SearchQueries: queries,
			ContextBudget: 1,
			Risk:          "unknown",
			Blocking:      true,
			Trace: contracts.PlannerTrace{
				RawResponse: rawResponse,
				ParserMode:  "legacy_array",
				Prompt:      prompt,
			},
		}).Normalize(prompt)
	}

	return (&contracts.PlannerTaskPlan{
		Objective:     prompt,
		ActionType:    contracts.PlannerActionUnknown,
		SearchQueries: []string{prompt},
		ContextBudget: 1,
		Risk:          "unknown",
		Blocking:      true,
		Trace: contracts.PlannerTrace{
			RawResponse: rawResponse,
			ParserMode:  "fallback",
			Prompt:      prompt,
		},
	}).Normalize(prompt)
}

func extractJSONSnippet(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}

	if strings.HasPrefix(trimmed, "```") {
		if end := strings.LastIndex(trimmed, "```"); end > 3 {
			trimmed = strings.TrimSpace(trimmed[3:end])
			if nl := strings.Index(trimmed, "\n"); nl >= 0 {
				head := strings.TrimSpace(trimmed[:nl])
				if !strings.HasPrefix(head, "{") && !strings.HasPrefix(head, "[") {
					trimmed = strings.TrimSpace(trimmed[nl+1:])
				}
			}
		}
	}

	objStart := strings.Index(trimmed, "{")
	objEnd := strings.LastIndex(trimmed, "}")
	arrStart := strings.Index(trimmed, "[")
	arrEnd := strings.LastIndex(trimmed, "]")

	switch {
	case objStart >= 0 && objEnd > objStart:
		return trimmed[objStart : objEnd+1]
	case arrStart >= 0 && arrEnd > arrStart:
		return trimmed[arrStart : arrEnd+1]
	default:
		return trimmed
	}
}
