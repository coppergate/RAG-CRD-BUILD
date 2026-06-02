package models

import (
	"strings"
	"testing"

	"app-builds/common/contracts"
)

func TestAssembleMessagesPreservesMemoryControllerOrder(t *testing.T) {
	model := &GenericModel{
		Config: ModelConfig{
			ExecutionHeader:        "CTX:\n",
			ExecutionFooter:        "\nPROMPT:\n",
			ExecutionSuffix:        "\n",
			PlanningPromptTemplate: "%s",
		},
	}

	history := []interface{}{
		&contracts.MemoryWriteItem{
			MemoryType: "behavioral_rule",
			Content:    "Use concise diffs.",
			Metadata: contracts.ToStruct(map[string]interface{}{
				"context_bucket": "behavioral_rules",
				"role":           "system",
			}),
		},
		&contracts.MemoryWriteItem{
			MemoryType: "task_local_retrieval",
			Content:    "Relevant local context.",
			Metadata: contracts.ToStruct(map[string]interface{}{
				"context_bucket": "task_local_retrieval",
				"role":           "system",
			}),
		},
		&contracts.MemoryWriteItem{
			MemoryType: "chat_history",
			Content:    "Prior user question.",
			Metadata: contracts.ToStruct(map[string]interface{}{
				"context_bucket": "episodic_history",
				"role":           "user",
			}),
		},
		&contracts.MemoryWriteItem{
			MemoryType: "chat_history",
			Content:    "Prior assistant response.",
			Metadata: contracts.ToStruct(map[string]interface{}{
				"context_bucket": "episodic_history",
				"role":           "assistant",
			}),
		},
	}

	messages := model.assembleMessages("Current task", nil, history)
	if len(messages) != 5 {
		t.Fatalf("expected 5 messages, got %d", len(messages))
	}

	if messages[0]["role"] != "system" || messages[0]["content"] != "Use concise diffs." {
		t.Fatalf("unexpected first message: %#v", messages[0])
	}
	if messages[1]["role"] != "system" || messages[1]["content"] != "Relevant local context." {
		t.Fatalf("unexpected second message: %#v", messages[1])
	}
	if messages[2]["role"] != "user" || messages[2]["content"] != "Prior user question." {
		t.Fatalf("unexpected third message: %#v", messages[2])
	}
	if messages[3]["role"] != "assistant" || messages[3]["content"] != "Prior assistant response." {
		t.Fatalf("unexpected fourth message: %#v", messages[3])
	}
	if messages[4]["role"] != "user" || messages[4]["content"] != "\nPROMPT:\nCurrent task\n" {
		t.Fatalf("unexpected final prompt message: %#v", messages[4])
	}
}

func TestAssembleMessagesPlacesRetrievedContextInUserPrompt(t *testing.T) {
	model := &GenericModel{
		Config: ModelConfig{
			ExecutionHeader:        "CTX:\n",
			ExecutionFooter:        "\nPROMPT:\n",
			ExecutionSuffix:        "\n",
			PlanningPromptTemplate: "%s",
		},
	}

	messages := model.assembleMessages("Answer the question.", []interface{}{"first chunk", "second chunk"}, nil)
	if len(messages) != 1 {
		t.Fatalf("expected 1 message, got %d", len(messages))
	}
	if messages[0]["role"] != "user" {
		t.Fatalf("expected user message, got %#v", messages[0])
	}
	if !strings.Contains(messages[0]["content"], "first chunk") || !strings.Contains(messages[0]["content"], "second chunk") {
		t.Fatalf("user message did not include retrieved context: %#v", messages[0])
	}
	if !strings.Contains(messages[0]["content"], "\nPROMPT:\nAnswer the question.\n") {
		t.Fatalf("unexpected user message: %#v", messages[0])
	}
}

func TestBuildTaggedExecutionPrompt(t *testing.T) {
	config := ModelConfig{
		ExecutionHeader: "CTX:\n",
		ExecutionFooter: "\nPROMPT:\n",
		ExecutionSuffix: "\n",
	}
	got := BuildTaggedExecutionPrompt(config, "Answer the question.", []interface{}{"first chunk", "second chunk"})
	if !strings.Contains(got, "<<<CONTEXT 1>>>") || !strings.Contains(got, "<<<END CONTEXT 2>>>") {
		t.Fatalf("tagged prompt did not include context delimiters: %q", got)
	}
	if !strings.Contains(got, "first chunk") || !strings.Contains(got, "second chunk") {
		t.Fatalf("tagged prompt did not preserve context text: %q", got)
	}
	if !strings.Contains(got, "\nPROMPT:\nAnswer the question.\n") {
		t.Fatalf("tagged prompt did not include footer/suffix: %q", got)
	}
}

func TestBuildNumberedExecutionPrompt(t *testing.T) {
	config := ModelConfig{
		ExecutionHeader: "CTX:\n",
		ExecutionFooter: "\nPROMPT:\n",
		ExecutionSuffix: "\n",
	}
	got := BuildNumberedExecutionPrompt(config, "Answer the question.", []interface{}{"first chunk", "second chunk"})
	if !strings.Contains(got, "Context 1:") || !strings.Contains(got, "Context 2:") {
		t.Fatalf("numbered prompt did not include numbered context sections: %q", got)
	}
	if !strings.Contains(got, "first chunk") || !strings.Contains(got, "second chunk") {
		t.Fatalf("numbered prompt did not preserve context text: %q", got)
	}
	if !strings.Contains(got, "\nPROMPT:\nAnswer the question.\n") {
		t.Fatalf("numbered prompt did not include footer/suffix: %q", got)
	}
}
