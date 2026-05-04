package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"time"
)

// InferenceNode holds the schema definition for the InferenceNode entity.
type InferenceNode struct {
	ent.Schema
}

// Fields of the InferenceNode.
func (InferenceNode) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("node_id"),
		field.String("hostname").
			Unique(),
		field.String("ip_address").
			Optional(),
		field.String("gpu_model").
			Optional(),
		field.Int("total_vram_mb").
			Optional(),
		field.Time("created_at").
			Default(time.Now),
	}
}

// Edges of the InferenceNode.
func (InferenceNode) Edges() []ent.Edge {
	return []ent.Edge{
		edge.To("metrics", ModelExecutionMetric.Type),
	}
}
