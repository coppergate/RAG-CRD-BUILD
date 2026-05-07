package llama3

import (
	"context"
	"strings"
	"testing"
	"app-builds/rag-worker/internal/models"
)

func TestExecutor_Execute(t *testing.T) {
	mock := &models.MockChatClient{
		ChatFunc: func(messages []map[string]string) (string, interface{}, error) {
			content := messages[0]["content"]
			if strings.Contains(content, "Query: my question") {
				return "my answer", nil, nil
			}
			return "wrong answer", nil, nil
		},
	}
	e := NewExecutor(mock)
	got, _, err := e.Execute(context.Background(), "my question", []interface{}{"some context"})
	if err != nil {
		t.Fatalf("Executor.Execute() error = %v", err)
	}
	if got != "my answer" {
		t.Errorf("Executor.Execute() = %v, want %v", got, "my answer")
	}
}

func TestExecutor_IsInsufficientContext(t *testing.T) {
        e := NewExecutor(nil)
        tests := []struct {
		result string
		want   bool
	}{
		{"I don't know.", false},
		{"{\"insufficient_context\": true}", true},
		{"this is an insufficient context message", true},
		{"some valid info", false},
	}
	for _, tt := range tests {
		if got := e.IsInsufficientContext(tt.result); got != tt.want {
			t.Errorf("IsInsufficientContext(%q) = %v, want %v", tt.result, got, tt.want)
		}
	}
}
