## Iteration 9: Behavioral Long-Term Memory and Action-Governed Planning

### Objective
Build a database-backed behavioral memory system that improves how the agent plans coding tasks, selects context, and applies operational rules. The goal is not just rule storage. The goal is to make planner output more structured, reduce irrelevant context, and steer each sub-task with the smallest useful prompt bundle.

### What This Iteration Must Solve

The current stack already has recursive planning, memory retrieval, and behavioral rule detection. Iteration 9 should tighten that into a stable planning workflow:

1. Identify the kind of work being requested.
2. Turn the planner output into a structured task plan.
3. Fetch only the behavioral rules and memory relevant to that task.
4. Inject that context into the planner and executor prompts.
5. Persist the task trace so the system can explain what it did.

### What Is Still Weak In The Current Plan

The direction is right, but the current plan still leaves a few critical gaps:

1. It treats `action_type` as a selector, not as a task contract.
2. It does not define how a planner response becomes ordered sub-tasks with dependencies and blocking steps.
3. It does not define what evidence is needed before the worker asks for context.
4. It does not cap how much memory or policy can be injected for a step.
5. It does not yet separate explicit user instructions from session overrides, project rules, and global rules in a machine-readable way.
6. It does not yet define how we measure whether the new path is actually better.

### How This Compares To The Existing Agent Support Pieces

The stack already has several partial solutions, but each one covers only part of the problem:

- `memory-controller` handles recall and durable memory, but it does not decide how a request should be decomposed.
- `action_identifiers` support routing, but they do not express task intent, ordering, or evidence requirements.
- The recursive planner already breaks work apart, but it still emits loose text instead of a contract the worker can reason over.
- The behavioral rules system can influence prompts, but precedence and conflict handling are still implicit.
- Persisted responses and retrieval logs help with auditability, but they do not yet explain why a specific context bundle was chosen for a specific sub-task.

### Design Constraints

- Action taxonomy alone is not enough. It is useful for rule selection, but it does not describe task structure.
- Keyword classification is useful as a fallback, but it is not reliable enough to be the only routing mechanism.
- Behavioral rules must be bounded. A learning loop that accepts everything will degrade the system over time.
- Planning and policy are different layers. Planner output should describe work. Behavioral memory should constrain how that work is performed.
- The system needs an evaluation story. If the new planning path does not measurably improve context usage or task quality, it is too expensive.

### Action Taxonomy

The action taxonomy is still useful as the top-level policy index:

1. `FILE_SEARCH`: Locate symbols, files, patterns, and references.
2. `FILE_EDIT`: Modify code, manifests, or docs.
3. `FILE_VCS`: Interact with git, branches, commits, and PR flow.
4. `REMOTE_EXEC`: Run commands on `hierophant` or related hosts.
5. `K8S_ORCHESTRATE`: Use `kubectl`, `helm`, or `talosctl`.
6. `DB_ACCESS`: Query or mutate TimescaleDB.
7. `BUILD_DEPLOY`: Build, version, and deploy services.
8. `DOC_PROCESS`: Generate or parse documents.
9. `JOB_RESUME`: Resume and cover letter workflows.
10. `WEB_FETCH`: Retrieve external documentation or resources.

### Planner Output Contract

The planner should produce a structured task object, not just raw sub-queries. The worker should be able to use that object to decide what to retrieve, what to defer, and what to treat as unsafe or blocking.

A useful shape would include:

- `objective`: the immediate goal of the step.
- `action_type`: one of the taxonomy values, or `UNKNOWN`.
- `inputs`: the specific files, commands, endpoints, or docs needed.
- `outputs`: what the step is expected to produce.
- `dependencies`: prior steps, missing facts, or required context.
- `context_budget`: a hint for how much memory or retrieval context to inject.
- `confidence`: how sure the planner is about the chosen action type.
- `blocking`: whether later steps depend on this step finishing.
- `risk`: whether the step can mutate code, state, or infrastructure.
- `evidence_requirements`: what must be established before execution.
- `task_order`: a normalized sequence or graph hint when the response contains multiple sub-steps.

This is the missing layer between user intent and prompt injection.

### Required Planner Semantics

The plan should answer these questions deterministically:

1. What is the task trying to prove or change?
2. What information is required before execution?
3. Which sub-task is the first safe action?
4. Which context buckets are relevant for this step?
5. Which later steps are blocked on this result?

If the planner cannot answer those questions, it should degrade to `UNKNOWN` and ask for narrower context instead of guessing.

### Known Shortcomings To Address

#### 1. Coarse action buckets
`FILE_SEARCH` or `FILE_EDIT` are helpful, but they are not a plan. The planner still needs to say what it is trying to prove or change before the worker decides what context to load.

#### 2. Brittle action detection
Current detection is keyword driven. That works for obvious prompts, but it will misread mixed requests, implied actions, and context-dependent follow-ups. We need a classifier that can degrade to `UNKNOWN` and still behave safely.

#### 3. Context overgrowth
The stack already mixes episodic history, behavioral rules, and live task context. Without a strict boundary, prompt size will keep growing and the planner will see noise instead of leverage.

#### 4. Unbounded learning
User corrections are valuable, but learned rules need staging, conflict checks, and session scoping. Otherwise the memory store becomes a policy dump.

#### 5. No deterministic rule resolution
If several rules match the same task, the system needs a predictable order of precedence. Priority alone is not enough unless we define how scope, recency, session override, and explicit user instruction interact.

#### 6. No structured evaluation
We need a way to tell whether the new planning path actually improved task completion, reduced irrelevant context, and lowered bad tool calls.

### Implementation Shape

This iteration should be implemented as contracts and retrieval rules first, then wired into the planner and worker paths.

#### Phase 0: Task Trace And Planner Contract

Define a structured task trace that can be persisted and replayed. Each planner step should record:

- the raw planner output,
- the parsed task object,
- the selected action type,
- the context sources that were considered,
- the final injected prompt bundle,
- and the rules that were applied.

The goal is to make the planner explainable before it becomes more ambitious.

#### Phase 1: Behavioral Policy Store
Store behavioral rules in TimescaleDB with:

- `action_type`
- `rule_content`
- `priority`
- `scope`
- `is_active`
- `created_at`
- `updated_at`

Store a separate audit trail for which rules were applied to which prompt or sub-task.

#### Phase 2: Task Plan Contract
Introduce a structured internal plan object for planner output. The planner should emit the plan, not just natural-language reasoning. The worker can then map each plan node to a prompt bundle.

The first implementation should support:

- single-step plans,
- multi-step linear plans,
- blocked steps waiting on retrieval or user input,
- and a fallback path when the planner only returns `UNKNOWN`.

#### Phase 3: Context Assembly
Split context into explicit buckets:

- Behavioral rules
- Episodic memory
- Task-local retrieval context
- User-provided hints

The worker should compose only the buckets that are relevant to the current action type and step. The buckets should be ordered by specificity, not by arrival time.

#### Phase 3.1: Retrieval Ordering

The default retrieval order should be:

1. User instruction for the current session.
2. Session-scoped override rules.
3. Action-type scoped behavioral rules.
4. Task-local retrieval results.
5. Episodic session memory.
6. Global fallback policy.

That order keeps explicit user intent ahead of system policy and keeps policy ahead of generic recall.

#### Phase 4: Learning Loop
Allow user corrections to stage proposed rules, not immediately activate them. Add conflict checks before promotion to active status.

The staged rule should carry:

- source prompt or session reference,
- proposed action type,
- proposed scope,
- activation state,
- conflict status,
- and review outcome.

#### Phase 5: Evaluation
Track whether the new system reduces:

- planner prompt size
- irrelevant retrieved memory
- repeated tool mistakes
- retries caused by missing context

### Rule Resolution Model

When multiple behavioral rules match, resolve them in this order:

1. Explicit user instruction for the current session.
2. Session-scoped behavioral override.
3. Action-type specific active rule.
4. Project-scoped rule.
5. Global fallback rule.

Within each layer, higher priority wins. If priorities tie, prefer the most specific scope and then the newest active rule.

#### Conflict Handling

If a rule conflicts with a higher-scope or newer explicit instruction, keep it staged or inactive rather than forcing a merge. The system should not invent precedence where none exists.

### Deliverables

- Ent schema migrations for behavioral tables.
- A structured planner/task schema.
- API endpoints for rule management and rule staging.
- Updated `rag-worker` context assembly using action-scoped retrieval.
- Audit records for applied behavioral rules.
- A validation pass showing the new approach reduces unnecessary prompt size or retry behavior.

### First Implementation Slice

The first pass should stay narrow and measurable:

1. Define the task plan contract and persistence shape.
2. Teach the planner to emit structured tasks for the most common action types.
3. Add deterministic rule selection for one retrieval path.
4. Persist the task trace and applied rules.
5. Add tests that assert ordering, fallback behavior, and budget enforcement.

That slice is enough to validate whether the approach improves decomposition and context selection before the learning loop is broadened.

### Exit Criteria

- Planner output is structured enough to identify the next task and its required inputs.
- Behavioral rules are injected only when relevant to the current action type.
- Session overrides and staged rules are handled safely and deterministically.
- The system can explain which rules influenced a prompt or task.
- The new path can be measured against the old path with concrete metrics.

### Implementation Notes

The existing code already gives us a starting point:

- `rag-worker` currently retrieves history and behavioral context before planning.
- The planner already emits sub-queries and intermediate planning text.
- `db-adapter` already persists responses and retrieval logs.

Iteration 9 should tighten these pieces into a clearer contract rather than adding another loosely coupled layer on top.
