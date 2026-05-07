package granite31

import (
	"context"
	"testing"

	"app-builds/rag-worker/internal/models"
)

func TestExecutor_Execute(t *testing.T) {
	mock := &models.MockChatClient{
		ChatFunc: func(messages []map[string]string) (string, interface{}, error) {
			return "granite answer", nil, nil
		},
	}
	e := NewExecutor(mock)
	got, _, err := e.Execute(context.Background(), "my question", []interface{}{"some context"})
	if err != nil {
		t.Fatalf("Executor.Execute() error = %v", err)
	}
	if got != "granite answer" {
		t.Errorf("Executor.Execute() = %v, want %v", got, "granite answer")
	}
}

func TestExecutor_IsInsufficientContext(t *testing.T) {
        e := NewExecutor(nil)
        tests := []struct {
		result string
		want   bool
	}{
		{"Some context here.", false},
		{"insufficient context", true},
		{"I don't have enough information", true},
		{"NOT MENTIONED IN THE CONTEXT", true},
		{"valid info", false},
	}
	for _, tt := range tests {
		if got := e.IsInsufficientContext(tt.result); got != tt.want {
			t.Errorf("IsInsufficientContext(%q) = %v, want %v", tt.result, got, tt.want)
		}
	}
}
