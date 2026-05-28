package logic

import (
	"context"
	"testing"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/behavioralrule"
	"app-builds/common/ent/enttest"
	"app-builds/memory-controller/internal/behavioral"
	"github.com/google/uuid"

	_ "github.com/mattn/go-sqlite3"
)

func TestMemoryManager(t *testing.T) {
	client := enttest.Open(t, "sqlite3", "file:ent?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	m := NewMemoryManager(client)
	ctx := context.Background()

	t.Run("CreateAndListSessions", func(t *testing.T) {
		s, err := m.CreateSession(ctx, 0, "test-session")
		if err != nil {
			t.Fatalf("Failed to create session: %v", err)
		}
		if s.Name != "test-session" {
			t.Errorf("Expected name test-session, got %s", s.Name)
		}

		sessions, err := m.ListSessions(ctx)
		if err != nil {
			t.Fatalf("Failed to list sessions: %v", err)
		}
		if len(sessions) != 1 {
			t.Errorf("Expected 1 session, got %d", len(sessions))
		}
	})

	t.Run("WriteAndListItems", func(t *testing.T) {
		sessionID := int64(123)
		m.CreateSession(ctx, sessionID, "item-session")

		req := &contracts.MemoryWriteRequest{
			Scope: &contracts.MemoryScope{
				SessionId: sessionID,
			},
			Writes: []*contracts.MemoryWriteItem{
				{
					MemoryType: "test",
					Content:    "test content",
					Summary:    "test summary",
				},
			},
		}

		err := m.WriteItems(ctx, req)
		if err != nil {
			t.Fatalf("Failed to write items: %v", err)
		}

		items, err := m.ListItems(ctx, sessionID)
		if err != nil {
			t.Fatalf("Failed to list items: %v", err)
		}
		if len(items) != 1 {
			t.Errorf("Expected 1 item, got %d", len(items))
		}
		if items[0].Content != "test content" {
			t.Errorf("Expected content 'test content', got %s", items[0].Content)
		}

		// List for different session
		items2, _ := m.ListItems(ctx, 456)
		if len(items2) != 0 {
			t.Errorf("Expected 0 items for different session, got %d", len(items2))
		}
	})

	t.Run("Retrieve", func(t *testing.T) {
		sessionID := int64(789)
		m.CreateSession(ctx, sessionID, "retrieve-session")

		// Add some history
		p, err := client.Prompt.Create().
			SetSessionID(sessionID).
			SetContent("What is AI?").
			SetPromptID(uuid.New()).
			Save(ctx)
		if err != nil {
			t.Fatalf("Failed to create prompt: %v", err)
		}
		t.Logf("Created prompt with ID=%d", p.ID)

		resp, err := client.Response.Create().
			SetPromptID(p.ID).
			SetContent("AI is Artificial Intelligence.").
			SetResponseID(uuid.New()).
			SetSequenceNumber(1).
			Save(ctx)
		if err != nil {
			t.Fatalf("Failed to create response: %v", err)
		}
		t.Logf("Created response with ID=%d, PromptID=%d", resp.ID, resp.PromptID)

		// Add a memory item
		m.WriteItems(ctx, &contracts.MemoryWriteRequest{
			Scope: &contracts.MemoryScope{SessionId: sessionID},
			Writes: []*contracts.MemoryWriteItem{
				{MemoryType: "fact", Content: "User is a dev", Summary: "User job"},
			},
		})

		req := &contracts.MemoryRetrieveRequest{
			Scope: &contracts.MemoryScope{SessionId: sessionID},
			Limit: 5,
		}

		pack, err := m.Retrieve(ctx, req, "")
		if err != nil {
			t.Fatalf("Failed to retrieve: %v", err)
		}

		// Should have 1 prompt, 1 response, 1 memory item = 3 items
		if len(pack.Items) != 3 {
			t.Errorf("Expected 3 items in pack, got %d", len(pack.Items))
		}

		// Verify order of history (prompt then response)
		// Our implementation prepends them in reverse order of prompts, then response after prompt.
		// So for 1 prompt: [MemoryItems..., Prompt, Response]

		foundPrompt := false
		foundResponse := false
		foundFact := false
		for _, item := range pack.Items {
			if item.MemoryType == "fact" {
				foundFact = true
			}
			if item.MemoryType == "chat_history" {
				if item.Content == "What is AI?" {
					foundPrompt = true
				}
				if item.Content == "AI is Artificial Intelligence." {
					foundResponse = true
				}
			}
		}

		if !foundPrompt || !foundResponse || !foundFact {
			t.Errorf("Missing items in pack: prompt=%v, resp=%v, fact=%v", foundPrompt, foundResponse, foundFact)
		}
	})

	t.Run("DeleteSession", func(t *testing.T) {
		sessionID := int64(999)
		m.CreateSession(ctx, sessionID, "delete-me")
		m.WriteItems(ctx, &contracts.MemoryWriteRequest{
			Scope:  &contracts.MemoryScope{SessionId: sessionID},
			Writes: []*contracts.MemoryWriteItem{{Content: "data"}},
		})

		err := m.DeleteSession(ctx, sessionID)
		if err != nil {
			t.Fatalf("Failed to delete session: %v", err)
		}

		// Verify session gone
		_, err = client.Session.Get(ctx, sessionID)
		if !ent.IsNotFound(err) {
			t.Errorf("Expected session to be not found, got %v", err)
		}

		// Verify items gone
		items, _ := m.ListItems(ctx, sessionID)
		if len(items) != 0 {
			t.Errorf("Expected 0 items after deletion, got %d", len(items))
		}
	})

	t.Run("RetrieveOrdersBehavioralRulesByScopeAndPriority", func(t *testing.T) {
		localClient := enttest.Open(t, "sqlite3", "file:behavioral-order?mode=memory&cache=shared&_fk=1")
		defer localClient.Close()
		localManager := NewMemoryManager(localClient)
		localCtx := context.Background()

		sessionID := int64(2024)
		localManager.CreateSession(localCtx, sessionID, "behavior-session")

		_, err := localClient.BehavioralRule.Create().
			SetActionType("FILE_EDIT").
			SetRuleContent("global rule").
			SetPriority(5).
			SetScope(behavioralrule.ScopeGLOBAL).
			SetState(behavioralrule.StateACTIVE).
			Save(localCtx)
		if err != nil {
			t.Fatalf("Failed to create global rule: %v", err)
		}

		_, err = localClient.BehavioralRule.Create().
			SetActionType("FILE_EDIT").
			SetRuleContent("project rule").
			SetPriority(1).
			SetScope(behavioralrule.ScopePROJECT).
			SetState(behavioralrule.StateACTIVE).
			Save(localCtx)
		if err != nil {
			t.Fatalf("Failed to create project rule: %v", err)
		}

		sessionRule, err := localClient.BehavioralRule.Create().
			SetActionType("FILE_EDIT").
			SetRuleContent("session rule").
			SetPriority(1).
			SetScope(behavioralrule.ScopeSESSION).
			SetState(behavioralrule.StateACTIVE).
			Save(localCtx)
		if err != nil {
			t.Fatalf("Failed to create session rule: %v", err)
		}

		_, err = localClient.SessionGovernance.Create().
			SetSessionID(sessionID).
			SetRuleID(sessionRule.ID).
			SetPriorityOverride(99).
			Save(localCtx)
		if err != nil {
			t.Fatalf("Failed to create session override: %v", err)
		}

		pack, err := localManager.Retrieve(localCtx, &contracts.MemoryRetrieveRequest{
			Scope: &contracts.MemoryScope{SessionId: sessionID},
			Limit: 5,
		}, "FILE_EDIT")
		if err != nil {
			t.Fatalf("Failed to retrieve behavioral pack: %v", err)
		}

		if len(pack.Items) < 3 {
			t.Fatalf("Expected at least 3 behavioral items, got %d", len(pack.Items))
		}
		if pack.Items[0].Content != "session rule" {
			t.Fatalf("Expected session rule first, got %q", pack.Items[0].Content)
		}
		if pack.Items[1].Content != "project rule" {
			t.Fatalf("Expected project rule second, got %q", pack.Items[1].Content)
		}
		if pack.Items[2].Content != "global rule" {
			t.Fatalf("Expected global rule third, got %q", pack.Items[2].Content)
		}
	})

	t.Run("RetrieveBucketsRulesByActionType", func(t *testing.T) {
		localClient := enttest.Open(t, "sqlite3", "file:behavioral-bucket?mode=memory&cache=shared&_fk=1")
		defer localClient.Close()
		localManager := NewMemoryManager(localClient)
		localCtx := context.Background()

		sessionID := int64(3030)
		localManager.CreateSession(localCtx, sessionID, "bucket-session")

		_, err := localClient.BehavioralRule.Create().
			SetActionType("FILE_EDIT").
			SetRuleContent("edit rule").
			SetPriority(9).
			SetScope(behavioralrule.ScopeSESSION).
			SetState(behavioralrule.StateACTIVE).
			Save(localCtx)
		if err != nil {
			t.Fatalf("Failed to create edit rule: %v", err)
		}

		_, err = localClient.BehavioralRule.Create().
			SetActionType("FILE_SEARCH").
			SetRuleContent("search rule").
			SetPriority(9).
			SetScope(behavioralrule.ScopeGLOBAL).
			SetState(behavioralrule.StateACTIVE).
			Save(localCtx)
		if err != nil {
			t.Fatalf("Failed to create search rule: %v", err)
		}

		_, err = localClient.BehavioralRule.Create().
			SetActionType("FILE_EDIT").
			SetRuleContent("fallback rule").
			SetPriority(1).
			SetScope(behavioralrule.ScopeGLOBAL).
			SetState(behavioralrule.StateACTIVE).
			Save(localCtx)
		if err != nil {
			t.Fatalf("Failed to create fallback rule: %v", err)
		}

		pack, err := localManager.Retrieve(localCtx, &contracts.MemoryRetrieveRequest{
			Scope: &contracts.MemoryScope{SessionId: sessionID},
			Limit: 10,
		}, "FILE_EDIT")
		if err != nil {
			t.Fatalf("Failed to retrieve bucketed context: %v", err)
		}

		if len(pack.Items) != 3 {
			t.Fatalf("Expected 3 rules in pack, got %d", len(pack.Items))
		}
		if pack.Items[0].Content != "edit rule" {
			t.Fatalf("Expected edit rule first, got %q", pack.Items[0].Content)
		}
		if pack.Items[1].Content != "fallback rule" {
			t.Fatalf("Expected fallback rule second, got %q", pack.Items[1].Content)
		}
		if pack.Items[2].Content != "search rule" {
			t.Fatalf("Expected search rule third, got %q", pack.Items[2].Content)
		}
		if meta := contracts.FromStruct(pack.Items[0].Metadata); meta["context_bucket"] != "action_scoped_behavior" {
			t.Fatalf("Expected action bucket for first rule, got %v", meta["context_bucket"])
		}
		if meta := contracts.FromStruct(pack.Items[1].Metadata); meta["context_bucket"] != "action_scoped_behavior" {
			t.Fatalf("Expected fallback bucket for second rule, got %v", meta["context_bucket"])
		}
		if meta := contracts.FromStruct(pack.Items[2].Metadata); meta["context_bucket"] != "global_fallback_policy" {
			t.Fatalf("Expected fallback bucket for third rule, got %v", meta["context_bucket"])
		}
	})

	t.Run("RecordLearningStagesRules", func(t *testing.T) {
		localClient := enttest.Open(t, "sqlite3", "file:behavioral-stage?mode=memory&cache=shared&_fk=1")
		defer localClient.Close()
		manager := behavioral.NewBehaviorManager(localClient)

		rule, err := manager.RecordLearning(context.Background(), "stage this", "FILE_EDIT", "Optimization", 55)
		if err != nil {
			t.Fatalf("Failed to stage learning: %v", err)
		}
		if rule.State != behavioralrule.StateSTAGED {
			t.Fatalf("Expected staged rule state, got %s", rule.State)
		}
	})
}
