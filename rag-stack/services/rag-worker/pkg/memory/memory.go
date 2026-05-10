package memory

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"app-builds/common/contracts"
)

type MemoryClient struct {
	url    string
	client *http.Client
}

func NewMemoryClient(url string) *MemoryClient {
	return &MemoryClient{
		url: url,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (m *MemoryClient) Retrieve(ctx context.Context, sessionID int64, tags []int64, query string) (*contracts.MemoryPack, error) {
	req := contracts.MemoryRetrieveRequest{
		RequestId:     fmt.Sprintf("ret-%d", time.Now().UnixNano()),
		CorrelationId: fmt.Sprintf("corr-%d", time.Now().UnixNano()),
		Scope: &contracts.MemoryScope{
			SessionId: sessionID,
			Tags:      tags,
		},
		Query: query,
		Limit: 10,
	}
	if len(tags) > 0 {
		req.Limit = 100
	}

	body, err := json.Marshal(&req)
	if err != nil {
		return nil, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", m.url+"/retrieve", bytes.NewBuffer(body))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := m.client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("memory-controller returned status %d", resp.StatusCode)
	}

	var pack contracts.MemoryPack
	if err := json.NewDecoder(resp.Body).Decode(&pack); err != nil {
		return nil, err
	}

	return &pack, nil
}

func (m *MemoryClient) AuditRuleApplication(ctx context.Context, promptID string, ruleID int64, actionType string, metadata map[string]interface{}) error {
	req := struct {
		PromptID   string                 `json:"prompt_id"`
		RuleID     int64                  `json:"rule_id"`
		ActionType string                 `json:"action_type"`
		Context    map[string]interface{} `json:"context"`
	}{
		PromptID:   promptID,
		RuleID:     ruleID,
		ActionType: actionType,
		Context:    metadata,
	}

	body, err := json.Marshal(&req)
	if err != nil {
		return err
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", m.url+"/behavior/audit", bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := m.client.Do(httpReq)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted && resp.StatusCode != http.StatusOK {
		return fmt.Errorf("memory-controller audit returned status %d", resp.StatusCode)
	}

	return nil
}

func (m *MemoryClient) GetActionIdentifiers(ctx context.Context) (map[string][]string, error) {
	httpReq, err := http.NewRequestWithContext(ctx, "GET", m.url+"/behavior/identifiers", nil)
	if err != nil {
		return nil, err
	}

	resp, err := m.client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("memory-controller identifiers returned status %d", resp.StatusCode)
	}

	var result map[string][]string
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	return result, nil
}
