package contracts

import (
	"reflect"

	"google.golang.org/protobuf/types/known/structpb"
)

// ToStruct converts a map[string]interface{} to a google.protobuf.Struct.
// It recursively handles slice types that structpb.NewStruct might not support (like []string).
func ToStruct(m map[string]interface{}) *structpb.Struct {
	if m == nil {
		return nil
	}

	// Pre-process the map to ensure all slices are []interface{}
	cleanMap := make(map[string]interface{})
	for k, v := range m {
		cleanMap[k] = prepareForStruct(v)
	}

	s, err := structpb.NewStruct(cleanMap)
	if err != nil {
		return nil
	}
	return s
}

func prepareForStruct(v interface{}) interface{} {
	if v == nil {
		return nil
	}

	rv := reflect.ValueOf(v)
	if rv.Kind() == reflect.Slice {
		ii := make([]interface{}, rv.Len())
		for i := 0; i < rv.Len(); i++ {
			ii[i] = prepareForStruct(rv.Index(i).Interface())
		}
		return ii
	}

	if rv.Kind() == reflect.Map {
		mi := make(map[string]interface{})
		for _, key := range rv.MapKeys() {
			if k, ok := key.Interface().(string); ok {
				mi[k] = prepareForStruct(rv.MapIndex(key).Interface())
			}
		}
		return mi
	}

	return v
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
