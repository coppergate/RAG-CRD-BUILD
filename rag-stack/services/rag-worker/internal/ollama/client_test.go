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

func TestIsUnsupportedEmbeddingModelError(t *testing.T) {
	err := &APIStatusError{
		Operation:  "embeddings",
		URL:        "http://ollama",
		StatusCode: http.StatusBadRequest,
		Body:       "this model does not support embeddings",
	}
	if !IsUnsupportedEmbeddingModelError(err) {
		t.Fatal("expected unsupported embedding response to be classified")
	}
}

func TestIsUnsupportedEmbeddingModelError_NonMatch(t *testing.T) {
	err := &APIStatusError{
		Operation:  "embeddings",
		URL:        "http://ollama",
		StatusCode: http.StatusBadGateway,
		Body:       "upstream unavailable",
	}
	if IsUnsupportedEmbeddingModelError(err) {
		t.Fatal("expected unrelated status error to not be classified as unsupported embeddings")
	}
}
