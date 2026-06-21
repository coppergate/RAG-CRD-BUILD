package schema

import (
	"time"

	"entgo.io/ent"
	"entgo.io/ent/dialect/entsql"
	"entgo.io/ent/schema"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
)

// TagEmbeddingCoverage holds the schema definition for the TagEmbeddingCoverage entity.
type TagEmbeddingCoverage struct {
	ent.Schema
}

// Annotations of the TagEmbeddingCoverage.
func (TagEmbeddingCoverage) Annotations() []schema.Annotation {
	return []schema.Annotation{
		entsql.Annotation{Table: "tag_embedding_coverage"},
	}
}

// Fields of the TagEmbeddingCoverage.
func (TagEmbeddingCoverage) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("tag_id"),
		field.String("embedding_model").MaxLen(100),
		field.Int("vector_dims"),
		field.Int64("vector_count").Default(0),
		field.Int("file_count").Default(0),
		field.String("status").Default("pending"),
		// status values: pending | building | complete | stale
		field.Time("last_embedded_at").Optional().Nillable(),
		field.Time("created_at").
			Default(time.Now).
			Immutable(),
		field.Time("updated_at").
			Default(time.Now),
	}
}

// Edges of the TagEmbeddingCoverage.
func (TagEmbeddingCoverage) Edges() []ent.Edge {
	return []ent.Edge{
		edge.From("tag", Tag.Type).
			Ref("embedding_coverages").
			Field("tag_id").
			Unique().
			Required(),
	}
}

// Indexes of the TagEmbeddingCoverage.
func (TagEmbeddingCoverage) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("tag_id", "embedding_model").Unique(),
		index.Fields("status"),
	}
}
