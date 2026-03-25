package llama3

import (
	"context"
	"reflect"
	"testing"
	"app-builds/rag-worker/internal/models"
)

func TestPlanner_Plan(t *testing.T) {
	tests := []struct {
		name       string
		planResult string
		want       []string
		wantErr    bool
	}{
		{
			name:       "valid json array",
			planResult: `["query 1", "query 2"]`,
			want:       []string{"query 1", "query 2"},
			wantErr:    false,
		},
		{
			name:       "json with markdown",
			planResult: "Here is the plan: ```json\n[\"query 1\", \"query 2\"]\n```",
			want:       []string{"query 1", "query 2"},
			wantErr:    false,
		},
		{
			name:       "invalid json",
			planResult: "invalid",
			want:       []string{"original prompt"}, // fallback to original prompt
			wantErr:    false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mock := &models.MockChatClient{
				ChatFunc: func(messages []map[string]string) (string, error) {
					return tt.planResult, nil
				},
			}
			p := NewPlanner(mock)
			got, err := p.Plan(context.Background(), "original prompt")
			if (err != nil) != tt.wantErr {
				t.Errorf("Planner.Plan() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("Planner.Plan() = %v, want %v", got, tt.want)
			}
		})
	}
}
