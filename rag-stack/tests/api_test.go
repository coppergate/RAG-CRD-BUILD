package tests

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"
)

const (
	adminAPIURL = "https://rag-admin-api.rag.hierocracy.home"
)

func getClient() *http.Client {
	return &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
		Timeout: 30 * time.Second,
	}
}

func TestHealthAll(t *testing.T) {
	client := getClient()
	resp, err := client.Get(adminAPIURL + "/api/health/all")
	if err != nil {
		t.Fatalf("Failed to call health endpoint: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK, got %v", resp.Status)
	}

	var health map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&health); err != nil {
		t.Fatalf("Failed to decode health response: %v", err)
	}

	if len(health) == 0 {
		t.Error("Empty health response")
	}
	t.Logf("Health status: %+v", health)
}

func TestTags(t *testing.T) {
	client := getClient()
	resp, err := client.Get(adminAPIURL + "/api/db/tags")
	if err != nil {
		t.Fatalf("Failed to fetch tags: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK, got %v", resp.Status)
	}

	var tags []map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&tags); err != nil {
		t.Fatalf("Failed to decode tags: %v", err)
	}
	t.Logf("Found %d tags", len(tags))
}

func TestSessionLifecycle(t *testing.T) {
	client := getClient()
	sessionName := fmt.Sprintf("test-session-%d", time.Now().Unix())

	// 1. Create Session
	createPayload := map[string]string{"name": sessionName}
	body, _ := json.Marshal(createPayload)
	resp, err := client.Post(adminAPIURL+"/api/memory/sessions", "application/json", bytes.NewBuffer(body))
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		t.Fatalf("Failed to create session, status: %v", resp.Status)
	}

	var session map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&session); err != nil {
		t.Fatalf("Failed to decode session: %v", err)
	}

	sessionID, ok := session["session_id"].(float64)
	if !ok {
		// Try 'id' if 'session_id' is missing (Ent sometimes defaults to 'id' in JSON if not overridden)
		sessionID, ok = session["id"].(float64)
		if !ok {
			t.Fatalf("Session ID missing in response: %+v", session)
		}
	}
	id := int64(sessionID)
	t.Logf("Created session with ID: %d", id)

	// 2. List Sessions
	resp, err = client.Get(adminAPIURL + "/api/memory/sessions")
	if err != nil {
		t.Fatalf("Failed to list sessions: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK for list sessions, got %v", resp.Status)
	}

	var sessions []map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&sessions); err != nil {
		t.Fatalf("Failed to decode sessions list: %v", err)
	}

	found := false
	for _, s := range sessions {
		sID, _ := s["session_id"].(float64)
		if sID == 0 {
			sID, _ = s["id"].(float64)
		}
		if int64(sID) == id {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("Created session %d not found in list", id)
	}

	// 3. Get Messages (should be empty but succeed)
	resp, err = client.Get(fmt.Sprintf("%s/api/db/sessions/%d/messages", adminAPIURL, id))
	if err != nil {
		t.Fatalf("Failed to get messages: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK for messages, got %v", resp.Status)
	}

	// 4. Update Session Tags
	tagPayload := map[string][]int64{"tag_ids": {1}} // Assuming tag 1 exists or just testing the endpoint
	tagBody, _ := json.Marshal(tagPayload)
	resp, err = client.Post(fmt.Sprintf("%s/api/db/sessions/tags?session_id=%d", adminAPIURL, id), "application/json", bytes.NewBuffer(tagBody))
	if err != nil {
		t.Fatalf("Failed to update session tags: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		t.Logf("Note: Tag update failed (expected if tag 1 doesn't exist), status: %v", resp.Status)
	}

	// 5. Delete Session
	req, _ := http.NewRequest(http.MethodDelete, fmt.Sprintf("%s/api/memory/sessions/%d", adminAPIURL, id), nil)
	resp, err = client.Do(req)
	if err != nil {
		t.Fatalf("Failed to delete session: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		t.Errorf("Expected StatusNoContent or OK for delete, got %v", resp.Status)
	}
	t.Logf("Deleted session %d", id)
}

func TestMemoryItems(t *testing.T) {
	client := getClient()
	
	// List items
	resp, err := client.Get(adminAPIURL + "/api/memory/items")
	if err != nil {
		t.Fatalf("Failed to list memory items: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK for list items, got %v", resp.Status)
	}
}
