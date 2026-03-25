package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"github.com/google/uuid"
	"time"
)

// Session holds the schema definition for the Session entity.
type Session struct {
	ent.Schema
}

// Fields of the Session.
func (Session) Fields() []ent.Field {
	return []ent.Field{
		field.UUID("id", uuid.UUID{}).
			Default(uuid.New).
			StorageKey("session_id"),
		field.UUID("project_id", uuid.UUID{}).
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
	return nil
}
