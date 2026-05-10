package behavioral

import (
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

func containsAny(s string, keywords ...string) bool {
	for _, k := range keywords {
		if strings.Contains(s, k) {
			return true
		}
	}
	return false
}
