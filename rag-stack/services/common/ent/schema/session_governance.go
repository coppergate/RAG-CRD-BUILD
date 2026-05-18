package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
	"time"
)

// SessionGovernance holds the schema definition for the SessionGovernance entity.
// This stores session-specific priority overrides for behavioral rules.
type SessionGovernance struct {
	ent.Schema
}

// Fields of the SessionGovernance.
func (SessionGovernance) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.Int64("session_id").
			StorageKey("session_id"),
		field.Int64("rule_id").
			StorageKey("rule_id"),
		field.Int("priority_override").
			StorageKey("priority_override"),
		field.Time("updated_at").
			Default(time.Now).
			UpdateDefault(time.Now).
			StorageKey("updated_at"),
	}
}

// Indexes of the SessionGovernance.
func (SessionGovernance) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("session_id", "rule_id").Unique(),
	}
}
