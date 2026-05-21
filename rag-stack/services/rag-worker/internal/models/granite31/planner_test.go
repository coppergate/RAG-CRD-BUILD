package granite31

import (
	"context"
	"reflect"
	"testing"

	"app-builds/common/contracts"
	"app-builds/rag-worker/internal/models"
)

func TestPlanner_Plan(t *testing.T) {
	tests := []struct {
		name       string
		planResult string
		wantQuery  []string
		wantAction string
		wantErr    bool
	}{
		{
			name:       "valid json object",
			planResult: `{"objective":"original prompt","action_type":"FILE_SEARCH","search_queries":["granite query 1","granite query 2"],"context_budget":3}`,
			wantQuery:  []string{"granite query 1", "granite query 2"},
			wantAction: "FILE_SEARCH",
			wantErr:    false,
		},
		{
			name:       "empty response",
			planResult: "",
			wantQuery:  []string{"original prompt"},
			wantAction: contracts.PlannerActionUnknown,
			wantErr:    false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mock := &models.MockChatClient{
				ChatFunc: func(messages []map[string]string) (string, interface{}, error) {
					return tt.planResult, nil, nil
				},
			}
			p := NewPlanner(mock)
			got, _, err := p.Plan(context.Background(), "original prompt", nil, nil)
			if (err != nil) != tt.wantErr {
				t.Errorf("Planner.Plan() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got == nil {
				t.Fatalf("Planner.Plan() returned nil plan")
			}
			if got.ActionType != tt.wantAction {
				t.Errorf("Planner.Plan().ActionType = %v, want %v", got.ActionType, tt.wantAction)
			}
			if !reflect.DeepEqual(got.SearchQueries, tt.wantQuery) {
				t.Errorf("Planner.Plan().SearchQueries = %v, want %v", got.SearchQueries, tt.wantQuery)
			}
		})
	}
}
