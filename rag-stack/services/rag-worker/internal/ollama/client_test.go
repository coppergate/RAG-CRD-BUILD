package ollama

import (
	"net/http"
	"testing"
)

func TestIsMissingModelError(t *testing.T) {
	err := &APIStatusError{Operation: "chat", URL: "http://ollama", StatusCode: http.StatusNotFound}
	if !IsMissingModelError(err) {
		t.Fatal("expected 404 status error to be classified as missing model")
	}
}

func TestIsMissingModelError_Non404(t *testing.T) {
	err := &APIStatusError{Operation: "chat", URL: "http://ollama", StatusCode: http.StatusBadGateway}
	if IsMissingModelError(err) {
		t.Fatal("expected non-404 status error to not be classified as missing model")
	}
}
