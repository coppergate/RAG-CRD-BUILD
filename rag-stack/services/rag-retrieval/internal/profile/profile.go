// Package profile decides how broad a retrieval should be, from the agent and
// model identifying the request (spec §5.5).
package profile

import "strings"

type Profile string

const (
	// Planner: broad and architectural — design docs, prior decisions, memory.
	Planner Profile = "planner"
	// Executor: narrow and precise — code spans, no prose, no memory.
	Executor Profile = "executor"
	// None: skip retrieval entirely (title generation and other small-model work).
	None Profile = "none"
	// Auto: derive from agent, then model.
	Auto Profile = "auto"
)

// Parse normalises an explicit profile request. Anything unrecognised becomes
// Auto rather than an error — retrieval must never fail on a bad hint.
func Parse(v string) Profile {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "planner":
		return Planner
	case "executor":
		return Executor
	case "none", "off":
		return None
	default:
		return Auto
	}
}

// Derive resolves Auto using the agent name first, then the model id. The agent
// is the better signal but is absent from system.transform, so model is the
// documented fallback (§5.5 Option B).
func Derive(requested Profile, agent, model string) Profile {
	if requested != Auto && requested != "" {
		return requested
	}

	switch strings.ToLower(strings.TrimSpace(agent)) {
	case "plan", "planner", "architect":
		return Planner
	case "build", "builder", "executor", "code":
		return Executor
	case "title", "summarize", "summary":
		return None
	}

	m := strings.ToLower(model)
	switch {
	case m == "":
		return Planner
	// Reasoning/planning families.
	case strings.Contains(m, "qwen3"), strings.Contains(m, "qwen2.5:"):
		return Planner
	// Coding families.
	case strings.Contains(m, "devstral"), strings.Contains(m, "coder"), strings.Contains(m, "codellama"):
		return Executor
	// Small CPU models only ever do titles.
	case strings.Contains(m, "3.2:3b"), strings.Contains(m, ":1b"), strings.Contains(m, "minilm"):
		return None
	default:
		return Planner
	}
}
