## Iteration 8: Advanced Reasoning, Verification, and Self-Correction

### Objective
Enhance the reliability and accuracy of the RAG stack by introducing a multi-stage reasoning process that includes response verification, hallucination detection, and autonomous self-correction.

### Scope
- Implement a **Refiner/Critic** model phase in the `rag-worker` pipeline.
- Add a **Verification** stage to the Pulsar-based workflow.
- Implement **Self-Correction** logic that allows the pipeline to re-plan or re-search if inconsistencies are detected.
- Integrate **Cross-Model Verification** (e.g., Llama 3 verifying Granite 3.1 output).

### Non-Goals
- Real-time reinforcement learning from human feedback (RLHF).
- Replacing the core vector search engine.
- Implementing a fully autonomous multi-agent swarm (keep it to a structured pipeline).

### Phase 1: Verification Data Model and Contracts
- Extend `contracts.InternalRequest` to include `verification_mode` and `critic_model`.
- Define `VerificationResult` contract:
  - `is_hallucination` (bool)
  - `missing_evidence` (list of claims)
  - `contradictions` (list of memory/context conflicts)
  - `refinement_instructions` (string)
- Update `responses` table in TimescaleDB to store verification audit trails.

### Phase 2: The Critic Phase in RAG Worker
- Add a `verify` stage after the `exec` stage in `rag-worker`.
- The Critic model performs:
  - **Grounding Check**: Verifying every claim against the `MemoryPack` and retrieved `contexts`.
  - **Consistency Check**: Ensuring the response doesn't contradict previous turns (long-term memory).
  - **Constraint Validation**: Checking against persistent profile constraints.

### Phase 3: Self-Correction Loop
- If the `VerificationResult` indicates a failure:
  - Trigger a **Re-Plan** or **Re-Search** with specific refinement instructions.
  - Decrement a `correction_budget` (similar to `recursion_budget`) to prevent infinite loops.
  - Only stream the "Final Verified" response to the user.

### Phase 4: Cross-Model Verification
- Allow the use of a larger/stronger model as the "Critic" (e.g., using a high-parameter model for verification while a smaller model handles generation).
- Implement a "Voting" mechanism where multiple models verify high-stakes information.

### Phase 5: UI and Observability
- Update RAG Explorer to show the "Thought Process" including the Critic's feedback and the self-correction steps.
- Add metrics for "Correction Rate", "Hallucination Catch Rate", and "Verification Overhead".

### Exit Criteria
- >= 30% reduction in measured hallucination rate on "fact-check" benchmarks.
- No > 20% increase in total response latency (optimized by parallel verification where possible).
- Verified audit trail for every corrected response.

### Risks and Mitigations
- **Latency Increase**: Use smaller, specialized models for verification or perform verification asynchronously for non-critical parts.
- **Critic Hallucinations**: Implement strict template-based prompting for the Critic model to ensure deterministic verification logic.
- **Token Usage**: Apply strict budgeting for the verification phase.
