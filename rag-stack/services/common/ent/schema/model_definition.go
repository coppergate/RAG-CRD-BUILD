package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"github.com/google/uuid"
	"time"
)

// ModelDefinition holds the schema definition for the ModelDefinition entity.
type ModelDefinition struct {
	ent.Schema
}

// Fields of the ModelDefinition.
func (ModelDefinition) Fields() []ent.Field {
	return []ent.Field{
		field.UUID("id", uuid.UUID{}).
			Default(uuid.New).
			StorageKey("model_id"),
		field.String("model_name").
			Unique(),
		field.String("family").
			Optional(),
		field.Float32("parameters_billions").
			Optional(),
		field.String("quantization").
			Optional(),
		field.Time("created_at").
			Default(time.Now),
	}
}

// Edges of the ModelDefinition.
func (ModelDefinition) Edges() []ent.Edge {
	return []ent.Edge{
		edge.To("metrics", ModelExecutionMetric.Type),
	}
}
