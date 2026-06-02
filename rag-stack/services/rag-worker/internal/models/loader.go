package models

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// modelConfigYAML is the on-disk representation of a ModelConfig.
// All fields are optional; absent fields fall through to the defaults layer.
type modelConfigYAML struct {
	PlanningPromptTemplate     string   `yaml:"planning_prompt_template"`
	SystemInstruction          string   `yaml:"system_instruction"`
	ExecutionHeader            string   `yaml:"execution_header"`
	ExecutionFooter            string   `yaml:"execution_footer"`
	ExecutionSuffix            string   `yaml:"execution_suffix"`
	ExecutionPromptFormatter   string   `yaml:"execution_prompt_formatter"`
	InsufficientContextPhrases []string `yaml:"insufficient_context_phrases"`
}

// formattersByName maps the string key used in YAML to the corresponding formatter function.
var formattersByName = map[string]func(ModelConfig, string, []interface{}) string{
	"default":  BuildDefaultExecutionPrompt,
	"numbered": BuildNumberedExecutionPrompt,
	"tagged":   BuildTaggedExecutionPrompt,
}

// LoadModelConfig reads a shared defaults file and a per-model override file,
// merges them (override wins on every non-zero field), and returns a ModelConfig
// with the formatter function resolved from its name.
//
// Either path may be empty, in which case that layer is skipped. It is valid to
// call LoadModelConfig("", "") — the result is a zero-value ModelConfig with the
// default formatter applied.
func LoadModelConfig(defaultsPath, overridePath string) (ModelConfig, error) {
	var base, override modelConfigYAML

	if defaultsPath != "" {
		data, err := os.ReadFile(defaultsPath)
		if err != nil {
			return ModelConfig{}, fmt.Errorf("reading model defaults %q: %w", defaultsPath, err)
		}
		if err := yaml.Unmarshal(data, &base); err != nil {
			return ModelConfig{}, fmt.Errorf("parsing model defaults %q: %w", defaultsPath, err)
		}
	}

	if overridePath != "" {
		data, err := os.ReadFile(overridePath)
		if err != nil {
			return ModelConfig{}, fmt.Errorf("reading model config %q: %w", overridePath, err)
		}
		if err := yaml.Unmarshal(data, &override); err != nil {
			return ModelConfig{}, fmt.Errorf("parsing model config %q: %w", overridePath, err)
		}
	}

	merged := mergeModelConfigYAML(base, override)
	return resolveModelConfig(merged), nil
}

// mergeModelConfigYAML applies override fields on top of base; any non-zero
// override field replaces the corresponding base field.
func mergeModelConfigYAML(base, override modelConfigYAML) modelConfigYAML {
	if override.PlanningPromptTemplate != "" {
		base.PlanningPromptTemplate = override.PlanningPromptTemplate
	}
	if override.SystemInstruction != "" {
		base.SystemInstruction = override.SystemInstruction
	}
	if override.ExecutionHeader != "" {
		base.ExecutionHeader = override.ExecutionHeader
	}
	if override.ExecutionFooter != "" {
		base.ExecutionFooter = override.ExecutionFooter
	}
	if override.ExecutionSuffix != "" {
		base.ExecutionSuffix = override.ExecutionSuffix
	}
	if override.ExecutionPromptFormatter != "" {
		base.ExecutionPromptFormatter = override.ExecutionPromptFormatter
	}
	if len(override.InsufficientContextPhrases) > 0 {
		base.InsufficientContextPhrases = override.InsufficientContextPhrases
	}
	return base
}

// resolveModelConfig converts the YAML intermediate form into a ModelConfig,
// resolving the formatter name to its function. Falls back to BuildNumberedExecutionPrompt
// for unknown or empty formatter names.
func resolveModelConfig(y modelConfigYAML) ModelConfig {
	formatter, ok := formattersByName[y.ExecutionPromptFormatter]
	if !ok {
		formatter = BuildNumberedExecutionPrompt
	}
	return ModelConfig{
		PlanningPromptTemplate:     y.PlanningPromptTemplate,
		SystemInstruction:          y.SystemInstruction,
		ExecutionHeader:            y.ExecutionHeader,
		ExecutionFooter:            y.ExecutionFooter,
		ExecutionSuffix:            y.ExecutionSuffix,
		ExecutionPromptFormatter:   formatter,
		InsufficientContextPhrases: y.InsufficientContextPhrases,
		FormatterName:              y.ExecutionPromptFormatter,
	}
}
