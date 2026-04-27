package envutil

import (
	"fmt"
	"os"
	"time"
)

// GetEnv returns the value of the environment variable named by key,
// or fallback if the variable is not set.
func GetEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

// GetEnvInt returns the integer value of the environment variable named by key,
// or fallback if the variable is not set or cannot be parsed.
func GetEnvInt(key string, fallback int) int {
	if value, ok := os.LookupEnv(key); ok {
		var i int
		if _, err := fmt.Sscanf(value, "%d", &i); err == nil {
			return i
		}
	}
	return fallback
}

// GetEnvFloat returns the float64 value of the environment variable named by key,
// or fallback if the variable is not set or cannot be parsed.
func GetEnvFloat(key string, fallback float64) float64 {
	if value, ok := os.LookupEnv(key); ok {
		var f float64
		if _, err := fmt.Sscanf(value, "%f", &f); err == nil {
			return f
		}
	}
	return fallback
}

// GetEnvDuration returns the time.Duration value of the environment variable named by key,
// or fallback if the variable is not set or cannot be parsed.
// The value should be in Go duration format (e.g., "30s", "2m", "120s").
func GetEnvDuration(key string, fallback time.Duration) time.Duration {
	if value, ok := os.LookupEnv(key); ok {
		if d, err := time.ParseDuration(value); err == nil {
			return d
		}
	}
	return fallback
}
