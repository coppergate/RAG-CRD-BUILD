package main

import (
	"context"
	"os"

	"app-builds/common/ent"
	"app-builds/common/ent/actiontype"
	_ "github.com/lib/pq"
	"app-builds/common/logging"
)

func main() {
	dbConn := os.Getenv("DB_CONN_STRING")
	if dbConn == "" {
		dbConn = "postgres://app:VPbdmQ0HcczUUOb819opOpRWcSviKbyxTj1ng1WS4DCWSTH6ktVRXky7f7KsScUv@timescaledb-rw.timescaledb.svc.cluster.local:5432/app?sslmode=disable"
	}

	client, err := ent.Open("postgres", dbConn)
	if err != nil {
		logging.Fatalf("failed opening connection to postgres: %v", err)
	}
	defer client.Close()

	ctx := context.Background()

	// 1. Seed Action Types and Identifiers
	taxonomy := map[string][]string{
		"FILE_SEARCH":     {"search", "find", "grep", "token", "pattern"},
		"FILE_EDIT":       {"edit", "modify", "change", "update file", "search_replace", "multi_edit"},
		"FILE_VCS":        {"git", "branch", "commit", "push", "pull request", "vcs"},
		"REMOTE_EXEC":     {"ssh", "hierophant", "remote", "execute on host"},
		"K8S_ORCHESTRATE": {"kubernetes", "kubectl", "k8s", "pod", "deployment", "service", "namespace", "talosctl"},
		"DB_ACCESS":       {"database", "sql", "psql", "query", "timescaledb", "select ", "insert ", "update "},
		"BUILD_DEPLOY":    {"build", "deploy", "package", "kaniko", "version"},
		"DOC_PROCESS":     {"pdf", "pdftotext", "paps", "document"},
		"JOB_RESUME":      {"resume", "cover letter", "qualifications", "job req"},
		"WEB_FETCH":       {"http", "get ", "post ", "url", "curl", "wget", "fetch"},
	}

	for atName, identifiers := range taxonomy {
		at, err := client.ActionType.Query().Where(actiontype.NameEQ(atName)).Only(ctx)
		if err != nil {
			at, err = client.ActionType.Create().SetName(atName).Save(ctx)
			if err != nil {
				logging.Fatalf("failed creating action type %s: %v", atName, err)
			}
		}

		for _, id := range identifiers {
			err = client.ActionIdentifier.Create().
				SetActionType(at).
				SetIdentifier(id).
				Exec(ctx)
			if err != nil {
				logging.Printf("Warning: failed creating identifier %s for %s: %v", id, atName, err)
			}
		}
	}

	// 2. Seed Initial Rules
	rules := []struct {
		ActionType string
		Category   string
		Content    string
		Priority   int
	}{
		{"FILE_EDIT", "Safety", "If an edit process involves more than 5 lines of code, store the original file in a sub-directory matching its current structure under the '/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/ai-changes/original' directory, and create a new file with the edited content.", 100},
		{"FILE_VCS", "Policy", "Create a local git branch every day named work-YYYY-MM-DD (e.g., work-2026-03-02).", 80},
		{"FILE_VCS", "Policy", "Commit all changes to the local branch in git any time changes are made with simple timestamp (e.g., 2026-03-02 08:30).", 80},
		{"FILE_VCS", "Policy", "Always add the following trailer to git commits: Accomplished with a little help from my AI buddies", 100},
		{"K8S_ORCHESTRATE", "Policy", "Use the Krew rook-ceph kubectl plugin when available (kubectl rook-ceph ceph -n rook-ceph <cmd>), with a safe fallback to kubectl exec.", 70},
		{"K8S_ORCHESTRATE", "Paths", "When running kubectl on hierophant, use: /home/k8s/kube/kubectl with KUBECONFIG=/home/k8s/kube/config/kubeconfig", 100},
		{"K8S_ORCHESTRATE", "Architecture", "Use service names and not IP addresses for interservice calls on k8s.", 90},
		{"REMOTE_EXEC", "Security", "When accessing hierophant from the environment, ALWAYS use the private key ~/.ssh/id_hierophant_access and the user junie.", 100},
		{"REMOTE_EXEC", "Policy", "Use non-interactive SSH/Kubernetes patterns to avoid hangs on password prompts.", 90},
		{"JOB_RESUME", "Authenticity", "The RAG pipeline and related AI stack are personal projects. Do not attribute them to previous employers.", 100},
		{"JOB_RESUME", "Authenticity", "Do NOT add any statements claiming experience, skills, or achievements that are not expressly found in the source documents.", 100},
		{"BUILD_DEPLOY", "Versioning", "Maintain a major.minor.build versioning scheme starting with 1.0.0. Increment build for service updates, minor for Iterations.", 90},
		{"DOC_PROCESS", "Tools", "Use paps for converting text files to PDF and pdftotext for extraction.", 80},
	}

	for _, r := range rules {
		_, err = client.BehavioralRule.Create().
			SetActionType(r.ActionType).
			SetCategory(r.Category).
			SetRuleContent(r.Content).
			SetPriority(r.Priority).
			SetState("ACTIVE").
			Save(ctx)
		if err != nil {
			logging.Printf("Warning: failed creating rule for %s: %v", r.ActionType, err)
		}
	}

	logging.Println("Seeding complete.")
}
