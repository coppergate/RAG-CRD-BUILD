package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/enttest"
	"github.com/google/uuid"

	_ "github.com/mattn/go-sqlite3"
)

func TestMemoryHandler(t *testing.T) {
	// 1. Setup in-memory SQLite Ent client
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	h := NewMemoryHandler(client)
	ctx := context.Background()

	// 2. Test POST /api/memory/items
	t.Run("WriteItems", func(t *testing.T) {
		sessionID := uuid.New().String()
		reqBody := contracts.MemoryWriteRequest{
			RequestID: "req-1",
			Scope: contracts.MemoryScope{
				SessionID: sessionID,
			},
			Writes: []contracts.MemoryWriteItem{
				{
					MemoryType: "observation",
					Content:    "The user likes coffee.",
					Summary:    "Coffee preference",
				},
			},
		}
		
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/api/memory/items", bytes.NewReader(body))
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

	// 3. Test GET /api/memory/items
	t.Run("ListItems", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/memory/items", nil)
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
}
