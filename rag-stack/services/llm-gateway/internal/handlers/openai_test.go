package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"app-builds/common/ent/enttest"
	"app-builds/llm-gateway/internal/pulsar"

	_ "github.com/mattn/go-sqlite3"
)

type mockPulsarClient struct {
	SendRequestFunc     func(ctx context.Context, id string, payload interface{}) (string, error)
	SendPromptEventFunc func(ctx context.Context, id string, sessionID int64, content string) error
	SubscribeStreamFunc func(id string, ch chan pulsar.StreamChunk)
	UnsubscribeStreamFunc func(id string)
	SendRawRequestFunc  func(ctx context.Context, payload interface{}) error
}

func (m *mockPulsarClient) SendRequest(ctx context.Context, id string, payload interface{}) (string, error) {
	return m.SendRequestFunc(ctx, id, payload)
}
func (m *mockPulsarClient) SendPromptEvent(ctx context.Context, id string, sessionID int64, content string) error {
	return m.SendPromptEventFunc(ctx, id, sessionID, content)
}
func (m *mockPulsarClient) SubscribeStream(id string, ch chan pulsar.StreamChunk) {
	m.SubscribeStreamFunc(id, ch)
}
func (m *mockPulsarClient) UnsubscribeStream(id string) {
	m.UnsubscribeStreamFunc(id)
}
func (m *mockPulsarClient) SendRawRequest(ctx context.Context, payload interface{}) error {
	return m.SendRawRequestFunc(ctx, payload)
}
func (m *mockPulsarClient) Close() {}
func (m *mockPulsarClient) Ping() error { return nil }

func TestHandleChatCompletions(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	mockPulsar := &mockPulsarClient{
		SendRequestFunc: func(ctx context.Context, id string, payload interface{}) (string, error) {
			return "Hello from mock", nil
		},
		SendPromptEventFunc: func(ctx context.Context, id string, sessionID int64, content string) error {
			return nil
		},
	}

	h := &OpenAIHandler{
		Pulsar: mockPulsar,
		Ent:    client,
	}

	reqBody := ChatCompletionRequest{
		Model: "gpt-mock",
		Messages: []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		}{
			{Role: "user", Content: "Hello"},
		},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", bytes.NewReader(body))
	w := httptest.NewRecorder()

	h.HandleChatCompletions(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %v", w.Code)
	}

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)

	choices := resp["choices"].([]interface{})
	firstChoice := choices[0].(map[string]interface{})
	message := firstChoice["message"].(map[string]interface{})
	if message["content"] != "Hello from mock" {
		t.Errorf("Expected content 'Hello from mock', got %v", message["content"])
	}
}

func TestHandleGenericChat(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	mockPulsar := &mockPulsarClient{
		SendRequestFunc: func(ctx context.Context, id string, payload interface{}) (string, error) {
			return "Generic answer", nil
		},
	}

	h := &OpenAIHandler{
		Pulsar: mockPulsar,
		Ent:    client,
	}

	reqBody := GenericChatRequest{
		Prompt: "Tell me a joke",
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/v1/rag/chat", bytes.NewReader(body))
	w := httptest.NewRecorder()

	h.HandleGenericChat(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %v", w.Code)
	}

	var resp map[string]interface{}
	json.NewDecoder(w.Body).Decode(&resp)

	if resp["result"] != "Generic answer" {
		t.Errorf("Expected result 'Generic answer', got %v", resp["result"])
	}
}
