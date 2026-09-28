package config

import (
	"testing"
)

func TestParseTransportDefaultsToOllama(t *testing.T) {
	// An unrecognised value must not silently disable embedding; default to the
	// path with the lowest floor.
	for _, in := range []string{"", "nonsense", "OLLAMA", " ollama "} {
		if got := parseTransport(in); got != TransportOllama {
			t.Errorf("parseTransport(%q) = %q, want ollama", in, got)
		}
	}
	for _, in := range []string{"gateway", "GATEWAY", " gateway "} {
		if got := parseTransport(in); got != TransportGateway {
			t.Errorf("parseTransport(%q) = %q, want gateway", in, got)
		}
	}
}

func TestSplitTags(t *testing.T) {
	cases := []struct {
		in   string
		want []string
	}{
		{"stack-docs", []string{"stack-docs"}},
		{"stack-docs,stack-go", []string{"stack-docs", "stack-go"}},
		{" stack-docs , stack-go ", []string{"stack-docs", "stack-go"}},
		{"stack-docs,,stack-go", []string{"stack-docs", "stack-go"}},
		{"", nil},
		{"   ", nil},
		{",,,", nil},
	}
	for _, c := range cases {
		got := splitTags(c.in)
		if len(got) != len(c.want) {
			t.Errorf("splitTags(%q) = %v, want %v", c.in, got, c.want)
			continue
		}
		for i := range got {
			if got[i] != c.want[i] {
				t.Errorf("splitTags(%q) = %v, want %v", c.in, got, c.want)
				break
			}
		}
	}
}

func TestLoadDefaults(t *testing.T) {
	cfg := Load()

	// The body cap is the one that bites: 1 MiB truncates coding-agent
	// payloads, so the default must be the larger value.
	if cfg.MaxBodyBytes != 32<<20 {
		t.Errorf("MaxBodyBytes = %d, want 32MiB", cfg.MaxBodyBytes)
	}
	// Executor retrieval must be narrower than planner retrieval (§5.5).
	if cfg.ExecutorTopK >= cfg.PlannerTopK {
		t.Errorf("executor top_k (%d) should be below planner top_k (%d)",
			cfg.ExecutorTopK, cfg.PlannerTopK)
	}
	if cfg.EmbedTransport != TransportOllama {
		t.Errorf("default transport = %q, want ollama", cfg.EmbedTransport)
	}
	// Qdrant is HTTPS-only on 6333; an http:// default reads as a dead service.
	if cfg.QdrantURL == "" {
		t.Error("QdrantURL must have a default")
	}
	if len(cfg.PlannerTags) == 0 || len(cfg.ExecutorTags) == 0 {
		t.Error("profile tag defaults must be populated")
	}
	if cfg.DefaultMaxTokens <= 0 {
		t.Error("RAG_INJECT_MAX_TOKENS must default above zero")
	}
}
