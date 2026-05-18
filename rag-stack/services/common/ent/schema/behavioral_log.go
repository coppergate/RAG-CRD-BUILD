package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"time"
)

// BehavioralLog holds the schema definition for the BehavioralLog entity.
type BehavioralLog struct {
	ent.Schema
}

// Fields of the BehavioralLog.
func (BehavioralLog) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.String("prompt_id").
			StorageKey("prompt_id"),
		field.Int64("rule_id").
			StorageKey("rule_id"),
		field.String("action_type").
			StorageKey("action_type"),
		field.Time("applied_at").
			Default(time.Now).
			Immutable().
			StorageKey("applied_at"),
		field.JSON("context", map[string]interface{}{}).
			Optional().
			StorageKey("context"),
	}
}

// Edges of the BehavioralLog.
func (BehavioralLog) Edges() []ent.Edge {
	return nil
}
