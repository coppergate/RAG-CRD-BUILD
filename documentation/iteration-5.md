## Multi-Model Recursive RAG Orchestration

### 1. Implement a Specialized Multi-Model Pipeline
- Transition from a single-worker RAG to a stage-based pipeline:
  - **Stage 1: Ingress**: Receive user prompt and establish session/correlation context.
  - **Stage 2: Planning**: Use a specialized "Planner" model (e.g., Llama 3.1 8B) to:
    - Decompose complex prompts into "bite-sized", operable sub-tasks.
    - Identify specific tool/context requirements for each sub-task.
    - Map each sub-task to the most suitable "Executor" model/profile.
  - **Stage 3: Retrieval**: Execute targeted multi-query vector searches; strictly prune context to only what is necessary for the current sub-task to preserve VRAM.
  - **Stage 4: Execution**: Use specialized "Executor" models (e.g., DeepSeek Coder) to process sub-tasks in isolation.
  - **Stage 5: Aggregation**: Implement "Tricky Aggregation" to:
    - Recompose partial responses into a coherent, unified answer.
    - Resolve contradictions or overlaps between sub-task results.
    - Maintain a consistent tone and citation flow across the final output.

### 2. Implement Recursive Logic and Feedback Loop
- Define a "Grounding Guard" in the Executor stage:
  - If the model determines context is insufficient, it must return a specific JSON contract: `{"insufficient_context": true, "missing_details": [...]}`.
- Implement a **Recursion Manager** in the worker logic:
  - Intercept "insufficient context" signals.
  - Decrement a `recursion_budget` (default: 2).
  - Feed missing details back to the **Planning** stage for refined retrieval.
- Halt recursion when `recursion_budget` reaches zero or a satisfactory answer is produced.

### 3. Asynchronous Status and Verbose Tracking
- Emit "State Transition" messages as the request moves through the pipeline.
- Status messages should be published to `rag.status` for the UI.
- **Verbose Experimentation Logging**:
  - Capture and store the full internal state (sub-tasks, pruned context, raw executor outputs) for each step.
  - Log to TimescaleDB to enable "Post-Mortem" analysis of failed recursions or poor aggregations.
- Example States: `PLANNING_TASK`, `SUBTASK_DISPATCH`, `RETRIEVING_CONTEXT`, `GENERATING_CODE`, `REFINING_PLAN`, `AGGREGATING_RESULTS`.

### 4. Kubernetes Deployment and Model Pinning
- Configure separate K8s Deployments for roles:
  - `llm-planner`: Pinned to GPU 0 using `nvidia.com/gpu: 1` and `nodeSelector`.
  - `llm-executor`: Pinned to GPU 1 using `nvidia.com/gpu: 1` and `nodeSelector`.
- Anticipate expansion: Use a consistent naming convention (`llm-<role>-<model-id>`) to support a growing fleet of models.
- Ensure service names (e.g., `llm-planner.rag.svc.cluster.local`) are used for all inter-service communication.

### 5. Pulsar Topic Architecture (Concise & Consistent)
- Use a clear, flat namespace that resembles existing patterns:
  - `rag.ingress`: Initial requests.
  - `rag.plan`: Planning tasks and refined queries.
  - `rag.exec`: Execution tasks with retrieved context.
  - `rag.status`: Asynchronous state/progress updates for the UI.
  - `rag.results`: Final aggregated responses.

### 6. UI/UX Enhancements for Recursion
- Update the 'Ask the RAG' interface to:
  - Support selecting a "Primary Model" (Executor) and an optional "Planner" profile.
  - Display a live "Thinking Trace" based on `rag.status` messages.
  - Show "Recursion Depth" indicators when the model is gathering more information.

### 7. Configuration Discovery and Observability
- Maintain the 'ping' functionality for all nodes to report:
  - Loaded model name and version.
  - GPU VRAM utilization and temperature.
  - Current queue depth and recursion stats.
- Integrate these metrics into the LGTM stack (Grafana dashboards).

---

### Progress & Status (Updated: 2026-02-28)

The foundation for Iteration 5 has been established with the following core improvements:

1.  **Observability & APM (Completed)**:
    - Full **Grafana LGTM stack** (Loki, Grafana, Tempo, Mimir) is deployed and configured with S3 storage (Rook-Ceph).
    - **OpenTelemetry (OTLP)** metrics and tracing enabled across all Go services via a new shared `internal/telemetry` common package.
    - **Grafana Alloy** is deployed as a `DaemonSet` to collect and ship Kubernetes logs to Loki.
    - Custom performance dashboards for the RAG stack are automated via the Grafana Operator.

2.  **Build Pipeline & Host Isolation (Completed)**:
    - **Cluster-Native Build Pipeline** (Kaniko + S3 + Pulsar Orchestrator) is fully implemented and integrated.
    - **Self-Bootstrapping**: The `build-orchestrator` image is built via a one-shot Kaniko job, eliminating all host-side `podman build` or `gcc` tasks on `hierophant`.
    - **Host Resource Protection**: `hierophant` now only performs lightweight source packaging (`tar`) and orchestration (`kubectl`/`pulsar-client`).
    - **Synchronous Builds**: `build-all-on-cluster.sh` includes a `--wait` flag to ensure images are fully ready before deployment.
    - **Safe Temporary Storage**: All build-triggering artifacts are stored in a private, per-user `~/.complete-build/tmp` directory to avoid permission conflicts.

3.  **Infrastructure Refinement (Completed)**:
    - **Loki & Memcached** relocated to worker nodes via node affinity to free up resources on inference nodes.
    - **Loki** scaled horizontally to 3 replicas for high availability and load distribution.
    - **Object Store Manager** and **Build Orchestrator** services added to the stack.

4.  **Service Refactoring (Completed)**:
    - All Go services (`llm-gateway`, `rag-worker`, `db-adapter`, `qdrant-adapter`, `rag-web-ui`, `object-store-mgr`) refactored to use a centralized `common` module for telemetry and utilities.
    - Error handling and logging context (Correlation IDs, Session IDs) improved across all services.

**Next Steps**:
- Proceed with the Multi-Model Recursive RAG orchestration logic (Planner/Executor split) after the planned cluster reboot and Ceph stabilization.
