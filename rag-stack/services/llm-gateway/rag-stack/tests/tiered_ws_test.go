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
	// 1. Create a session
	sessionName := fmt.Sprintf("TieredTest-%d", time.Now().Unix())
	sessionReq := fmt.Sprintf(`{"name": "%s"}`, sessionName)
	resp, err := http.Post("https://rag-admin-api.rag.hierocracy.home/api/memory/sessions", "application/json", strings.NewReader(sessionReq))
	if err != nil {
		log.Fatalf("Failed to create session: %v", err)
	}
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		log.Fatalf("Failed to create session: status=%d, body=%s", resp.StatusCode, string(body))
	}
	var session struct {
		ID int64 `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&session); err != nil {
		log.Fatalf("Failed to decode session: %v", err)
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
			log.Fatalf("Failed to connect to WS: %v, status=%d, body=%s, headers=%v", err, resp_ws.StatusCode, string(body), resp_ws.Header)
		}
		log.Fatalf("Failed to connect to WS: %v", err)
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
		log.Fatalf("Failed to send prompt: %v", err)
	}

	// 4. Verify tiered chunks
	var seq0Received, contentReceived bool
	
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	for {
		select {
		case <-ctx.Done():
			log.Fatal("Timeout waiting for response")
		default:
			_, message, err := conn.ReadMessage()
			if err != nil {
				log.Fatalf("Read error: %v", err)
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
					log.Fatal("ERROR: Seq 0 must have metadata")
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
					fmt.Println("SUCCESS: Tiered streaming verified.")
					return
				}
				log.Fatal("Finished but missed either Seq 0 or content")
			}
		}
	}
}
