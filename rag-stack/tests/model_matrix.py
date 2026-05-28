import os

MODEL_A = os.getenv("MODEL_A", os.getenv("OLLAMA_MODEL", "llama3.1:latest"))
MODEL_B = os.getenv("MODEL_B", "granite3.1-dense:8b")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", MODEL_A)


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


def model_cases():
    return [
        {
            "name": f"{MODEL_A}__{MODEL_A}",
            "label": f"{_slug(MODEL_A)}__{_slug(MODEL_A)}",
            "planner": MODEL_A,
            "executor": MODEL_A,
        },
        {
            "name": f"{MODEL_A}__{MODEL_B}",
            "label": f"{_slug(MODEL_A)}__{_slug(MODEL_B)}",
            "planner": MODEL_A,
            "executor": MODEL_B,
        },
        {
            "name": f"{MODEL_B}__{MODEL_A}",
            "label": f"{_slug(MODEL_B)}__{_slug(MODEL_A)}",
            "planner": MODEL_B,
            "executor": MODEL_A,
        },
        {
            "name": f"{MODEL_B}__{MODEL_B}",
            "label": f"{_slug(MODEL_B)}__{_slug(MODEL_B)}",
            "planner": MODEL_B,
            "executor": MODEL_B,
        },
    ]
