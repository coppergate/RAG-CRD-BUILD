## Iteration 9: Behavioral Long-Term Memory and Action Governance - PLANNED

### Objective
Implement a structured, database-backed "Behavioral Long-Term Memory" system to govern agent actions. This system replaces static markdown-based rules (`guidelines.md` and `OPERATIONS.md`) with dynamic, context-aware prompt injection based on the specific type of action being planned or executed.

### Scope
- **Governance Database**: Implement a schema in TimescaleDB (using Ent) to store operational rules linked to specific "Action Types".
- **Action Taxonomy**: Define a standardized set of 10 core action types that the agent can perform.
- **Dynamic Context Injection**: Update the `rag-worker` pipeline to fetch and inject relevant behavioral rules into the Planner and Executor prompts based on the current sub-task.
- **Feedback Loop**: Allow the agent to record "Learned Behaviors" or "Corrective Guidelines" back into the database when user feedback is received.

### Action Taxonomy
The following Action Types have been identified for immediate support:

1.  **FILE_SEARCH**: Searching the project for tokens, symbols, or patterns (e.g., using `search_project` or `grep`).
2.  **FILE_EDIT**: Modifying existing code or configuration files. Includes rules for saving originals and formatting.
3.  **FILE_VCS**: Interacting with source control (Git). Includes branching, commit messaging, and PR policies.
4.  **REMOTE_EXEC**: Executing commands on the **hierophant** host or cluster nodes via SSH.
5.  **K8S_ORCHESTRATE**: Managing Kubernetes resources using `kubectl`, `helm`, or `talosctl`.
6.  **DB_ACCESS**: Querying or modifying the database (TimescaleDB).
7.  **BUILD_DEPLOY**: Managing the build pipeline, versioning, and deployment of services.
8.  **DOC_PROCESS**: Generating or parsing documents (PDFs, Markdown).
9.  **JOB_RESUME**: Specific rules for resume and cover letter generation (Authenticity, targeted generation).
10. **WEB_FETCH**: Fetching external documentation or resources via `curl`, `wget`, or web search.

### Implementation Plan

#### Phase 1: Database Schema (Ent)
- Create `BehavioralRule` entity:
    - `action_type`: Enum of the taxonomy above.
    - `rule_content`: The specific operational instruction (text).
    - `priority`: Integer to handle conflicting rules.
    - `is_active`: Boolean to enable/disable rules.
    - `scope`: Global, project-specific, or session-specific.
- Create `BehavioralLog` entity:
    - Audit trail of which rules were applied to which `prompt_id`.

#### Phase 2: Management API (rag-admin-api)
- Extend `rag-admin-api` with REST endpoints:
    - `GET /api/behavior/rules/{action_type}`: Fetch rules for a type.
    - `POST /api/behavior/rules`: Add or update rules.
    - `POST /api/behavior/audit`: Log rule application.

#### Phase 3: Memory Orchestration (memory-controller)
- Integrate behavioral memory into the `memory-controller`:
    - The `memory-controller` becomes the central hub for assembling the `MemoryPack`.
    - It will fetch behavioral rules from `rag-admin-api` and session context from the database.
    - It delivers the combined context to the `rag-worker` via the existing `/retrieve` endpoint.

#### Phase 4: Pipeline Integration (rag-worker)
- Update `handlePlan` and `handleSearch` in `rag-worker`:
    - The `rag-worker` requests a `MemoryPack` from the `memory-controller`.
    - This pack now includes "Behavioral Context" based on the identified `ActionType` of the current prompt/task.
    - Rules are injected into the "System Instructions" for the sub-task execution.

#### Phase 5: Feedback and Self-Correction
- Implement a "Learning" step:
    - When a user provides a correction (e.g., "Don't use Horizontal Scrolling"), the `rag-admin-api` handles the categorization and persistence of this new rule.

### Deliverables
- Ent schema migrations for behavioral tables.
- API endpoints for rule management.
- Updated `rag-worker` pipeline with behavioral rule injection.
- Initial seeding of the database with content from `guidelines.md` and `OPERATIONS.md`.

### Exit Criteria
- Successful migration of 100% of existing `guidelines.md` and `OPERATIONS.md` rules into the database.
- Verified injection of action-specific rules into LLM sub-prompts.
- Audit trail confirming rule compliance in production logs.
