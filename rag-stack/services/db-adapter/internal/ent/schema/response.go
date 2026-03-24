package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"github.com/google/uuid"
	"time"
)

// Response holds the schema definition for the Response entity.
type Response struct {
	ent.Schema
}

// Fields of the Response.
func (Response) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.UUID("response_id", uuid.UUID{}).
			Default(uuid.New),
		field.Int64("prompt_id").
			Optional(),
		field.UUID("session_id", uuid.UUID{}).
			Optional(),
		field.Text("content"),
		field.Int("sequence_number"),
		field.String("model_name").
			Optional().
			Nillable(),
		field.Time("created_at").
			Default(time.Now).
			Immutable(),
		field.JSON("metadata", map[string]interface{}{}).
			Optional(),
	}
}

// Edges of the Response.
func (Response) Edges() []ent.Edge {
	return nil
}
