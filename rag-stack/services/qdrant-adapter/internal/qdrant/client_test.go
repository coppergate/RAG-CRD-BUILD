package qdrant

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"testing"

	"app-builds/qdrant-adapter/internal/config"
	"github.com/stretchr/testify/assert"
)

type MockRoundTripper struct {
	roundTrip func(req *http.Request) (*http.Response, error)
}

func (m *MockRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	return m.roundTrip(req)
}

func TestSearch(t *testing.T) {
	cfg := &config.Config{
		QdrantHost: "localhost",
		QdrantPort: "6333",
	}

	mockRT := &MockRoundTripper{
		roundTrip: func(req *http.Request) (*http.Response, error) {
			assert.Equal(t, "/collections/test-coll-128/points/search", req.URL.Path)

			resp := map[string]interface{}{
				"result": []interface{}{
					map[string]interface{}{
						"id":      1,
						"payload": map[string]interface{}{"content": "test content"},
						"score":   0.9,
					},
				},
			}
			body, _ := json.Marshal(resp)
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBuffer(body)),
			}, nil
		},
	}

	client := &QdrantClient{
		cfg:        cfg,
		httpClient: &http.Client{Transport: mockRT},
	}

	results, err := client.Search("test-coll", 128, []float32{0.1, 0.2}, 10, nil, 0, false)

	assert.NoError(t, err)
	assert.Len(t, results, 1)
	res := results[0].(map[string]interface{})
	assert.Equal(t, "test content", res["content"])
}

func TestSearch_WithTagsAndSessionFilter(t *testing.T) {
	cfg := &config.Config{
		QdrantHost: "localhost",
		QdrantPort: "6333",
	}

	mockRT := &MockRoundTripper{
		roundTrip: func(req *http.Request) (*http.Response, error) {
			body, _ := io.ReadAll(req.Body)
			var payload map[string]interface{}
			err := json.Unmarshal(body, &payload)
			assert.NoError(t, err)

			filter, ok := payload["filter"].(map[string]interface{})
			if assert.True(t, ok) {
				_, hasMust := filter["must"].([]interface{})
				_, hasShould := filter["should"].([]interface{})
				assert.True(t, hasMust, "expected top-level must filter")
				assert.True(t, hasShould, "expected top-level should filter")
			}

			resp := map[string]interface{}{"result": []interface{}{}}
			respBody, _ := json.Marshal(resp)
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBuffer(respBody)),
			}, nil
		},
	}

	client := &QdrantClient{
		cfg:        cfg,
		httpClient: &http.Client{Transport: mockRT},
	}

	_, err := client.Search("test-coll", 128, []float32{0.1, 0.2}, 10, []int64{1, 2}, 42, true)
	assert.NoError(t, err)
}

func TestSearch_Failure(t *testing.T) {
	cfg := &config.Config{
		QdrantHost: "localhost",
		QdrantPort: "6333",
	}

	mockRT := &MockRoundTripper{
		roundTrip: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 500,
				Body:       io.NopCloser(bytes.NewBufferString("internal error")),
			}, nil
		},
	}

	client := &QdrantClient{
		cfg:        cfg,
		httpClient: &http.Client{Transport: mockRT},
	}

	results, err := client.Search("test-coll", 128, []float32{0.1, 0.2}, 10, nil, 0, false)

	assert.Error(t, err)
	assert.Nil(t, results)
	assert.Contains(t, err.Error(), "status 500")
}

func TestRetrieveByPaths(t *testing.T) {
	cfg := &config.Config{
		QdrantHost: "localhost",
		QdrantPort: "6333",
	}

	mockRT := &MockRoundTripper{
		roundTrip: func(req *http.Request) (*http.Response, error) {
			assert.Equal(t, "/collections/test-coll-128/points/scroll", req.URL.Path)

			resp := map[string]interface{}{
				"result": map[string]interface{}{
					"points": []interface{}{
						map[string]interface{}{
							"id":      "p1",
							"payload": map[string]interface{}{"path": "file1.txt", "content": "c1"},
						},
					},
				},
			}
			body, _ := json.Marshal(resp)
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBuffer(body)),
			}, nil
		},
	}

	client := &QdrantClient{
		cfg:        cfg,
		httpClient: &http.Client{Transport: mockRT},
	}

	results, err := client.RetrieveByPaths("test-coll", 128, []string{"file1.txt"}, 0)

	assert.NoError(t, err)
	assert.Len(t, results, 1)
}
