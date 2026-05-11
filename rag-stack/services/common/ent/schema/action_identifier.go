package schema

import (
	"entgo.io/ent"
	"entgo.io/ent/schema/edge"
	"entgo.io/ent/schema/field"
)

// ActionIdentifier holds the schema definition for the ActionIdentifier entity.
type ActionIdentifier struct {
	ent.Schema
}

// Fields of the ActionIdentifier.
func (ActionIdentifier) Fields() []ent.Field {
	return []ent.Field{
		field.Int64("id").
			StorageKey("id"),
		field.String("identifier").
			StorageKey("identifier"),
	}
}

// Edges of the ActionIdentifier.
func (ActionIdentifier) Edges() []ent.Edge {
	return []ent.Edge{
		edge.From("action_type", ActionType.Type).
			Ref("identifiers").
			Unique().
			Required(),
	}
}
