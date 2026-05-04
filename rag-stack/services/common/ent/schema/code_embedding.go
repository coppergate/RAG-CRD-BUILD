package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"time"
)

// CodeEmbedding holds the schema definition for the CodeEmbedding entity.
type CodeEmbedding struct {
	ent.Schema
}

// Annotations of the CodeEmbedding.
func (CodeEmbedding) Annotations() []schema.Annotation {
	return []schema.Annotation{
		entsql.Annotation{Table: "code_embedding"},
	}
}

// Fields of the CodeEmbedding.
func (CodeEmbedding) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("embedding_id"),
		field.Int64("ingestion_id").
			Optional(),
		field.JSON("embedding_vector", []float32{}).
			Optional(),
		field.JSON("metadata", map[string]interface{}{}).
			Optional(),
		field.Time("created_at").
			Default(time.Now),
	}
}

// Edges of the CodeEmbedding.
func (CodeEmbedding) Edges() []ent.Edge {
	return []ent.Edge{
		edge.From("ingestion", CodeIngestion.Type).
			Ref("embeddings").
			Field("ingestion_id").
			Unique(),
		edge.To("tags", Tag.Type).
			StorageKey(edge.Table("code_embedding_tag"), edge.Columns("embedding_id", "tag_id")),
	}
}
