package contracts

import (
	"reflect"

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

	// Use reflection to handle any slice type (like []string)
	rv := reflect.ValueOf(v)
	if rv.Kind() == reflect.Slice {
		ii := make([]interface{}, rv.Len())
		for i := 0; i < rv.Len(); i++ {
			item := rv.Index(i).Interface()
			// Recursively handle nested slices if any
			if reflect.TypeOf(item) != nil && reflect.TypeOf(item).Kind() == reflect.Slice {
				val := ToValue(item)
				ii[i] = val.AsInterface()
			} else {
				ii[i] = item
			}
		}
		v = ii
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
