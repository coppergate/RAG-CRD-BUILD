package schema

import (
"github.com/google/uuid"
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
	"time"
)

// MemoryItem holds the schema definition for the MemoryItem entity.
type MemoryItem struct {
	ent.Schema
}

// Fields of the MemoryItem.
func (MemoryItem) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.Int64("project_id").
			Optional(),
		field.Int64("session_id").
			Optional(),
		field.UUID("user_id", uuid.UUID{}).
			Optional(),
		field.String("memory_type").
			Comment("short_term_memory, long_term_memory, persistent_memory"),
		field.Text("summary"),
		field.Text("content").
			Optional(),
		field.Float("salience").
			Default(0.0),
		field.Float("retention_score").
			Default(1.0),
		field.JSON("decay_state", map[string]interface{}{}).
			Optional(),
		field.String("status").
			Default("active").
			Comment("active, pruned, etc."),
		field.Bool("pinned").
			Default(false),
		field.Time("expires_at").
			Optional().
			Comment("TTL or expiry timestamp"),
		field.JSON("metadata", map[string]interface{}{}).
			Optional(),
		field.Time("created_at").
			Default(time.Now),
		field.Time("updated_at").
			Default(time.Now).
			UpdateDefault(time.Now),
	}
}

// Edges of the MemoryItem.
func (MemoryItem) Edges() []ent.Edge {
	return []ent.Edge{
		edge.From("session", Session.Type).
			Ref("memory_items").
			Field("session_id").
			Unique(),
		edge.To("links", MemoryLink.Type),
		edge.To("events", MemoryEvent.Type),
	}
}

// Indexes of the MemoryItem.
func (MemoryItem) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("project_id"),
		index.Fields("session_id"),
		index.Fields("user_id"),
		index.Fields("memory_type"),
		index.Fields("status"),
	}
}
