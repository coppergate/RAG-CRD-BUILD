package schema

import (
	"time"

	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
)

// AgentSession maps an opaque external agent session id (opencode's "ses_…")
// onto the int64 session identity the rest of the stack keys on.
type AgentSession struct {
	ent.Schema
}

// Annotations of the AgentSession.
func (AgentSession) Annotations() []schema.Annotation {
	return []schema.Annotation{
		entsql.Annotation{Table: "agent_session"},
	}
}

// Fields of the AgentSession.
func (AgentSession) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("agent_session_id"),
		field.Text("external_id").
			Unique().
			StorageKey("external_id"),
		field.String("source").
			Default("opencode"),
		field.Time("created_at").
			Default(time.Now).
			Immutable(),
		field.Time("last_seen_at").
			Default(time.Now),
	}
}

// Edges of the AgentSession.
func (AgentSession) Edges() []ent.Edge {
	return []ent.Edge{
		edge.To("session", Session.Type).
			Unique().
			Required().
			StorageKey(edge.Column("session_id")),
	}
}
