package behavioral

import (
	"regexp"
	"strings"
)

type ActionType string

const (
	ActionFileSearch    ActionType = "FILE_SEARCH"
	ActionFileEdit      ActionType = "FILE_EDIT"
	ActionFileVCS       ActionType = "FILE_VCS"
	ActionRemoteExec    ActionType = "REMOTE_EXEC"
	ActionK8sOrchestrate ActionType = "K8S_ORCHESTRATE"
	ActionDBAccess      ActionType = "DB_ACCESS"
	ActionBuildDeploy   ActionType = "BUILD_DEPLOY"
	ActionDocProcess    ActionType = "DOC_PROCESS"
	ActionJobResume     ActionType = "JOB_RESUME"
	ActionWebFetch      ActionType = "WEB_FETCH"
	ActionUnknown       ActionType = "UNKNOWN"
)

// DetectActionType attempts to identify the ActionType based on keywords in the prompt.
func DetectActionType(prompt string, actionMap map[string][]string) string {
	p := strings.ToLower(prompt)

	if actionMap == nil {
		return "UNKNOWN"
	}

	for actionType, identifiers := range actionMap {
		if containsAny(p, identifiers...) {
			return actionType
		}
	}

	return "UNKNOWN"
}

type MemorySuggestion struct {
	Preposition string
	ActionType  string
	Instruction string
	Priority    int
	Category    string
}

var (
	// fixed set of prepositions
	prepositions = []string{"when", "before", "after", "during", "while", "once", "for"}
	// pattern: REMEMBER [PREPOSITION] [ACTION_TYPE] [INSTRUCTION]
	// where instruction might have markdown headers for priority
	rememberRegex = regexp.MustCompile(`(?i)REMEMBER\s+(WHEN|BEFORE|AFTER|DURING|WHILE|ONCE|FOR)\s+([A-Z0-9_]+)\s+(.*)`)
)

func DetectMemorySuggestion(prompt string) *MemorySuggestion {
	match := rememberRegex.FindStringSubmatch(prompt)
	if match == nil || len(match) < 4 {
		return nil
	}

	preposition := strings.ToUpper(match[1])
	actionType := strings.ToUpper(match[2])
	rawInstruction := strings.TrimSpace(match[3])

	// Parse priority from markdown headers
	priority := 0
	instruction := rawInstruction
	if strings.HasPrefix(rawInstruction, "###") {
		priority = 20
		instruction = strings.TrimSpace(strings.TrimPrefix(rawInstruction, "###"))
	} else if strings.HasPrefix(rawInstruction, "##") {
		priority = 50
		instruction = strings.TrimSpace(strings.TrimPrefix(rawInstruction, "##"))
	} else if strings.HasPrefix(rawInstruction, "#") {
		priority = 100
		instruction = strings.TrimSpace(strings.TrimPrefix(rawInstruction, "#"))
	}

	// Simple heuristic for category: if it looks like "CATEGORY - Instruction"
	category := ""
	if parts := strings.SplitN(instruction, "-", 2); len(parts) == 2 {
		category = strings.TrimSpace(parts[0])
		instruction = strings.TrimSpace(parts[1])
	}

	return &MemorySuggestion{
		Preposition: preposition,
		ActionType:  actionType,
		Instruction: instruction,
		Priority:    priority,
		Category:    category,
	}
}

func containsAny(s string, keywords ...string) bool {
	for _, k := range keywords {
		if strings.Contains(s, k) {
			return true
		}
	}
	return false
}
