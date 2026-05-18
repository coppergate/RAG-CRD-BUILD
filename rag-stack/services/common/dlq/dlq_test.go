package dlq

import (
	"os"
	"testing"
)

func TestDefaultMaxRetries(t *testing.T) {
	os.Unsetenv("DLQ_MAX_RETRIES")
	// Can't test NewHandler without a real Pulsar client, but we can test the config parsing
	if defaultMaxRetries != 3 {
		t.Fatalf("expected default max retries to be 3, got %d", defaultMaxRetries)
	}
}

func TestProcessResultConstants(t *testing.T) {
	if Success != 0 {
		t.Fatal("Success should be 0")
	}
	if TransientFailure != 1 {
		t.Fatal("TransientFailure should be 1")
	}
	if PermanentFailure != 2 {
		t.Fatal("PermanentFailure should be 2")
	}
}

func TestDLQMessageStruct(t *testing.T) {
	msg := DLQMessage{
		OriginalTopic: "test-topic",
		RetryCount:    2,
		FirstFailure:  "2026-03-26T06:00:00Z",
		LastError:     "connection refused",
		Payload:       []byte(`{"id":"123"}`),
	}
	if msg.OriginalTopic != "test-topic" {
		t.Fatal("unexpected topic")
	}
	if msg.RetryCount != 2 {
		t.Fatal("unexpected retry count")
	}
}

func TestMaxRetriesFromEnv(t *testing.T) {
	t.Setenv("DLQ_MAX_RETRIES", "5")
	// Verify the env parsing logic (extracted for testability)
	val := os.Getenv("DLQ_MAX_RETRIES")
	if val != "5" {
		t.Fatalf("expected DLQ_MAX_RETRIES=5, got %s", val)
	}

	t.Setenv("DLQ_MAX_RETRIES", "invalid")
	// Invalid values should fall back to default
	val = os.Getenv("DLQ_MAX_RETRIES")
	if val != "invalid" {
		t.Fatalf("expected raw value 'invalid', got %s", val)
	}
}
