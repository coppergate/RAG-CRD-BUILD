package schema

import (
	"time"

	"entgo.io/ent"
	"entgo.io/ent/schema/field"
)

// BuildVersion holds the schema definition for the BuildVersion entity.
type BuildVersion struct {
	ent.Schema
}

// Fields of the BuildVersion.
func (BuildVersion) Fields() []ent.Field {
	return []ent.Field{
		field.String("service_name").
			Unique().
			NotEmpty(),
		field.String("version").
			NotEmpty(),
		field.Time("last_build").
			Default(time.Now),
	}
}

// Edges of the BuildVersion.
func (BuildVersion) Edges() []ent.Edge {
	return nil
}
