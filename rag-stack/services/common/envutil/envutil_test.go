package envutil

import (
	"os"
	"testing"
	"time"
)

func TestGetEnv(t *testing.T) {
	tests := []struct {
		name     string
		key      string
		fallback string
		envVal   string
		setEnv   bool
		want     string
	}{
		{name: "returns fallback when not set", key: "TEST_GETENV_MISSING", fallback: "default", setEnv: false, want: "default"},
		{name: "returns env value when set", key: "TEST_GETENV_SET", fallback: "default", envVal: "custom", setEnv: true, want: "custom"},
		{name: "returns empty string when env is empty", key: "TEST_GETENV_EMPTY", fallback: "default", envVal: "", setEnv: true, want: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.setEnv {
				os.Setenv(tt.key, tt.envVal)
				defer os.Unsetenv(tt.key)
			} else {
				os.Unsetenv(tt.key)
			}
			if got := GetEnv(tt.key, tt.fallback); got != tt.want {
				t.Errorf("GetEnv(%q, %q) = %q, want %q", tt.key, tt.fallback, got, tt.want)
			}
		})
	}
}

func TestGetEnvInt(t *testing.T) {
	tests := []struct {
		name     string
		key      string
		fallback int
		envVal   string
		setEnv   bool
		want     int
	}{
		{name: "returns fallback when not set", key: "TEST_INT_MISSING", fallback: 42, setEnv: false, want: 42},
		{name: "returns parsed int", key: "TEST_INT_SET", fallback: 42, envVal: "100", setEnv: true, want: 100},
		{name: "returns fallback on invalid int", key: "TEST_INT_BAD", fallback: 42, envVal: "abc", setEnv: true, want: 42},
		{name: "handles zero", key: "TEST_INT_ZERO", fallback: 42, envVal: "0", setEnv: true, want: 0},
		{name: "handles negative", key: "TEST_INT_NEG", fallback: 42, envVal: "-5", setEnv: true, want: -5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.setEnv {
				os.Setenv(tt.key, tt.envVal)
				defer os.Unsetenv(tt.key)
			} else {
				os.Unsetenv(tt.key)
			}
			if got := GetEnvInt(tt.key, tt.fallback); got != tt.want {
				t.Errorf("GetEnvInt(%q, %d) = %d, want %d", tt.key, tt.fallback, got, tt.want)
			}
		})
	}
}

func TestGetEnvFloat(t *testing.T) {
	tests := []struct {
		name     string
		key      string
		fallback float64
		envVal   string
		setEnv   bool
		want     float64
	}{
		{name: "returns fallback when not set", key: "TEST_FLOAT_MISSING", fallback: 2.0, setEnv: false, want: 2.0},
		{name: "returns parsed float", key: "TEST_FLOAT_SET", fallback: 2.0, envVal: "3.5", setEnv: true, want: 3.5},
		{name: "returns fallback on invalid", key: "TEST_FLOAT_BAD", fallback: 2.0, envVal: "abc", setEnv: true, want: 2.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.setEnv {
				os.Setenv(tt.key, tt.envVal)
				defer os.Unsetenv(tt.key)
			} else {
				os.Unsetenv(tt.key)
			}
			if got := GetEnvFloat(tt.key, tt.fallback); got != tt.want {
				t.Errorf("GetEnvFloat(%q, %f) = %f, want %f", tt.key, tt.fallback, got, tt.want)
			}
		})
	}
}

func TestGetEnvDuration(t *testing.T) {
	tests := []struct {
		name     string
		key      string
		fallback time.Duration
		envVal   string
		setEnv   bool
		want     time.Duration
	}{
		{name: "returns fallback when not set", key: "TEST_DUR_MISSING", fallback: 30 * time.Second, setEnv: false, want: 30 * time.Second},
		{name: "returns parsed duration", key: "TEST_DUR_SET", fallback: 30 * time.Second, envVal: "2m", setEnv: true, want: 2 * time.Minute},
		{name: "returns fallback on invalid", key: "TEST_DUR_BAD", fallback: 30 * time.Second, envVal: "abc", setEnv: true, want: 30 * time.Second},
		{name: "handles seconds", key: "TEST_DUR_SEC", fallback: 30 * time.Second, envVal: "120s", setEnv: true, want: 120 * time.Second},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.setEnv {
				os.Setenv(tt.key, tt.envVal)
				defer os.Unsetenv(tt.key)
			} else {
				os.Unsetenv(tt.key)
			}
			if got := GetEnvDuration(tt.key, tt.fallback); got != tt.want {
				t.Errorf("GetEnvDuration(%q, %v) = %v, want %v", tt.key, tt.fallback, got, tt.want)
			}
		})
	}
}
