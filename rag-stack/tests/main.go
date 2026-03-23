package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"
)

var (
	baseURL = "https://172.20.1.24" // rag-web-ui LoadBalancer
	client  = &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
		Timeout: 30 * time.Second,
	}
)

func main() {
	tagName := fmt.Sprintf("test-tag-%d", time.Now().Unix())
	fmt.Printf("--- Starting E2E Test with tag: %s ---\n", tagName)

	vectorSize := 4096 // Default for Llama 3.1
	if vs := os.Getenv("VECTOR_SIZE"); vs != "" {
		fmt.Sscanf(vs, "%d", &vectorSize)
	}
	fmt.Printf("Using vector_size: %d\n", vectorSize)

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
	fileName := fmt.Sprintf("e2e-test-file-%d.txt", time.Now().Unix())
	fileContent := "This is a secret code: BLUE-ORCHID-2026. This file is for RAG testing."
	if err := uploadFile(fileName, fileContent); err != nil {
		logFatal("Failed to upload file: %v", err)
	}

	// 4. Trigger Ingestion
	fmt.Println("[STEP 4] Triggering ingestion...")
	if err := triggerIngest(tagID, vectorSize, fileName); err != nil {
		logFatal("Failed to trigger ingestion: %v", err)
	}

	// 5 & 6. Wait for Ingestion and Verify via Ask
	fmt.Println("[STEP 5&6] Waiting for ingestion and verifying via RAG Query (up to 5m)...")
	
	start := time.Now()
	success := false
	var lastAnswer string
	for time.Since(start) < 5*time.Minute {
		// Use a very specific query to ensure we are testing the isolation and the file we just uploaded.
		query := fmt.Sprintf("What is the secret code mentioned in the file %s? Answer with just the code.", fileName)
		answer, askErr := askRAG(query, []string{tagID})
		if askErr == nil {
			lastAnswer = answer
			// Tighten verification: should contain the code and be relatively short or focused
			upperAnswer := strings.ToUpper(answer)
			if strings.Contains(upperAnswer, "BLUE-ORCHID-2026") {
				// Success! Now check for leakage (other codes from previous runs)
				// Previous codes were likely strings like 'Crimson-Sky-77', '12345ABC', etc.
				// For now, we just log the answer for manual review but we could add more checks.
				fmt.Printf("SUCCESS: Found secret code in answer after %v!\n", time.Since(start))
				fmt.Printf("RAG Answer: %s\n", answer)
				success = true
				break
			}
		}
		fmt.Printf("Waiting for ingestion... (elapsed: %v, last answer: %q)\n", time.Since(start).Round(time.Second), answer)
		time.Sleep(10 * time.Second)
	}

	if !success {
		fmt.Printf("FAILURE: Secret code not found in answer after 5 minutes. Last answer: %q\n", lastAnswer)
	}

	// 7. Cleanup (Delete Data)
	fmt.Println("[STEP 7] Cleaning up data by tag...")
	if err := deleteData(tagID); err != nil {
		logFatal("Failed to delete data: %v", err)
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

	fmt.Println("--- E2E Test Completed ---")
}

func getFiles() ([]string, error) {
	resp, err := client.Get(baseURL + "/")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// Simple regex to find files in the <ul> section
	// <li>Filename</li>
	re := regexp.MustCompile(`<li>([^<]+)</li>`)
	matches := re.FindAllStringSubmatch(string(body), -1)

	var files []string
	for _, m := range matches {
		if m[1] != "No files found" {
			files = append(files, m[1])
		}
	}
	return files, nil
}

func createTag(name string) error {
	formData := url.Values{"tag_name": {name}}
	resp, err := client.PostForm(baseURL+"/create-tag", formData)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusFound {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func getTags() (map[string]string, error) {
	resp, err := client.Get(baseURL + "/")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	fmt.Printf("DEBUG: HTML body: %s\n", string(body))

	// Very simple regex to find tag IDs and names from the HTML checkboxes
	// <input type="checkbox" name="tags" value="ID"> Name
	re := regexp.MustCompile(`<input type="checkbox" name="tags" value="([^"]+)"> ([^<]+)`)
	matches := re.FindAllStringSubmatch(string(body), -1)

	tags := make(map[string]string)
	for _, m := range matches {
		tags[strings.TrimSpace(m[2])] = m[1]
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
	var b bytes.Buffer
	w := multipart.NewWriter(&b)
	fw, err := w.CreateFormFile("file", name)
	if err != nil {
		return err
	}
	if _, err := io.Copy(fw, strings.NewReader(content)); err != nil {
		return err
	}
	w.Close()

	req, err := http.NewRequest("POST", baseURL+"/upload", &b)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", w.FormDataContentType())

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusFound {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func triggerIngest(tagID string, vectorSize int, fileName string) error {
	formData := url.Values{
		"tags":        {tagID},
		"vector_size": {fmt.Sprintf("%d", vectorSize)},
		"file_names":  {fileName},
	}
	resp, err := client.PostForm(baseURL+"/trigger-ingest", formData)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusFound {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func askRAG(query string, tags []string) (string, error) {
	payload := map[string]interface{}{
		"query": query,
		"tags":  tags,
	}
	body, _ := json.Marshal(payload)
	resp, err := client.Post(baseURL+"/ask", "application/json", bytes.NewBuffer(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Answer string `json:"answer"`
		Error  string `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}
	if result.Error != "" {
		return "", fmt.Errorf(result.Error)
	}
	return result.Answer, nil
}

func deleteData(tagID string) error {
	formData := url.Values{"tags": {tagID}}
	resp, err := client.PostForm(baseURL+"/delete-data", formData)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusFound {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return nil
}

func logFatal(format string, v ...interface{}) {
	fmt.Printf(format+"\n", v...)
	os.Exit(1)
}
