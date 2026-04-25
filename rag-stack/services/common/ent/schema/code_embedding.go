package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"github.com/google/uuid"
	"time"
)

// CodeEmbedding holds the schema definition for the CodeEmbedding entity.
type CodeEmbedding struct {
	ent.Schema
}

// Fields of the CodeEmbedding.
func (CodeEmbedding) Fields() []ent.Field {
	return []ent.Field{
		field.UUID("id", uuid.UUID{}).
			Default(uuid.New).
			StorageKey("embedding_id"),
		field.UUID("ingestion_id", uuid.UUID{}).
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
