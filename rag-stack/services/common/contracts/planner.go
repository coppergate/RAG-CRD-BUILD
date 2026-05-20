package contracts

import (
	"encoding/json"
	"strings"
)

const PlannerActionUnknown = "UNKNOWN"

// PlannerStep describes one ordered step emitted by the planner.
type PlannerStep struct {
	Order                int      `json:"order"`
	Objective            string   `json:"objective,omitempty"`
	ActionType           string   `json:"action_type,omitempty"`
	Inputs               []string `json:"inputs,omitempty"`
	Outputs              []string `json:"outputs,omitempty"`
	Dependencies         []string `json:"dependencies,omitempty"`
	ContextBudget        int      `json:"context_budget,omitempty"`
	Confidence           float64  `json:"confidence,omitempty"`
	Blocking             bool     `json:"blocking,omitempty"`
	Risk                 string   `json:"risk,omitempty"`
	EvidenceRequirements []string `json:"evidence_requirements,omitempty"`
	SearchQueries        []string `json:"search_queries,omitempty"`
}

// PlannerTrace records how the planner arrived at the task plan.
type PlannerTrace struct {
	RawResponse    string   `json:"raw_response,omitempty"`
	ParserMode     string   `json:"parser_mode,omitempty"`
	Prompt         string   `json:"prompt,omitempty"`
	ContextSources []string `json:"context_sources,omitempty"`
	AppliedRules   []string `json:"applied_rules,omitempty"`
	Notes          []string `json:"notes,omitempty"`
}

// PlannerTaskPlan is the structured contract emitted by the planner.
type PlannerTaskPlan struct {
	Objective            string        `json:"objective,omitempty"`
	ActionType           string        `json:"action_type,omitempty"`
	Inputs               []string      `json:"inputs,omitempty"`
	Outputs              []string      `json:"outputs,omitempty"`
	Dependencies         []string      `json:"dependencies,omitempty"`
	ContextBudget        int           `json:"context_budget,omitempty"`
	Confidence           float64       `json:"confidence,omitempty"`
	Blocking             bool          `json:"blocking,omitempty"`
	Risk                 string        `json:"risk,omitempty"`
	EvidenceRequirements []string      `json:"evidence_requirements,omitempty"`
	SearchQueries        []string      `json:"search_queries,omitempty"`
	Steps                []PlannerStep `json:"steps,omitempty"`
	Trace                PlannerTrace  `json:"trace,omitempty"`
}

// Normalize applies conservative defaults so downstream routing always has a usable plan.
func (p *PlannerTaskPlan) Normalize(prompt string) *PlannerTaskPlan {
	if p == nil {
		return &PlannerTaskPlan{
			Objective:     prompt,
			ActionType:    PlannerActionUnknown,
			SearchQueries: []string{prompt},
			ContextBudget: 1,
			Risk:          "unknown",
			Blocking:      true,
		}
	}

	if strings.TrimSpace(p.Objective) == "" {
		p.Objective = prompt
	}

	p.ActionType = normalizePlannerToken(p.ActionType)
	if p.ActionType == "" {
		p.ActionType = PlannerActionUnknown
	}

	if len(p.SearchQueries) == 0 {
		for _, step := range p.Steps {
			if len(step.SearchQueries) > 0 {
				p.SearchQueries = append(p.SearchQueries, step.SearchQueries...)
			}
		}
	}

	if len(p.SearchQueries) == 0 {
		p.SearchQueries = []string{prompt}
	}

	if p.ContextBudget <= 0 {
		p.ContextBudget = 1
	}
	if strings.TrimSpace(p.Risk) == "" {
		p.Risk = "unknown"
	}
	if len(p.Steps) > 0 {
		orderMissing := true
		for _, step := range p.Steps {
			if step.Order > 0 {
				orderMissing = false
				break
			}
		}
		if orderMissing {
			for i := range p.Steps {
				p.Steps[i].Order = i + 1
			}
		}
	}

	return p
}

// ToMap converts the plan into a map for metadata persistence.
func (p *PlannerTaskPlan) ToMap() map[string]interface{} {
	if p == nil {
		return nil
	}
	var out map[string]interface{}
	raw, err := json.Marshal(p)
	if err != nil {
		return map[string]interface{}{}
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return map[string]interface{}{}
	}
	return out
}

// ToMap converts the trace into a map for metadata persistence.
func (p *PlannerTrace) ToMap() map[string]interface{} {
	if p == nil {
		return nil
	}
	var out map[string]interface{}
	raw, err := json.Marshal(p)
	if err != nil {
		return map[string]interface{}{}
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return map[string]interface{}{}
	}
	return out
}

func normalizePlannerToken(v string) string {
	return strings.ToUpper(strings.TrimSpace(v))
}
