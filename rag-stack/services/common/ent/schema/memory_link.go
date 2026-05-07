package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
	"time"
)

// MemoryLink holds the schema definition for the MemoryLink entity.
type MemoryLink struct {
	ent.Schema
}

// Fields of the MemoryLink.
func (MemoryLink) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.Int64("memory_item_id").
			Comment("The associated memory item"),
		field.JSON("source_message_ids", []int64{}).
			Optional().
			Comment("Provenance from chat messages"),
		field.JSON("ingestion_ids", []int64{}).
			Optional().
			Comment("Provenance from ingested data"),
		field.JSON("tags", []int64{}).
			Optional(),
		field.JSON("metadata", map[string]interface{}{}).
			Optional(),
		field.Time("created_at").
			Default(time.Now),
	}
}

// Edges of the MemoryLink.
func (MemoryLink) Edges() []ent.Edge {
	return []ent.Edge{
		edge.To("memory_item", MemoryItem.Type).
			Field("memory_item_id").
			Unique().
			Required(),
	}
}

// Indexes of the MemoryLink.
func (MemoryLink) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("memory_item_id"),
	}
}
