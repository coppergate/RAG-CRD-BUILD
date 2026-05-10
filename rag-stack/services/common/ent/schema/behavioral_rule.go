package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"time"
)

// BehavioralRule holds the schema definition for the BehavioralRule entity.
type BehavioralRule struct {
	ent.Schema
}

// Fields of the BehavioralRule.
func (BehavioralRule) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.String("action_type").
			StorageKey("action_type"),
		field.String("category").
			Optional().
			StorageKey("category"),
		field.Enum("state").
			Values("PENDING", "ACTIVE", "REJECTED", "EXPIRED").
			Default("ACTIVE"). // Default to ACTIVE for existing rules
			StorageKey("state"),
		field.Text("rule_content").
			StorageKey("rule_content"),
		field.Int("priority").
			Default(0).
			StorageKey("priority"),
		field.Bool("is_active").
			Default(true).
			StorageKey("is_active"),
		field.Enum("scope").
			Values("GLOBAL", "PROJECT", "SESSION").
			Default("GLOBAL").
			StorageKey("scope"),
		field.Time("created_at").
			Default(time.Now).
			Immutable().
			StorageKey("created_at"),
		field.Time("updated_at").
			Default(time.Now).
			UpdateDefault(time.Now).
			StorageKey("updated_at"),
	}
}

// Edges of the BehavioralRule.
func (BehavioralRule) Edges() []ent.Edge {
	return nil
}
