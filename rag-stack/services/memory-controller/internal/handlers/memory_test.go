package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/enttest"
	"app-builds/common/ent/session"

	_ "github.com/mattn/go-sqlite3"
)

func TestMemoryHandler(t *testing.T) {
	// 1. Setup in-memory SQLite Ent client
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	h := NewMemoryHandler(client)
	ctx := context.Background()

	// 2. Test POST /items
	t.Run("WriteItems", func(t *testing.T) {
		sessionID := time.Now().UnixNano() % 100000
		// Create session first
		client.Session.Create().SetID(sessionID).SetName("write-items-session").SaveX(ctx)

		reqBody := contracts.MemoryWriteRequest{
			RequestId: "req-1",
			Scope: &contracts.MemoryScope{
				SessionId: sessionID,
			},
			Writes: []*contracts.MemoryWriteItem{
				{
					MemoryType: "observation",
					Content:    "The user likes coffee.",
					Summary:    "Coffee preference",
				},
			},
		}
		
		body, _ := json.Marshal(&reqBody)
		req := httptest.NewRequest(http.MethodPost, "/items", bytes.NewReader(body))
		w := httptest.NewRecorder()
		
		h.HandleItems(w, req)
		
		if w.Code != http.StatusCreated {
			t.Errorf("Expected status 201, got %v", w.Code)
		}
		
		// Verify in DB
		count, _ := client.MemoryItem.Query().Count(ctx)
		if count != 1 {
			t.Errorf("Expected 1 memory item in DB, got %d", count)
		}
	})

	// 3. Test GET /items
	t.Run("ListItems", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/items", nil)
		w := httptest.NewRecorder()
		
		h.HandleItems(w, req)
		
		if w.Code != http.StatusOK {
			t.Errorf("Expected status 200, got %v", w.Code)
		}
		
		var items []*ent.MemoryItem
		json.NewDecoder(w.Body).Decode(&items)
		
		if len(items) != 1 {
			t.Errorf("Expected 1 item, got %d", len(items))
		}
		if items[0].Summary != "Coffee preference" {
			t.Errorf("Expected summary 'Coffee preference', got %s", items[0].Summary)
		}
	})

	// 4. Test POST /sessions
	t.Run("CreateSession", func(t *testing.T) {
		reqBody := struct {
			Id   int64  `json:"id"`
			Name string `json:"name"`
		}{
			Id:   time.Now().UnixNano() % 100000,
			Name: "test session",
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/sessions", bytes.NewReader(body))
		w := httptest.NewRecorder()

		h.HandleSessions(w, req)

		if w.Code != http.StatusCreated {
			t.Errorf("Expected status 201, got %v: %s", w.Code, w.Body.String())
		}
	})

	// 5. Test POST /sessions conflict (Duplicate name, different ID)
	t.Run("CreateSessionDuplicateName", func(t *testing.T) {
		reqBody := struct {
			Id   int64  `json:"id"`
			Name string `json:"name"`
		}{
			Id:   time.Now().UnixNano() % 100000,
			Name: "test session", // Same name as before
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/sessions", bytes.NewReader(body))
		w := httptest.NewRecorder()

		h.HandleSessions(w, req)

		if w.Code != http.StatusConflict {
			t.Errorf("Expected status 409, got %v: %s", w.Code, w.Body.String())
		}
	})

	// 6. Test POST /sessions update (Same ID, same name)
	t.Run("CreateSessionUpdate", func(t *testing.T) {
		// First get the existing session
		sessions, _ := client.Session.Query().All(ctx)
		if len(sessions) == 0 {
			t.Fatal("No sessions found")
		}
		existingID := sessions[0].ID

		reqBody := struct {
			Id   int64  `json:"id"`
			Name string `json:"name"`
		}{
			Id:   existingID,
			Name: "updated session name",
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/sessions", bytes.NewReader(body))
		w := httptest.NewRecorder()

		h.HandleSessions(w, req)

		if w.Code != http.StatusCreated {
			t.Errorf("Expected status 201, got %v: %s", w.Code, w.Body.String())
		}
		
		// Verify name updated
		updated, _ := client.Session.Get(ctx, sessions[0].ID)
		if updated.Name != "updated session name" {
			t.Errorf("Expected name 'updated session name', got %s", updated.Name)
		}
	})

	// 7. Test POST /retrieve
	t.Run("HandleRetrieve", func(t *testing.T) {
		sessionID := int64(888)
		client.Session.Create().SetID(sessionID).SetName("retrieve-handler-session").SaveX(ctx)

		reqBody := contracts.MemoryRetrieveRequest{
			Scope: &contracts.MemoryScope{
				SessionId: sessionID,
			},
			Limit: 5,
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/retrieve", bytes.NewReader(body))
		w := httptest.NewRecorder()

		h.HandleRetrieve(w, req)

		if w.Code != http.StatusOK {
			t.Errorf("Expected status 200, got %v: %s", w.Code, w.Body.String())
		}

		var pack contracts.MemoryPack
		json.NewDecoder(w.Body).Decode(&pack)
		// Initially empty session should return empty pack (or just empty items)
		if len(pack.Items) != 0 {
			t.Errorf("Expected 0 items in empty session, got %d", len(pack.Items))
		}
	})

	// 8. Test DELETE /sessions/{id}
	t.Run("DeleteSession", func(t *testing.T) {
		sessionID := int64(12345)
		client.Session.Create().SetID(sessionID).SetName("to-be-deleted").SaveX(ctx)

		req := httptest.NewRequest(http.MethodDelete, "/sessions/12345", nil)
		w := httptest.NewRecorder()

		h.HandleSessions(w, req)

		if w.Code != http.StatusNoContent {
			t.Errorf("Expected status 204, got %v: %s", w.Code, w.Body.String())
		}

		// Verify deleted
		exists, _ := client.Session.Query().Where(session.ID(sessionID)).Exist(ctx)
		if exists {
			t.Errorf("Session still exists after deletion")
		}
	})
}
