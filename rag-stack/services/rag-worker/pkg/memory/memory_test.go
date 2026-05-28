package memory

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"

	"app-builds/common/contracts"
	"github.com/stretchr/testify/assert"
)

type MockRoundTripper struct {
	roundTrip func(req *http.Request) (*http.Response, error)
}

func (m *MockRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	return m.roundTrip(req)
}

func TestRetrieve_Success(t *testing.T) {
	mockRT := &MockRoundTripper{
		roundTrip: func(req *http.Request) (*http.Response, error) {
			assert.Equal(t, "/retrieve", req.URL.Path)
			var payload map[string]interface{}
			bodyBytes, _ := io.ReadAll(req.Body)
			_ = json.Unmarshal(bodyBytes, &payload)
			assert.Equal(t, "FILE_EDIT", payload["action_type"])

			resp := contracts.MemoryPack{
				Items: []*contracts.MemoryWriteItem{
					{Content: "memory 1"},
					{Content: "memory 2"},
				},
			}
			body, _ := json.Marshal(&resp)
			return &http.Response{
				StatusCode: 200,
				Body:       io.NopCloser(bytes.NewBuffer(body)),
			}, nil
		},
	}

	client := &MemoryClient{
		url:    "http://localhost:8080",
		client: &http.Client{Transport: mockRT},
	}

	pack, err := client.Retrieve(context.Background(), 1, []int64{101}, "FILE_EDIT", "test query")

	assert.NoError(t, err)
	assert.Len(t, pack.Items, 2)
	assert.Equal(t, "memory 1", pack.Items[0].Content)
}

func TestRetrieve_Failure(t *testing.T) {
	mockRT := &MockRoundTripper{
		roundTrip: func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: 500,
				Body:       io.NopCloser(bytes.NewBufferString("error")),
			}, nil
		},
	}

	client := &MemoryClient{
		url:    "http://localhost:8080",
		client: &http.Client{Transport: mockRT},
	}

	pack, err := client.Retrieve(context.Background(), 1, nil, "UNKNOWN", "test query")

	assert.Error(t, err)
	assert.Nil(t, pack)
	assert.Contains(t, err.Error(), "status 500")
}
