package clients

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"time"

	"app-builds/common/contracts"
	"google.golang.org/protobuf/encoding/protojson"
)

type QdrantClient interface {
	Search(ctx context.Context, op *contracts.QdrantOp) (*contracts.QdrantResponse, error)
}

type QdrantHTTPClient struct {
	baseURL    string
	httpClient *http.Client
}

func NewQdrantHTTPClient(baseURL string) *QdrantHTTPClient {
	return &QdrantHTTPClient{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (c *QdrantHTTPClient) Search(ctx context.Context, op *contracts.QdrantOp) (*contracts.QdrantResponse, error) {
	return c.doRequest(ctx, "/search", op)
}

func (c *QdrantHTTPClient) doRequest(ctx context.Context, path string, op *contracts.QdrantOp) (*contracts.QdrantResponse, error) {
	marshaller := protojson.MarshalOptions{
		UseProtoNames: true,
	}
	payload, err := marshaller.Marshal(op)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal qdrant op: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+path, bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("qdrant request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("qdrant request failed with status %d: %s", resp.StatusCode, string(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	var qdrantResp contracts.QdrantResponse
	if err := protojson.Unmarshal(body, &qdrantResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return &qdrantResp, nil
}
