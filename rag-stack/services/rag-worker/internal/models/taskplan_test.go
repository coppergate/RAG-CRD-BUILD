package models

import (
	"testing"

	"app-builds/common/contracts"
)

func TestParsePlannerTaskPlan(t *testing.T) {
	tests := []struct {
		name     string
		raw      string
		wantType string
		wantSQ   []string
	}{
		{
			name:     "structured object",
			raw:      `{"objective":"inspect files","action_type":"FILE_SEARCH","search_queries":["a","b"],"steps":[{"objective":"find symbol","search_queries":["sym"]}]}`,
			wantType: "FILE_SEARCH",
			wantSQ:   []string{"a", "b"},
		},
		{
			name:     "legacy array",
			raw:      `["one","two"]`,
			wantType: contracts.PlannerActionUnknown,
			wantSQ:   []string{"one", "two"},
		},
		{
			name:     "fallback",
			raw:      "not json",
			wantType: contracts.PlannerActionUnknown,
			wantSQ:   []string{"prompt"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ParsePlannerTaskPlan(tt.raw, "prompt")
			if got == nil {
				t.Fatalf("ParsePlannerTaskPlan returned nil")
			}
			if got.ActionType != tt.wantType {
				t.Fatalf("ActionType=%q want %q", got.ActionType, tt.wantType)
			}
			if len(got.SearchQueries) != len(tt.wantSQ) {
				t.Fatalf("SearchQueries=%v want %v", got.SearchQueries, tt.wantSQ)
			}
			for i := range tt.wantSQ {
				if got.SearchQueries[i] != tt.wantSQ[i] {
					t.Fatalf("SearchQueries[%d]=%q want %q", i, got.SearchQueries[i], tt.wantSQ[i])
				}
			}
			if got.ContextBudget <= 0 {
				t.Fatalf("ContextBudget must be positive")
			}
		})
	}
}
