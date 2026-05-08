package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

type StreamChunk struct {
	Id             string                 `json:"id"`
	SessionId      int64                  `json:"session_id"`
	Result         string                 `json:"result"`
	SequenceNumber int32                  `json:"sequence_number"`
	IsLast         bool                   `json:"is_last"`
	Metadata       map[string]interface{} `json:"metadata"`
}

func main() {
	sessionID, err := runTest()
	
	// Cleanup session if created
	if sessionID != 0 {
		cleanup(sessionID)
	}

	if err != nil {
		log.Fatalf("Test failed: %v", err)
	}
	fmt.Println("SUCCESS: Tiered streaming verified.")
}

func cleanup(id int64) {
	fmt.Printf("Cleaning up session %d...\n", id)
	deleteURL := fmt.Sprintf("https://rag-admin-api.rag.hierocracy.home/api/memory/sessions/%d", id)
	req, err := http.NewRequest(http.MethodDelete, deleteURL, nil)
	if err != nil {
		log.Printf("Failed to create delete request: %v", err)
		return
	}

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
		Timeout: 10 * time.Second,
	}

	resp, err := client.Do(req)
	if err != nil {
		log.Printf("Failed to delete session: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		body, _ := io.ReadAll(resp.Body)
		log.Printf("Failed to delete session: status=%d, body=%s", resp.StatusCode, string(body))
	} else {
		fmt.Println("Session cleaned up successfully.")
	}
}

func runTest() (int64, error) {
	// 1. Create a session
	sessionName := fmt.Sprintf("TieredTest-%d", time.Now().Unix())
	sessionReq := fmt.Sprintf(`{"name": "%s"}`, sessionName)
	resp, err := http.Post("https://rag-admin-api.rag.hierocracy.home/api/memory/sessions", "application/json", strings.NewReader(sessionReq))
	if err != nil {
		return 0, fmt.Errorf("failed to create session: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return 0, fmt.Errorf("failed to create session: status=%d, body=%s", resp.StatusCode, string(body))
	}
	var session struct {
		ID int64 `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&session); err != nil {
		return 0, fmt.Errorf("failed to decode session: %v", err)
	}
	fmt.Printf("Created session: %d\n", session.ID)

	// 2. Connect to WebSocket
	url := fmt.Sprintf("wss://rag-admin-api.rag.hierocracy.home/api/chat/v1/rag/chat/stream")
	dialer := websocket.Dialer{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	conn, resp_ws, err := dialer.Dial(url, nil)
	if err != nil {
		if resp_ws != nil {
			body, _ := io.ReadAll(resp_ws.Body)
			return session.ID, fmt.Errorf("failed to connect to WS: %v, status=%d, body=%s", err, resp_ws.StatusCode, string(body))
		}
		return session.ID, fmt.Errorf("failed to connect to WS: %v", err)
	}
	defer conn.Close()

	// 3. Send a prompt
	prompt := map[string]interface{}{
		"prompt":     "Tell me a very short secret about session context.",
		"session_id": session.ID,
		"planner":    "llama3.1:latest",
		"executor":   "llama3.1:latest",
	}
	if err := conn.WriteJSON(prompt); err != nil {
		return session.ID, fmt.Errorf("failed to send prompt: %v", err)
	}

	// 4. Verify tiered chunks
	var seq0Received, contentReceived bool
	
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	for {
		select {
		case <-ctx.Done():
			return session.ID, fmt.Errorf("timeout waiting for response")
		default:
			_, message, err := conn.ReadMessage()
			if err != nil {
				return session.ID, fmt.Errorf("read error: %v", err)
			}

			var chunk StreamChunk
			if err := json.Unmarshal(message, &chunk); err != nil {
				log.Printf("Failed to unmarshal: %v", err)
				continue
			}

			fmt.Printf("Chunk: Seq=%d, Len=%d, Metadata=%v\n", chunk.SequenceNumber, len(chunk.Result), chunk.Metadata != nil)

			if chunk.SequenceNumber == 0 {
				seq0Received = true
				if chunk.Result != "" {
					log.Printf("WARNING: Seq 0 should have empty result, got len %d", len(chunk.Result))
				}
				if chunk.Metadata == nil {
					return session.ID, fmt.Errorf("Seq 0 must have metadata")
				}
			} else if chunk.SequenceNumber > 0 {
				contentReceived = true
				if len(chunk.Result) == 0 && !chunk.IsLast {
					log.Printf("WARNING: Seq %d has empty result", chunk.SequenceNumber)
				}
				if chunk.Metadata != nil {
					log.Printf("WARNING: Seq %d should NOT have metadata (bandwidth optimization)", chunk.SequenceNumber)
				}
			}

			if chunk.IsLast {
				fmt.Println("Final chunk received.")
				if seq0Received && contentReceived {
					return session.ID, nil
				}
				return session.ID, fmt.Errorf("finished but missed either Seq 0 or content")
			}
		}
	}
}
