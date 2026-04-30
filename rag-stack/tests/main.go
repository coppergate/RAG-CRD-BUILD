package main

import (
	"bytes"
	"crypto/rand"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var (
	baseURL     = "https://rag-admin-api.rag.hierocracy.home"
	sessionID   = ""
	sessionName = ""
	bucketName  = ""
	s3Index     = "e2eTestBucket"
	client      = &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
		Timeout: 30 * time.Second,
	}
)

func main() {
	tagName := fmt.Sprintf("test-tag-%d", time.Now().Unix())
	sessionID = generateUUID()
	sessionName = fmt.Sprintf("e2e-session-%d", time.Now().Unix())
	fmt.Printf("[%s] --- Starting E2E Test (Isolation) ---\n", time.Now().Format(time.RFC3339))
	fmt.Printf("Tag Name: %s\nSession ID: %s\nSession Name: %s\n", tagName, sessionID, sessionName)

	vectorSize := 4096 // Default for Llama 3.1
	if vs := os.Getenv("VECTOR_SIZE"); vs != "" {
		fmt.Sscanf(vs, "%d", &vectorSize)
	}
	fmt.Printf("Using vector_size: %d\n", vectorSize)

	// 0. Get Bucket Name
	fmt.Println("[STEP 0] Getting bucket name...")
	if err := getBucket(); err != nil {
		logFatal("Failed to get bucket name: %v", err)
	}
	fmt.Printf("Bucket: %s\n", bucketName)

	// 1. Create Tag
	fmt.Println("[STEP 1] Creating tag...")
	if err := createTag(tagName); err != nil {
		logFatal("Failed to create tag: %v", err)
	}
	time.Sleep(1 * time.Second)

	// 2. Get Tag ID
	fmt.Println("[STEP 2] Getting tag ID...")
	tagID, err := getTagID(tagName)
	if err != nil {
		logFatal("Failed to get tag ID: %v", err)
	}
	fmt.Printf("Tag ID: %s\n", tagID)

	// 3. Upload Test File
	fmt.Println("[STEP 3] Uploading test file...")
	baseFileName := fmt.Sprintf("e2e-test-file-%d.txt", time.Now().Unix())
	fileName := fmt.Sprintf("%s/%s", s3Index, baseFileName)
	timestamp := time.Now().Unix()
	secretCode := fmt.Sprintf("BLUE-ORCHID-%s", tagID[:8])
	fileContent := fmt.Sprintf("This is a secret code: %s. Generation timestamp: %d. This file is for RAG testing.", secretCode, timestamp)
	if err := uploadFile(fileName, fileContent); err != nil {
		logFatal("Failed to upload file: %v", err)
	}

	// 4. Trigger Ingestion
	fmt.Printf("[STEP 4] Triggering ingestion for tag %s (ID: %s) and session %s...\n", tagName, tagID, sessionID)
	if err := triggerIngest(tagID, vectorSize, fileName, sessionID); err != nil {
		logFatal("Failed to trigger ingestion: %v", err)
	}

	// 5 & 6. Wait for Ingestion and Verify via Ask
	fmt.Println("[STEP 5&6] Waiting for ingestion and verifying via RAG Query (up to 1m)...")
	
	start := time.Now()
	success := false
	var lastAnswer string
	for time.Since(start) < time.Minute {
		// Use a very specific query to ensure we are testing the isolation and the file we just uploaded.
		query := fmt.Sprintf("What is the secret code and its generation timestamp mentioned in the file %s? Provide the exact code and timestamp.", fileName)
		answer, askErr := askRAG(query, []string{tagID})
		if askErr == nil {
			lastAnswer = answer
			fmt.Printf("DEBUG: Received RAG Answer: %q\n", answer)
			// Tighten verification: should contain the code and be relatively short or focused
			upperAnswer := strings.ToUpper(answer)
			upperSecret := strings.ToUpper(secretCode)
			if strings.Contains(upperAnswer, upperSecret) {
				// Verify timestamp in answer if possible
				tsPattern := regexp.MustCompile(`(?i)timestamp\D*?(\d{10})`)
				match := tsPattern.FindStringSubmatch(answer)
				if match != nil {
					retrievedTS, _ := strconv.ParseInt(match[1], 10, 64)
					diff := time.Now().Unix() - retrievedTS
					if diff > 60 || diff < -60 {
						fmt.Printf("FAILURE: Found code but timestamp is stale. Diff: %ds\n", diff)
						logFatal("Secret code verification failed: timestamp stale (diff: %ds)", diff)
					}
					fmt.Printf("SUCCESS: Found secret code %s and valid timestamp (diff: %ds) in answer after %v!\n", secretCode, diff, time.Since(start))
				} else {
					fmt.Printf("FAILURE: Found code %s but NO timestamp in answer. Answer: %q\n", secretCode, answer)
					logFatal("Secret code verification failed: missing timestamp in answer")
				}
				
				fmt.Printf("RAG Answer: %s\n", answer)
				success = true
				break
			}
		}
		fmt.Printf("Waiting for ingestion... (elapsed: %v, last answer: %q)\n", time.Since(start).Round(time.Second), answer)
		time.Sleep(10 * time.Second)
	}

	if success {
		// --- Iteration 6b Extended Tests ---
		testIteration6b(sessionID, tagID, tagName, fileName, vectorSize)
	} else {
		fmt.Printf("FAILURE: Secret code not found in answer after 5 minutes. Last answer: %q\n", lastAnswer)
	}

	// 7. Cleanup (Delete Data)
	fmt.Println("[STEP 7] Cleaning up data by tag, session and S3...")
	if err := deleteData(tagID); err != nil {
		fmt.Printf("Warning: Failed to delete tag data: %v\n", err)
	}
	if err := deleteSession(sessionID); err != nil {
		fmt.Printf("Warning: Failed to delete session: %v\n", err)
	}
	if err := removeFileFromS3(fileName); err != nil {
		fmt.Printf("Warning: Failed to delete file from S3: %v\n", err)
	}

	// 8. Final Verification
	fmt.Println("[STEP 8] Final Verification (Checking if file is gone from S3)...")
	// Wait a few seconds for S3 eventual consistency
	time.Sleep(5 * time.Second)
	files, err := getFiles()
	found := false
	for _, f := range files {
		if f == fileName {
			found = true
			break
		}
	}
	if found {
		fmt.Println("FAILURE: Test file still exists in S3 after deletion.")
	} else {
		fmt.Println("SUCCESS: Test file removed from S3.")
	}

	fmt.Printf("[%s] --- E2E Test Completed ---\n", time.Now().Format(time.RFC3339))
}

func getBucket() error {
	bucketName = os.Getenv("BUCKET_NAME")
	if bucketName == "" {
		bucketName = "e2eTestBucket"
	}
	fmt.Printf("Using bucket: %s\n", bucketName)
	return nil
}

func getFiles() ([]string, error) {
	resp, err := client.Get(baseURL + "/api/s3/buckets/" + bucketName + "?prefix=" + s3Index)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var objects []struct {
		Key string `json:"Key"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&objects); err != nil {
		return nil, err
	}

	var files []string
	for _, o := range objects {
		files = append(files, o.Key)
	}
	return files, nil
}

func createTag(name string) error {
	payload := map[string]string{"name": name}
	body, _ := json.Marshal(payload)
	resp, err := client.Post(baseURL+"/api/db/tags", "application/json", bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func getTags() (map[string]string, error) {
	resp, err := client.Get(baseURL + "/api/db/tags")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var tagsList []struct {
		Id   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tagsList); err != nil {
		return nil, err
	}

	tags := make(map[string]string)
	for _, t := range tagsList {
			tags[t.Name] = t.Id
	}
	return tags, nil
}

func getTagID(name string) (string, error) {
	tags, err := getTags()
	if err != nil {
		return "", err
	}
	id, ok := tags[name]
	if !ok {
		return "", fmt.Errorf("tag %s not found", name)
	}
	return id, nil
}

func uploadFile(name, content string) error {
	url := fmt.Sprintf("%s/api/s3/buckets/%s/%s", baseURL, bucketName, name)
	req, err := http.NewRequest(http.MethodPut, url, strings.NewReader(content))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "text/plain")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func removeFileFromS3(name string) error {
	url := fmt.Sprintf("%s/api/s3/buckets/%s/%s", baseURL, bucketName, name)
	req, err := http.NewRequest(http.MethodDelete, url, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func triggerIngest(tagID string, vectorSize int, fileName string, sessionID string) error {
	payload := map[string]interface{}{
		"ingestion_id": tagID,
		"tag_ids":      []string{tagID},
		"tag_names":    []string{"E2E-Tag"},
		"vector_size":  vectorSize,
		"file_names":   []string{fileName},
		"session_id":   sessionID,
		"session_name": sessionName,
		"bucket_name":  bucketName,
		"index":        s3Index,
	}
	body, _ := json.Marshal(payload)
	resp, err := client.Post(baseURL+"/api/ingest/ingest", "application/json", bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusAccepted {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func askRAG(query string, tags []string) (string, error) {
	payload := map[string]interface{}{
		"prompt":       query,
		"tags":         tags,
		"session_id":   sessionID,
		"session_name": sessionName,
	}
	body, _ := json.Marshal(payload)
	resp, err := client.Post(baseURL+"/api/chat/v1/rag/chat", "application/json", bytes.NewBuffer(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Result string `json:"result"`
		Error  string `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("failed to decode RAG response: %v", err)
	}
	if result.Error != "" {
		return "", fmt.Errorf(result.Error)
	}
	return result.Result, nil
}

func deleteData(tagID string) error {
	req, err := http.NewRequest(http.MethodDelete, baseURL+"/api/db/tags/"+tagID, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func deleteSession(id string) error {
	req, err := http.NewRequest(http.MethodDelete, baseURL+"/api/db/sessions/"+id, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func logFatal(format string, v ...interface{}) {
	fmt.Printf(format+"\n", v...)
	os.Exit(1)
}

func generateUUID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}
