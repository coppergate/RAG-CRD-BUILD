package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/field"
	"entgo.io/ent/schema/index"
	"github.com/google/uuid"
	"time"
)

// MemoryLink holds the schema definition for the MemoryLink entity.
type MemoryLink struct {
	ent.Schema
}

// Fields of the MemoryLink.
func (MemoryLink) Fields() []ent.Field {
	return []ent.Field{
		field.UUID("id", uuid.UUID{}).
			Default(uuid.New).
			StorageKey("id"),
		field.UUID("memory_item_id", uuid.UUID{}).
			Comment("The associated memory item"),
		field.JSON("source_message_ids", []uuid.UUID{}).
			Optional().
			Comment("Provenance from chat messages"),
		field.JSON("ingestion_ids", []uuid.UUID{}).
			Optional().
			Comment("Provenance from ingested data"),
		field.JSON("tags", []string{}).
			Optional(),
		field.JSON("metadata", map[string]interface{}{}).
			Optional(),
		field.Time("created_at").
			Default(time.Now),
	}
}

// Edges of the MemoryLink.
func (MemoryLink) Edges() []ent.Edge {
	return nil
}

// Indexes of the MemoryLink.
func (MemoryLink) Indexes() []ent.Index {
	return []ent.Index{
		index.Fields("memory_item_id"),
	}
}
