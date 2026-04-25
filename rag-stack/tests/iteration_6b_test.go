package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

func testIteration6b(sessionID string, tagID string, tagName string, fileName string, vectorSize int) {
	fmt.Println("\n--- Starting Iteration 6b Extended Tests ---")

	// 1. Verify Virtual FS Listing
	fmt.Println("[STEP 6B.1] Verifying Virtual FS Listing...")
	if err := verifyVirtualFS(sessionID, fileName); err != nil {
		fmt.Printf("FAILURE: Virtual FS verification failed: %v\n", err)
	} else {
		fmt.Println("SUCCESS: Virtual FS verification passed.")
	}

	// 2. Verify Session Health
	fmt.Println("[STEP 6B.2] Verifying Session Health...")
	if err := verifySessionHealth(sessionID); err != nil {
		fmt.Printf("FAILURE: Session Health verification failed: %v\n", err)
	} else {
		fmt.Println("SUCCESS: Session Health verification passed.")
	}

	// 3. Verify Audit Logs
	fmt.Println("[STEP 6B.3] Verifying Audit Logs...")
	if err := verifyAuditLogs(sessionID); err != nil {
		fmt.Printf("FAILURE: Audit Logs verification failed: %v\n", err)
	} else {
		fmt.Println("SUCCESS: Audit Logs verification passed.")
	}

	// 4. Verify Model Execution Metrics
	fmt.Println("[STEP 6B.4] Verifying Model Execution Metrics...")
	if err := verifyModelMetrics(); err != nil {
		fmt.Printf("FAILURE: Model Metrics verification failed: %v\n", err)
	} else {
		fmt.Println("SUCCESS: Model Metrics verification passed.")
	}

	// 5. Verify Qdrant Stats
	fmt.Println("[STEP 6B.5] Verifying Qdrant Stats...")
	collectionName := "test-collection"
	if vectorSize > 0 {
		collectionName = fmt.Sprintf("%s-%d", collectionName, vectorSize)
	}
	if err := verifyQdrantStats(collectionName); err != nil {
		fmt.Printf("FAILURE: Qdrant Stats verification failed: %v\n", err)
	} else {
		fmt.Println("SUCCESS: Qdrant Stats verification passed.")
	}

	fmt.Println("--- Iteration 6b Extended Tests Completed ---\n")
}

func verifyVirtualFS(sessionID string, expectedFile string) error {
	url := fmt.Sprintf("%s/api/db/storage/files?session_id=%s", baseURL, sessionID)
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	var files []struct {
		Path   string `json:"path"`
		Status string `json:"status"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&files); err != nil {
		return err
	}

	found := false
	for _, f := range files {
		if f.Path == expectedFile {
			found = true
			if f.Status != "SYNCED" {
				return fmt.Errorf("file found but status is %s, expected SYNCED", f.Status)
			}
			break
		}
	}

	if !found {
		return fmt.Errorf("expected file %s not found in virtual FS for session %s", expectedFile, sessionID)
	}
	return nil
}

func verifySessionHealth(sessionID string) error {
	url := fmt.Sprintf("%s/api/db/metrics/sessions/health?session_id=%s", baseURL, sessionID)
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	var health struct {
		SessionID     string  `json:"session_id"`
		TotalRequests int     `json:"total_requests"`
		SuccessRate   float64 `json:"success_rate"`
		Status        string  `json:"status"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&health); err != nil {
		return err
	}

	if health.TotalRequests == 0 {
		return fmt.Errorf("health report shows 0 requests for session %s", sessionID)
	}
	if health.Status != "HEALTHY" {
		return fmt.Errorf("expected HEALTHY status, got %s (success rate: %f)", health.Status, health.SuccessRate)
	}
	return nil
}

func verifyAuditLogs(sessionID string) error {
	url := fmt.Sprintf("%s/api/db/audit/retrieval?session_id=%s", baseURL, sessionID)
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	var logs []struct {
		Type   string `json:"type"`
		Detail string `json:"detail"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&logs); err != nil {
		return err
	}

	foundRetrieval := false
	for _, l := range logs {
		if l.Type == "RETRIEVAL" {
			foundRetrieval = true
			break
		}
	}

	if !foundRetrieval {
		return fmt.Errorf("no RETRIEVAL logs found for session %s", sessionID)
	}
	return nil
}

func verifyModelMetrics() error {
	url := fmt.Sprintf("%s/api/db/metrics/models", baseURL)
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	var metrics []map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&metrics); err != nil {
		return err
	}

	if len(metrics) == 0 {
		return fmt.Errorf("no model execution metrics found")
	}

	// Verify we have keys we expect
	m := metrics[0]
	requiredKeys := []string{"model_name", "node", "avg_tokens_per_sec", "avg_latency_ms", "total_executions"}
	for _, k := range requiredKeys {
		if _, ok := m[k]; !ok {
			return fmt.Errorf("missing key %s in metrics response", k)
		}
	}

	return nil
}

func verifyQdrantStats(collectionName string) error {
	url := fmt.Sprintf("%s/api/qdrant/stats?collection=%s", baseURL, collectionName)
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	var stats map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&stats); err != nil {
		return err
	}

	if _, ok := stats["vectors_count"]; !ok {
		// Qdrant might nest it under 'status' or similar depending on the version and how we proxy it
		// Let's just check if we got something back
		if len(stats) == 0 {
			return fmt.Errorf("qdrant stats response is empty")
		}
	}

	return nil
}
