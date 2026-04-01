package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
	"github.com/google/uuid"
	"time"
)

// MemoryItem holds the schema definition for the MemoryItem entity.
type MemoryItem struct {
	ent.Schema
}

// Fields of the MemoryItem.
func (MemoryItem) Fields() []ent.Field {
	return []ent.Field{
		field.UUID("id", uuid.UUID{}).
			Default(uuid.New).
			StorageKey("id"),
		field.UUID("tenant_id", uuid.UUID{}).
			Optional(),
		field.UUID("session_id", uuid.UUID{}).
			Optional(),
		field.UUID("user_id", uuid.UUID{}).
			Optional(),
		field.String("type").
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
		field.Bool("pinning").
			Default(false),
		field.Int64("ttl").
			Optional().
			Comment("TTL in seconds"),
		field.Time("created_at").
			Default(time.Now),
		field.Time("updated_at").
			Default(time.Now).
			UpdateDefault(time.Now),
	}
}

// Edges of the MemoryItem.
func (MemoryItem) Edges() []ent.Edge {
	return nil
}

// Indexes of the MemoryItem.
func (MemoryItem) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("tenant_id"),
		index.Fields("session_id"),
		index.Fields("user_id"),
		index.Fields("type"),
		index.Fields("status"),
	}
}
