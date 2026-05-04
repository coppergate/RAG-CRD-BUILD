package schema

import (
"github.com/google/uuid"
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"time"
)

// Session holds the schema definition for the Session entity.
type Session struct {
	ent.Schema
}

// Fields of the Session.
func (Session) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("session_id"),
		field.Int64("project_id").
			Optional(),
		field.String("name").
			Unique().
			Optional(),
		field.String("description").
			Optional(),
		field.JSON("metadata", map[string]interface{}{}).
			Optional(),
		field.UUID("user_id", uuid.UUID{}).
			Optional(),
		field.Time("created_at").
			Default(time.Now),
		field.Time("last_active_at").
			Default(time.Now),
	}
}

// Edges of the Session.
func (Session) Edges() []ent.Edge {
	return []ent.Edge{
		edge.To("tags", Tag.Type).
			StorageKey(edge.Table("session_tag"), edge.Columns("session_id", "tag_id")),
		edge.To("metrics", ModelExecutionMetric.Type),
		edge.To("retrieval_logs", RetrievalLog.Type),
		edge.To("memory_events", MemoryEvent.Type),
		edge.To("memory_items", MemoryItem.Type),
	}
}
