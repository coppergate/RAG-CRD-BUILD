package contracts

import (
	"google.golang.org/protobuf/types/known/structpb"
)

// ToStruct converts a map[string]interface{} to a google.protobuf.Struct
func ToStruct(m map[string]interface{}) *structpb.Struct {
	if m == nil {
		return nil
	}
	s, err := structpb.NewStruct(m)
	if err != nil {
		// Fallback for types that might not be directly compatible
		return nil
	}
	return s
}

// FromStruct converts a google.protobuf.Struct to a map[string]interface{}
func FromStruct(s *structpb.Struct) map[string]interface{} {
	if s == nil {
		return nil
	}
	return s.AsMap()
}

// ToValue converts an interface{} to a google.protobuf.Value
func ToValue(v interface{}) *structpb.Value {
	if v == nil {
		return structpb.NewNullValue()
	}
	val, err := structpb.NewValue(v)
	if err != nil {
		return structpb.NewNullValue()
	}
	return val
}

// FromValue converts a google.protobuf.Value to an interface{}
func FromValue(v *structpb.Value) interface{} {
	if v == nil {
		return nil
	}
	return v.AsInterface()
}
