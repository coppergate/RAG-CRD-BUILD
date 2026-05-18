package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
)

// ActionType holds the schema definition for the ActionType entity.
type ActionType struct {
	ent.Schema
}

// Fields of the ActionType.
func (ActionType) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.String("name").
			Unique().
			StorageKey("name"),
		field.String("description").
			Optional().
			StorageKey("description"),
	}
}

// Edges of the ActionType.
func (ActionType) Edges() []ent.Edge {
	return []ent.Edge{
		edge.To("identifiers", ActionIdentifier.Type),
	}
}
