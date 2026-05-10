package behavioral

import (
	"context"
	"fmt"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/behavioralrule"
	"app-builds/common/ent/behaviorallog"
)

type BehaviorManager struct {
	client *ent.Client
}

func NewBehaviorManager(client *ent.Client) *BehaviorManager {
	return &BehaviorManager{client: client}
}

// Rule Management

func (m *BehaviorManager) ListRules(ctx context.Context, actionType string) ([]*ent.BehavioralRule, error) {
	query := m.client.BehavioralRule.Query().Where(behavioralrule.IsActive(true))
	if actionType != "" {
		query = query.Where(behavioralrule.ActionTypeEQ(behavioralrule.ActionType(actionType)))
	}
	return query.Order(ent.Desc(behavioralrule.FieldPriority)).All(ctx)
}

func (m *BehaviorManager) CreateRule(ctx context.Context, actionType, content string, priority int, scope string) (*ent.BehavioralRule, error) {
	return m.client.BehavioralRule.Create().
		SetActionType(behavioralrule.ActionType(actionType)).
		SetRuleContent(content).
		SetPriority(priority).
		SetScope(behavioralrule.Scope(scope)).
		Save(ctx)
}

func (m *BehaviorManager) UpdateRule(ctx context.Context, id int64, content string, priority int, active bool) (*ent.BehavioralRule, error) {
	return m.client.BehavioralRule.UpdateOneID(id).
		SetRuleContent(content).
		SetPriority(priority).
		SetIsActive(active).
		SetUpdatedAt(time.Now()).
		Save(ctx)
}

// Auditing

func (m *BehaviorManager) LogRuleApplication(ctx context.Context, promptID string, ruleID int64, actionType string, metadata map[string]interface{}) error {
	_, err := m.client.BehavioralLog.Create().
		SetPromptID(promptID).
		SetRuleID(ruleID).
		SetActionType(behaviorallog.ActionType(actionType)).
		SetContext(metadata).
		Save(ctx)
	return err
}

// Learning Loop (Initial Implementation)

func (m *BehaviorManager) RecordLearning(ctx context.Context, feedback string, actionType string) (*ent.BehavioralRule, error) {
	// In a real implementation, we might use an LLM to refine the feedback into a structured rule.
	// For now, we store it as a high-priority "LEARNED" rule for the specified action type.
	return m.CreateRule(ctx, actionType, fmt.Sprintf("LEARNED BEHAVIOR: %s", feedback), 100, "GLOBAL")
}
