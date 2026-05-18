package schema

import (
"github.com/google/uuid"
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"time"
)

// Prompt holds the schema definition for the Prompt entity.
type Prompt struct {
	ent.Schema
}

// Fields of the Prompt.
func (Prompt) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.UUID("prompt_id", uuid.UUID{}).
			Default(uuid.New),
		field.Int64("session_id").
			Optional(),
		field.Text("content"),
		field.Time("created_at").
			Default(time.Now).
			Immutable(),
		field.JSON("metadata", map[string]interface{}{}).
			Optional(),
	}
}

// Edges of the Prompt.
func (Prompt) Edges() []ent.Edge {
	return nil
}
