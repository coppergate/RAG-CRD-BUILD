package profile

import "testing"

func TestDeriveFromAgent(t *testing.T) {
	cases := []struct {
		agent string
		want  Profile
	}{
		{"plan", Planner},
		{"PLAN", Planner},
		{"build", Executor},
		{"title", None},
		{"", Planner}, // no agent, no model: broad is the safe default
	}
	for _, c := range cases {
		if got := Derive(Auto, c.agent, ""); got != c.want {
			t.Errorf("Derive(Auto, %q, \"\") = %q, want %q", c.agent, got, c.want)
		}
	}
}

func TestDeriveFallsBackToModel(t *testing.T) {
	// §5.5: the agent name is absent from system.transform, so the model id is
	// the documented fallback. These are the models actually seeded.
	cases := []struct {
		model string
		want  Profile
	}{
		{"qwen3:32b", Planner},
		{"devstral-small-2:24b", Executor},
		{"qwen2.5-coder:32b", Executor},
		{"llama3.2:3b", None},
		{"all-minilm:l6-v2", None},
	}
	for _, c := range cases {
		if got := Derive(Auto, "", c.model); got != c.want {
			t.Errorf("Derive(Auto, \"\", %q) = %q, want %q", c.model, got, c.want)
		}
	}
}

func TestAgentBeatsModel(t *testing.T) {
	// A plan agent running on the executor model is still planning.
	if got := Derive(Auto, "plan", "devstral-small-2:24b"); got != Planner {
		t.Errorf("agent should win over model, got %q", got)
	}
}

func TestExplicitProfileWins(t *testing.T) {
	if got := Derive(Executor, "plan", "qwen3:32b"); got != Executor {
		t.Errorf("explicit profile should override derivation, got %q", got)
	}
}

func TestParseIsForgiving(t *testing.T) {
	// A bad hint must never be an error — retrieval degrades, it does not fail.
	if got := Parse("nonsense"); got != Auto {
		t.Errorf("Parse(nonsense) = %q, want auto", got)
	}
	if got := Parse("off"); got != None {
		t.Errorf("Parse(off) = %q, want none", got)
	}
}
