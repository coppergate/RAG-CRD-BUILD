import os

MODEL_A = os.getenv("MODEL_A", os.getenv("OLLAMA_MODEL", "llama3.1:latest"))
MODEL_B = os.getenv("MODEL_B", "granite3.1-dense:8b")
MODEL_C = os.getenv("MODEL_C", "llama3.2:3b")  # CPU alternate planner
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "all-minilm:l6-v2")
EMBEDDING_MODEL_2 = os.getenv("EMBEDDING_MODEL_2", "nomic-embed-text")
EMBEDDING_VECTOR_SIZE = {
    "all-minilm:l6-v2": 384,
    "nomic-embed-text": 768,
}

EMBEDDING_MODELS = [em for em in [EMBEDDING_MODEL, EMBEDDING_MODEL_2] if em]


def _slug(model: str) -> str:
    normalized = []
    last_dash = False
    for ch in model.strip().lower():
        if ch.isalnum():
            normalized.append(ch)
            last_dash = False
        elif not last_dash:
            normalized.append("-")
            last_dash = True
    return "".join(normalized).strip("-")


def _planner_executor_pairs():
    """Heterogeneous planner/executor pairs only — same-model pairs skipped."""
    pairs = [
        # GPU planner × GPU executor (cross-model only)
        {"planner": MODEL_A, "executor": MODEL_B},
        {"planner": MODEL_B, "executor": MODEL_A},
    ]
    # CPU alternate planner cases — only added when MODEL_C differs from GPU models
    if MODEL_C and MODEL_C not in (MODEL_A, MODEL_B):
        pairs += [
            {"planner": MODEL_C, "executor": MODEL_A},
            {"planner": MODEL_C, "executor": MODEL_B},
        ]
    return pairs


def model_cases():
    """8-case matrix: 2 embedding models × 4 heterogeneous planner/executor pairs."""
    cases = []
    for embed in EMBEDDING_MODELS:
        vector_size = EMBEDDING_VECTOR_SIZE.get(embed, 384)
        for pair in _planner_executor_pairs():
            p, e = pair["planner"], pair["executor"]
            cases.append({
                "name": f"{embed}__{p}__{e}",
                "label": f"{_slug(embed)}__{_slug(p)}__{_slug(e)}",
                "planner": p,
                "executor": e,
                "embedding_model": embed,
                "vector_size": vector_size,
            })
    return cases
