package granite31

import (
	"context"
	"strings"
	"testing"

	"app-builds/rag-worker/internal/models"
)

func TestExecutor_Execute(t *testing.T) {
	mock := &models.MockChatClient{
		ChatFunc: func(messages []map[string]string) (string, interface{}, error) {
			// Expect a system message followed by a user message now that
			// SystemInstruction is set on the granite31 config.
			if len(messages) != 2 {
				t.Fatalf("expected system + user messages (2 total), got %d", len(messages))
			}

			sysMsg := messages[0]
			if sysMsg["role"] != "system" {
				t.Fatalf("first message must be role=system, got %q", sysMsg["role"])
			}
			if !strings.Contains(sysMsg["content"], "strict extraction assistant") {
				t.Fatalf("system message missing extraction instruction: %q", sysMsg["content"])
			}

			userContent := messages[1]["content"]
			if !strings.Contains(userContent, "Context 1:") ||
				!strings.Contains(userContent, "User Query:") ||
				!strings.Contains(userContent, "Exact Answer:") {
				t.Fatalf("unexpected granite execution prompt: %q", userContent)
			}
			return "granite answer", nil, nil
		},
	}
	e := NewExecutor(mock)
	got, _, err := e.Execute(context.Background(), "my question", []interface{}{"some context"}, nil)
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
