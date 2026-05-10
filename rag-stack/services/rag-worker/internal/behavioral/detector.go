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
func DetectActionType(prompt string) ActionType {
	p := strings.ToLower(prompt)

	if containsAny(p, "resume", "cover letter", "qualifications", "job req") {
		return ActionJobResume
	}
	if containsAny(p, "kubernetes", "kubectl", "k8s", "pod", "deployment", "service", "namespace", "talosctl") {
		return ActionK8sOrchestrate
	}
	if containsAny(p, "git", "branch", "commit", "push", "pull request", "vcs") {
		return ActionFileVCS
	}
	if containsAny(p, "edit", "modify", "change", "update file", "search_replace", "multi_edit") {
		return ActionFileEdit
	}
	if containsAny(p, "search", "find", "grep", "token", "pattern") {
		return ActionFileSearch
	}
	if containsAny(p, "ssh", "hierophant", "remote", "execute on host") {
		return ActionRemoteExec
	}
	if containsAny(p, "build", "deploy", "package", "kaniko", "version") {
		return ActionBuildDeploy
	}
	if containsAny(p, "database", "sql", "psql", "query", "timescaledb", "select ", "insert ", "update ") {
		return ActionDBAccess
	}
	if containsAny(p, "pdf", "pdftotext", "paps", "document") {
		return ActionDocProcess
	}
	if containsAny(p, "http", "get ", "post ", "url", "curl", "wget", "fetch") {
		return ActionWebFetch
	}

	return ActionUnknown
}

func containsAny(s string, keywords ...string) bool {
	for _, k := range keywords {
		if strings.Contains(s, k) {
			return true
		}
	}
	return false
}
