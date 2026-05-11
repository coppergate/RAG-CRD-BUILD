package logic

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/behavioralrule"
	"app-builds/common/ent/memoryevent"
	"app-builds/common/ent/sessiongovernance"
	"app-builds/common/ent/memoryitem"
	"app-builds/common/ent/memorylink"
	"app-builds/common/ent/prompt"
	"app-builds/common/ent/response"
	"app-builds/common/ent/session"

	"entgo.io/ent/dialect/sql"
	"entgo.io/ent/dialect/sql/sqljson"
	"app-builds/common/logging"
)

type MemoryManager struct {
	client *ent.Client
}

func NewMemoryManager(client *ent.Client) *MemoryManager {
	return &MemoryManager{
		client: client,
	}
}

func (m *MemoryManager) ListItems(ctx context.Context, sessionID int64) ([]*ent.MemoryItem, error) {
	query := m.client.MemoryItem.Query()
	if sessionID > 0 {
		query = query.Where(memoryitem.SessionID(sessionID))
	}
	items, err := query.All(ctx)
	if err != nil {
		return nil, err
	}
	if items == nil {
		return []*ent.MemoryItem{}, nil
	}
	return items, nil
}

func (m *MemoryManager) WriteItems(ctx context.Context, req *contracts.MemoryWriteRequest) error {
	tx, err := m.client.Tx(ctx)
	if err != nil {
		return fmt.Errorf("failed to start transaction: %w", err)
	}

	for _, item := range req.Writes {
		builder := tx.MemoryItem.Create().
			SetMemoryType(item.MemoryType).
			SetSummary(item.Summary).
			SetContent(item.Content).
			SetSalience(item.SalienceHint).
			SetRetentionScore(item.RetentionHint).
			SetPinned(item.Pinned).
			SetMetadata(contracts.FromStruct(item.Metadata))

		if req.Scope.SessionId > 0 {
			builder = builder.SetSessionID(req.Scope.SessionId)
		}

		if req.Scope.ProjectId > 0 {
			builder = builder.SetProjectID(req.Scope.ProjectId)
		}

		mi, err := builder.Save(ctx)
		if err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to save memory item: %w", err)
		}

		// Create links
		if len(item.SourceRefs) == 0 && len(req.Scope.Tags) > 0 {
			// Create a default link for tags if no source refs are provided
			err = tx.MemoryLink.Create().
				SetMemoryItemID(mi.ID).
				SetTags(req.Scope.Tags).
				Exec(ctx)
			if err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to create tag-only memory link: %w", err)
			}
		}

		for _, ref := range item.SourceRefs {
			err = tx.MemoryLink.Create().
				SetMemoryItemID(mi.ID).
				SetTags(req.Scope.Tags).
				SetMetadata(map[string]interface{}{
					"source_kind":   ref.SourceKind,
					"source_id":     ref.SourceId,
					"relation_type": ref.RelationType,
				}).
				Exec(ctx)
			if err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to create memory link: %w", err)
			}
		}

		// Log event
		err = tx.MemoryEvent.Create().
			SetMemoryItemID(mi.ID).
			SetEventType("write").
			SetEventData(map[string]interface{}{
				"request_id":     req.RequestId,
				"correlation_id": req.CorrelationId,
			}).
			Exec(ctx)
		if err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to create memory event: %w", err)
		}
	}

	return tx.Commit()
}

func (m *MemoryManager) ListSessions(ctx context.Context) ([]*ent.Session, error) {
	sessions, err := m.client.Session.Query().
		Order(ent.Desc(session.FieldLastActiveAt)).
		WithTags().
		All(ctx)
	if err != nil {
		return nil, err
	}
	if sessions == nil {
		return []*ent.Session{}, nil
	}
	return sessions, nil
}

func (m *MemoryManager) CreateSession(ctx context.Context, id int64, name string) (*ent.Session, error) {
	// Check if name already exists for a DIFFERENT session ID
	if name != "" {
		existing, err := m.client.Session.Query().
			Where(session.Name(name)).
			First(ctx)
		if err == nil && existing != nil {
			if id == 0 || existing.ID != id {
				return nil, fmt.Errorf("session name already exists")
			}
		}
	}

	builder := m.client.Session.Create().
		SetName(name).
		SetLastActiveAt(time.Now())

	if id > 0 {
		builder.SetID(id)
	}

	sID, err := builder.OnConflictColumns(session.FieldID).
		UpdateLastActiveAt().
		UpdateName().
		ID(ctx)
	if err != nil {
		if strings.Contains(err.Error(), "unique constraint") || strings.Contains(err.Error(), "duplicate key") {
			return nil, fmt.Errorf("session name already exists")
		}
		return nil, err
	}

	return m.client.Session.Query().
		Where(session.ID(sID)).
		WithTags().
		Only(ctx)
}

func (m *MemoryManager) DeleteSession(ctx context.Context, id int64) error {
	tx, err := m.client.Tx(ctx)
	if err != nil {
		return fmt.Errorf("failed to start transaction: %w", err)
	}

	// 1. Find all memory items for this session
	items, err := tx.MemoryItem.Query().
		Where(memoryitem.SessionID(id)).
		All(ctx)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to query memory items: %w", err)
	}

	var itemIDs []int64
	for _, it := range items {
		itemIDs = append(itemIDs, it.ID)
	}

	if len(itemIDs) > 0 {
		// 2. Delete links
		_, err = tx.MemoryLink.Delete().
			Where(memorylink.MemoryItemIDIn(itemIDs...)).
			Exec(ctx)
		if err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to delete memory links: %w", err)
		}

		// 3. Delete events
		_, err = tx.MemoryEvent.Delete().
			Where(memoryevent.MemoryItemIDIn(itemIDs...)).
			Exec(ctx)
		if err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to delete memory events: %w", err)
		}

		// 4. Delete items
		_, err = tx.MemoryItem.Delete().
			Where(memoryitem.IDIn(itemIDs...)).
			Exec(ctx)
		if err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to delete memory items: %w", err)
		}
	}

	// 5. Delete session
	err = tx.Session.DeleteOneID(id).Exec(ctx)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to delete session: %w", err)
	}

	return tx.Commit()
}

func (m *MemoryManager) Retrieve(ctx context.Context, req *contracts.MemoryRetrieveRequest) (*contracts.MemoryPack, error) {
	sessionID := req.Scope.SessionId
	if sessionID == 0 {
		return nil, fmt.Errorf("session ID required in scope")
	}

	limit := req.Limit
	if limit <= 0 {
		limit = 10
	}

	// 1. Fetch relevant MemoryItems
	query := m.client.MemoryItem.Query().
		Where(memoryitem.SessionID(sessionID))

	// Filter by tags if provided
	if len(req.Scope.Tags) > 0 {
		query = query.Where(memoryitem.HasLinksWith(func(s *sql.Selector) {
			var ps []*sql.Predicate
			for _, tag := range req.Scope.Tags {
				ps = append(ps, sqljson.ValueContains(memorylink.FieldTags, tag))
			}
			s.Where(sql.Or(ps...))
		}))
		// If tags are provided, we assume the user wants everything for that tag
		// so we increase the limit significantly unless a limit was explicitly provided
		if req.Limit <= 0 {
			limit = 1000
		}
	}

	mItems, err := query.
		Order(ent.Desc(memoryitem.FieldCreatedAt)).
		Limit(int(limit)).
		All(ctx)
	if err != nil {
		logging.Printf("[MEMCTRL] Error fetching memory items: %v", err)
	}

	// 2. Fetch Chat History (Prompts and Responses)
	prompts, err := m.client.Prompt.Query().
		Where(prompt.SessionID(sessionID)).
		Order(ent.Desc(prompt.FieldCreatedAt)).
		Limit(int(limit)).
		All(ctx)
	if err != nil {
		logging.Printf("[MEMCTRL] Error fetching prompts: %v", err)
	}

	var promptIDs []int64
	for _, p := range prompts {
		promptIDs = append(promptIDs, p.ID)
	}

	respMap := make(map[int64]*ent.Response)
	if len(promptIDs) > 0 {
		responses, err := m.client.Response.Query().
			Where(response.PromptIDIn(promptIDs...)).
			All(ctx)
		if err != nil {
			logging.Printf("[MEMCTRL] Error fetching responses: %v", err)
		} else {
			for _, res := range responses {
				if res.PromptID != 0 {
					respMap[res.PromptID] = res
				}
			}
		}
	}

	// 3. Fetch Behavioral Rules (Iteration 9)
	rules, err := m.client.BehavioralRule.Query().
		Where(behavioralrule.StateEQ(behavioralrule.StateACTIVE)).
		All(ctx)
	if err != nil {
		logging.Printf("[MEMCTRL] Error fetching behavioral rules: %v", err)
	}

	// 3b. Fetch Session Overrides (Iteration 9b)
	overrides := make(map[int64]int)
	if sessionID > 0 {
		ovs, err := m.client.SessionGovernance.Query().
			Where(sessiongovernance.SessionID(sessionID)).
			All(ctx)
		if err == nil {
			for _, o := range ovs {
				overrides[o.RuleID] = o.PriorityOverride
			}
		}
	}

	// 4. Assemble MemoryPack
	pack := &contracts.MemoryPack{
		Items: []*contracts.MemoryWriteItem{},
	}

	// Add Behavioral Rules first (System instructions)
	// Apply overrides and filter/sort by priority
	type ruleWithPriority struct {
		rule     *ent.BehavioralRule
		priority int
	}
	var prioritizedRules []ruleWithPriority
	for _, rule := range rules {
		p := rule.Priority
		if ov, ok := overrides[rule.ID]; ok {
			p = ov
		}
		prioritizedRules = append(prioritizedRules, ruleWithPriority{rule: rule, priority: p})
	}

	// Sort by priority descending
	sort.Slice(prioritizedRules, func(i, j int) bool {
		return prioritizedRules[i].priority > prioritizedRules[j].priority
	})

	for _, pr := range prioritizedRules {
		pack.Items = append(pack.Items, &contracts.MemoryWriteItem{
			MemoryId:   pr.rule.ID,
			MemoryType: "behavioral_rule",
			Content:    pr.rule.RuleContent,
			Metadata: contracts.ToStruct(map[string]interface{}{
				"action_type": string(pr.rule.ActionType),
				"priority":    pr.priority,
				"scope":       string(pr.rule.Scope),
				"category":    pr.rule.Category,
			}),
		})
	}

	// Add MemoryItems
	for _, mi := range mItems {
		pack.Items = append(pack.Items, &contracts.MemoryWriteItem{
			MemoryId:      mi.ID,
			MemoryType:    mi.MemoryType,
			Summary:       mi.Summary,
			Content:       mi.Content,
			SalienceHint:  mi.Salience,
			RetentionHint: mi.RetentionScore,
			Pinned:        mi.Pinned,
			Metadata:      contracts.ToStruct(mi.Metadata),
		})
	}

	// Add History
	for i := len(prompts) - 1; i >= 0; i-- {
		p := prompts[i]
		pack.Items = append(pack.Items, &contracts.MemoryWriteItem{
			MemoryType: "chat_history",
			Content:    p.Content,
			Metadata: contracts.ToStruct(map[string]interface{}{
				"role":      "user",
				"timestamp": p.CreatedAt.Format(time.RFC3339),
				"id":        p.PromptID.String(),
			}),
		})

		if res, ok := respMap[p.ID]; ok {
			pack.Items = append(pack.Items, &contracts.MemoryWriteItem{
				MemoryType: "chat_history",
				Content:    res.Content,
				Metadata: contracts.ToStruct(map[string]interface{}{
					"role":      "assistant",
					"timestamp": res.CreatedAt.Format(time.RFC3339),
					"id":        res.ResponseID.String(),
				}),
			})
		}
	}

	return pack, nil
}
