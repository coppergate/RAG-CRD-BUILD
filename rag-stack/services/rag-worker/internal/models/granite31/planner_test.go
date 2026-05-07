package granite31

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
			planResult: `["granite query 1", "granite query 2"]`,
			want:       []string{"granite query 1", "granite query 2"},
			wantErr:    false,
		},
		{
			name:       "empty response",
			planResult: "",
			want:       []string{"original prompt"},
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
			got, _, err := p.Plan(context.Background(), "original prompt")
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
