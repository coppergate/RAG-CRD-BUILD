package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
	"time"
)

// MemoryEvent holds the schema definition for the MemoryEvent entity.
type MemoryEvent struct {
	ent.Schema
}

// Fields of the MemoryEvent.
func (MemoryEvent) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.Int64("memory_item_id").
			Comment("The associated memory item"),
		field.Int64("session_id").
			Optional().
			Comment("The associated session for easier auditing"),
		field.String("event_type").
			Comment("write, update, prune, audit"),
		field.JSON("event_data", map[string]interface{}{}).
			Optional(),
		field.Time("created_at").
			Default(time.Now).
			Immutable(),
	}
}

// Edges of the MemoryEvent.
func (MemoryEvent) Edges() []ent.Edge {
	return []ent.Edge{
		edge.From("session", Session.Type).
			Ref("memory_events").
			Field("session_id").
			Unique(),
		edge.From("memory_item", MemoryItem.Type).
			Ref("events").
			Field("memory_item_id").
			Unique().
			Required(),
	}
}

// Indexes of the MemoryEvent.
func (MemoryEvent) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("memory_item_id"),
		index.Fields("event_type"),
		index.Fields("created_at"),
	}
}
