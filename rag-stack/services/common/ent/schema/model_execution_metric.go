package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"time"
)

// ModelExecutionMetric holds the schema definition for the ModelExecutionMetric entity.
type ModelExecutionMetric struct {
	ent.Schema
}

// Fields of the ModelExecutionMetric.
func (ModelExecutionMetric) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("metric_id"),
		field.Int64("response_id").
			Optional(),
		field.Int64("session_id").
			Optional(),
		field.Int64("node_id").
			Optional(),
		field.Int64("model_id").
			Optional(),
		field.Int("prompt_tokens").
			Optional(),
		field.Int("completion_tokens").
			Optional(),
		field.Int("total_tokens").
			Optional(),
		field.Int64("total_duration_usec").
			Optional(),
		field.Int64("load_duration_usec").
			Optional(),
		field.Int64("prompt_eval_duration_usec").
			Optional(),
		field.Int64("eval_duration_usec").
			Optional(),
		field.Float32("tokens_per_second").
			Optional(),
		field.Time("created_at").
			Default(time.Now).
			Immutable(),
	}
}

// Edges of the ModelExecutionMetric.
func (ModelExecutionMetric) Edges() []ent.Edge {
	return []ent.Edge{
		edge.From("session", Session.Type).
			Ref("metrics").
			Field("session_id").
			Unique(),
		edge.From("node", InferenceNode.Type).
			Ref("metrics").
			Field("node_id").
			Unique(),
		edge.From("model", ModelDefinition.Type).
			Ref("metrics").
			Field("model_id").
			Unique(),
	}
}
