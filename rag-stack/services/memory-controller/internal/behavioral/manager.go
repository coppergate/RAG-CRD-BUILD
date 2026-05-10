package behavioral

import (
	"context"
	"fmt"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/actionidentifier"
	"app-builds/common/ent/actiontype"
	"app-builds/common/ent/behaviorallog"
	"app-builds/common/ent/behavioralrule"
	"app-builds/common/ent/sessiongovernance"
)

type BehaviorManager struct {
	client *ent.Client
}

func NewBehaviorManager(client *ent.Client) *BehaviorManager {
	return &BehaviorManager{client: client}
}

// Rule Management

func (m *BehaviorManager) ListRules(ctx context.Context, actionType string) ([]*ent.BehavioralRule, error) {
	query := m.client.BehavioralRule.Query().Where(behavioralrule.StateEQ(behavioralrule.StateACTIVE))
	if actionType != "" {
		query = query.Where(behavioralrule.ActionType(actionType))
	}
	return query.Order(ent.Desc(behavioralrule.FieldPriority)).All(ctx)
}

func (m *BehaviorManager) CreateRule(ctx context.Context, actionType, content, category string, priority int, scope string, state string) (*ent.BehavioralRule, error) {
	// Option B: Check for existing rule with same content and actionType
	existing, err := m.client.BehavioralRule.Query().
		Where(behavioralrule.ActionType(actionType), behavioralrule.RuleContent(content)).
		First(ctx)

	if err == nil && existing != nil {
		// Rule exists, update it but set to PENDING if state is not ACTIVE
		return m.client.BehavioralRule.UpdateOne(existing).
			SetPriority(priority).
			SetCategory(category).
			SetScope(behavioralrule.Scope(scope)).
			SetState(behavioralrule.State(state)).
			SetUpdatedAt(time.Now()).
			Save(ctx)
	}

	return m.client.BehavioralRule.Create().
		SetActionType(actionType).
		SetRuleContent(content).
		SetCategory(category).
		SetPriority(priority).
		SetScope(behavioralrule.Scope(scope)).
		SetState(behavioralrule.State(state)).
		Save(ctx)
}

func (m *BehaviorManager) UpdateRule(ctx context.Context, id int64, content string, priority int, state string) (*ent.BehavioralRule, error) {
	return m.client.BehavioralRule.UpdateOneID(id).
		SetRuleContent(content).
		SetPriority(priority).
		SetState(behavioralrule.State(state)).
		SetUpdatedAt(time.Now()).
		Save(ctx)
}

// Auditing

func (m *BehaviorManager) LogRuleApplication(ctx context.Context, promptID string, ruleID int64, actionType string, metadata map[string]interface{}) error {
	_, err := m.client.BehavioralLog.Create().
		SetPromptID(promptID).
		SetRuleID(ruleID).
		SetActionType(actionType).
		SetContext(metadata).
		Save(ctx)
	return err
}

// Action Taxonomy Management (Iteration 9b)

func (m *BehaviorManager) GetActionIdentifiers(ctx context.Context) (map[string][]string, error) {
	types, err := m.client.ActionType.Query().WithIdentifiers().All(ctx)
	if err != nil {
		return nil, err
	}

	result := make(map[string][]string)
	for _, t := range types {
		var ids []string
		for _, identifier := range t.Edges.Identifiers {
			ids = append(ids, identifier.Identifier)
		}
		result[t.Name] = ids
	}
	return result, nil
}

// Session Governance (Iteration 9b)

func (m *BehaviorManager) SetSessionOverride(ctx context.Context, sessionID, ruleID int64, priority int) error {
	return m.client.SessionGovernance.Create().
		SetSessionID(sessionID).
		SetRuleID(ruleID).
		SetPriorityOverride(priority).
		OnConflictColumns(sessiongovernance.FieldSessionID, sessiongovernance.FieldRuleID).
		UpdatePriorityOverride().
		SetUpdatedAt(time.Now()).
		Exec(ctx)
}

func (m *BehaviorManager) GetSessionOverrides(ctx context.Context, sessionID int64) (map[int64]int, error) {
	overrides, err := m.client.SessionGovernance.Query().
		Where(sessiongovernance.SessionID(sessionID)).
		All(ctx)
	if err != nil {
		return nil, err
	}

	result := make(map[int64]int)
	for _, o := range overrides {
		result[o.RuleID] = o.PriorityOverride
	}
	return result, nil
}

func (m *BehaviorManager) ClearSessionOverrides(ctx context.Context, sessionID int64) error {
	_, err := m.client.SessionGovernance.Delete().
		Where(sessiongovernance.SessionID(sessionID)).
		Exec(ctx)
	return err
}

// Learning Loop (Initial Implementation)

func (m *BehaviorManager) RecordLearning(ctx context.Context, feedback string, actionType string, category string, priority int) (*ent.BehavioralRule, error) {
	// learned behaviors start as PENDING for user approval
	return m.CreateRule(ctx, actionType, feedback, category, priority, "GLOBAL", "PENDING")
}
