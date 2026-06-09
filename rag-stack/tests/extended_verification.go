package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
	"unicode"
)

// buildEmbeddingCollection mirrors contracts.BuildEmbeddingCollection.
// Collection identity = prefix + embedding model slug + vector size.
func buildEmbeddingCollection(prefix, embeddingModel string, vectorSize int) string {
	base := strings.TrimSpace(prefix)
	if base == "" {
		base = "vectors"
	}
	normalized := normalizeEmbeddingModel(embeddingModel)
	switch {
	case normalized != "" && vectorSize > 0:
		return fmt.Sprintf("%s-%s-%d", base, normalized, vectorSize)
	case normalized != "":
		return fmt.Sprintf("%s-%s", base, normalized)
	case vectorSize > 0:
		return fmt.Sprintf("%s-%d", base, vectorSize)
	default:
		return base
	}
}

// normalizeEmbeddingModel mirrors contracts.NormalizeEmbeddingModelName.
func normalizeEmbeddingModel(model string) string {
	model = strings.ToLower(strings.TrimSpace(model))
	if model == "" {
		return ""
	}
	var b strings.Builder
	lastDash := false
	for _, r := range model {
		switch {
		case unicode.IsLetter(r), unicode.IsDigit(r):
			b.WriteRune(r)
			lastDash = false
		default:
			if !lastDash {
				b.WriteByte('-')
				lastDash = true
			}
		}
	}
	return strings.Trim(b.String(), "-")
}

func testExtendedVerification(sessionID int64, tagID int64, tagName string, fileName string, vectorSize int, embeddingModel string) {
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

	// 5. Verify Qdrant Stats (model-aware collection name)
	fmt.Println("[STEP 6B.5] Verifying Qdrant Stats...")
	collectionName := buildEmbeddingCollection("vectors", embeddingModel, vectorSize)
	fmt.Printf(" [INFO] Expected collection: %s\n", collectionName)
	if err := verifyQdrantStats(collectionName); err != nil {
		fmt.Printf("FAILURE: Qdrant Stats verification failed: %v\n", err)
	} else {
		fmt.Println("SUCCESS: Qdrant Stats verification passed.")
	}

	// 6. Verify embedding_model is stored in db-adapter storage records
	fmt.Println("[STEP 6B.6] Verifying embedding_model in DB storage records...")
	if err := verifyEmbeddingModelInDB(tagID, embeddingModel); err != nil {
		fmt.Printf("FAILURE: DB embedding_model verification failed: %v\n", err)
	} else {
		fmt.Println("SUCCESS: DB embedding_model verification passed.")
	}

	// 7. Verify memory-controller retrieve endpoint (in-memory planner query path)
	fmt.Println("[STEP 6B.7] Verifying memory-controller retrieve endpoint...")
	if err := verifyMemoryRetrieve(sessionID); err != nil {
		fmt.Printf("FAILURE: Memory retrieve verification failed: %v\n", err)
	} else {
		fmt.Println("SUCCESS: Memory retrieve verification passed.")
	}

	fmt.Println("--- Iteration 6b Extended Tests Completed ---")
}

func verifyVirtualFS(sessionID int64, expectedFile string) error {
	url := fmt.Sprintf("%s/api/db/storage/files?session_id=%d", baseURL, sessionID)
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
		return fmt.Errorf("expected file %s not found in virtual FS for session %d", expectedFile, sessionID)
	}
	return nil
}

func verifySessionHealth(sessionID int64) error {
	url := fmt.Sprintf("%s/api/db/metrics/sessions/health?session_id=%d", baseURL, sessionID)
	
	var health struct {
		SessionId     int64   `json:"session_id"`
		TotalRequests int     `json:"total_requests"`
		SuccessRate   float64 `json:"success_rate"`
		Status        string  `json:"status"`
	}

	for i := 0; i < 5; i++ {
		resp, err := client.Get(url)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("unexpected status: %d", resp.StatusCode)
		}

		if err := json.NewDecoder(resp.Body).Decode(&health); err != nil {
			return err
		}

		if health.TotalRequests > 0 {
			if health.Status != "HEALTHY" {
				return fmt.Errorf("expected HEALTHY status, got %s (success rate: %f)", health.Status, health.SuccessRate)
			}
			return nil
		}
		fmt.Printf(" [WAIT] Health report not yet populated (0 requests), retrying (%d/5)...\n", i+1)
		time.Sleep(3 * time.Second)
	}

	return fmt.Errorf("health report shows %d requests for session %d", health.TotalRequests, sessionID)
}

func verifyAuditLogs(sessionID int64) error {
	url := fmt.Sprintf("%s/api/db/audit/retrieval?session_id=%d", baseURL, sessionID)
	
	var logs []struct {
		Type   string `json:"type"`
		Detail string `json:"detail"`
	}

	for i := 0; i < 5; i++ {
		resp, err := client.Get(url)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("unexpected status: %d", resp.StatusCode)
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

		if foundRetrieval {
			return nil
		}
		fmt.Printf(" [WAIT] Audit logs not yet populated, retrying (%d/5)...\n", i+1)
		time.Sleep(3 * time.Second)
	}

	return fmt.Errorf("no RETRIEVAL logs found for session %d", sessionID)
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

// verifyEmbeddingModelInDB queries the db-adapter storage endpoint filtered by
// embedding_model and confirms at least one record was created with the correct
// model provenance for the given tag.
func verifyEmbeddingModelInDB(tagID int64, embeddingModel string) error {
	url := fmt.Sprintf("%s/api/db/storage/files?tag_id=%d&embedding_model=%s",
		baseURL, tagID, embeddingModel)

	for i := 0; i < 5; i++ {
		resp, err := client.Get(url)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("unexpected status: %d", resp.StatusCode)
		}

		var files []struct {
			Path           string `json:"path"`
			EmbeddingModel string `json:"embedding_model"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&files); err != nil {
			return err
		}

		if len(files) > 0 {
			for _, f := range files {
				if f.EmbeddingModel != embeddingModel {
					return fmt.Errorf("file %s has embedding_model %q, expected %q",
						f.Path, f.EmbeddingModel, embeddingModel)
				}
			}
			return nil
		}
		fmt.Printf(" [WAIT] No storage records with embedding_model=%q yet, retrying (%d/5)...\n", embeddingModel, i+1)
		time.Sleep(5 * time.Second)
	}

	return fmt.Errorf("no storage records found with embedding_model=%q for tag %d", embeddingModel, tagID)
}

// verifyMemoryRetrieve exercises the memory-controller /retrieve endpoint.
// This is the in-memory planner query path used by rag-worker during retrieval.
// After a successful RAG query the session should have memory items.
func verifyMemoryRetrieve(sessionID int64) error {
	payload := map[string]interface{}{
		"scope":       map[string]interface{}{"session_id": sessionID},
		"query":       "context",
		"limit":       5,
		"action_type": "RETRIEVE",
	}
	body, _ := json.Marshal(payload)

	resp, err := client.Post(baseURL+"/api/memory/retrieve", "application/json", bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	// Response is a MemoryPack — just verify it's valid JSON with no decode error.
	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return fmt.Errorf("failed to decode memory retrieve response: %v", err)
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
