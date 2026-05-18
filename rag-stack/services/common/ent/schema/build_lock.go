package schema

import (
	"time"

	"entgo.io/ent"
	"entgo.io/ent/schema/field"
)

// BuildLock holds the schema definition for the BuildLock entity.
type BuildLock struct {
	ent.Schema
}

// Fields of the BuildLock.
func (BuildLock) Fields() []ent.Field {
	return []ent.Field{
		field.String("service_name").
			Unique().
			NotEmpty(),
		field.String("lock_owner").
			NotEmpty(),
		field.Int("lock_pid"),
		field.String("lock_host"),
		field.Time("acquired_at").
			Default(time.Now),
		field.Time("heartbeat").
			Default(time.Now),
	}
}

// Edges of the BuildLock.
func (BuildLock) Edges() []ent.Edge {
	return nil
}
