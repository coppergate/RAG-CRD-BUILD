package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"github.com/google/uuid"
	"time"
)

// CodeIngestion holds the schema definition for the CodeIngestion entity.
type CodeIngestion struct {
	ent.Schema
}

// Fields of the CodeIngestion.
func (CodeIngestion) Fields() []ent.Field {
	return []ent.Field{
		field.UUID("id", uuid.UUID{}).
			Default(uuid.New).
			StorageKey("ingestion_id"),
		field.String("s3_bucket_id"),
		field.Time("created_at").
			Default(time.Now),
	}
}

// Edges of the CodeIngestion.
func (CodeIngestion) Edges() []ent.Edge {
	return []ent.Edge{
		edge.To("embeddings", CodeEmbedding.Type),
		edge.To("tags", Tag.Type).
			StorageKey(edge.Table("code_ingestion_tag"), edge.Columns("ingestion_id", "tag_id")),
	}
}
