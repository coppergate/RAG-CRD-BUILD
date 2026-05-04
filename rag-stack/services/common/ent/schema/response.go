package schema

import (
"github.com/google/uuid"
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
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
			Optional().
			Unique(),
		field.Int64("session_id").
			Optional(),
		field.Text("content"),
		field.Text("planning_response").
			Optional().
			Nillable(),
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

// Indexes of the Response.
func (Response) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("prompt_id").Unique(),
	}
}

// Edges of the Response.
func (Response) Edges() []ent.Edge {
	return nil
}
