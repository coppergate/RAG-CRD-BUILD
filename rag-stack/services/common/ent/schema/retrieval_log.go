package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"github.com/google/uuid"
	"time"
)

// RetrievalLog holds the schema definition for the RetrievalLog entity.
type RetrievalLog struct {
	ent.Schema
}

// Fields of the RetrievalLog.
func (RetrievalLog) Fields() []ent.Field {
	return []ent.Field{
		field.UUID("id", uuid.UUID{}).
			Default(uuid.New).
			StorageKey("log_id"),
		field.UUID("message_id", uuid.UUID{}).
			Optional(),
		field.UUID("session_id", uuid.UUID{}).
			Optional(),
		field.Text("query").
			Optional(),
		field.JSON("retrieved_chunks", []map[string]interface{}{}).
			Optional(),
		field.Time("created_at").
			Default(time.Now),
	}
}

// Edges of the RetrievalLog.
func (RetrievalLog) Edges() []ent.Edge {
	return []ent.Edge{
		edge.From("session", Session.Type).
			Ref("retrieval_logs").
			Field("session_id").
			Unique(),
	}
}
