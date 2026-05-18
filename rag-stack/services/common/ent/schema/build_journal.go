package schema

import (
	"time"

	"entgo.io/ent"
	"entgo.io/ent/schema/field"
)

// BuildJournal holds the schema definition for the BuildJournal entity.
type BuildJournal struct {
	ent.Schema
}

// Fields of the BuildJournal.
func (BuildJournal) Fields() []ent.Field {
	return []ent.Field{
		field.String("service_name").
			Unique().
			NotEmpty(),
		field.String("last_hash").
			NotEmpty(),
		field.Time("updated_at").
			Default(time.Now).
			UpdateDefault(time.Now),
	}
}

// Edges of the BuildJournal.
func (BuildJournal) Edges() []ent.Edge {
	return nil
}
