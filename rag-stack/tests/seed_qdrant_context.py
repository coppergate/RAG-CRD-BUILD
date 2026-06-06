import os
import time
import requests
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
import json
import sys
from datetime import datetime
from qdrant_client import QdrantClient
from qdrant_client.http import models
from e2e_tag_state import ensure_test_tag
from model_matrix import EMBEDDING_MODEL

QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama.llms-ollama.svc.cluster.local:11434")
VECTOR_SIZE = int(os.getenv("VECTOR_SIZE", "4096"))


def _normalize_model_name(model: str) -> str:
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


COLLECTION_NAME = f"vectors-{_normalize_model_name(EMBEDDING_MODEL)}-{VECTOR_SIZE}"
TAG_STATE_FILE = os.getenv(
    "RAG_E2E_TAG_STATE_FILE", "/tmp/rag-e2e-context-tag-state.json"
)

TEST_DATA = [
    {
        "id": 1001,
        "text": "Project Alpha uses the 'Zeltron-9' protocol for inter-pod communication. The primary maintainer is 'Dr. Aris Thorne'.",
        "metadata": {"source": "project_alpha/README.md", "tags": ["test-tag"], "embedding_model": EMBEDDING_MODEL}
    },
    {
        "id": 1002,
        "text": "The secret passphrase for the beta portal is 'Crimson-Sky-77'. Contact 'Unit-X' for access.",
        "metadata": {"source": "project_beta/secrets.txt", "tags": ["test-tag"], "embedding_model": EMBEDDING_MODEL}
    }
]

def get_ollama_embeddings(text: str):
    url = f"{OLLAMA_URL}/api/embeddings"
    payload = {
        "model": EMBEDDING_MODEL,
        "prompt": text
    }
    resp = requests.post(url, json=payload, timeout=60)
    resp.raise_for_status()
    return resp.json()["embedding"]

def ensure_ollama_model_available():
    url = f"{OLLAMA_URL}/api/tags"
    print(f"[SEED] Preflight: checking Ollama model '{EMBEDDING_MODEL}' at {url}")
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    data = resp.json()

    for model in data.get("models", []):
        candidate = model.get("name") or model.get("model")
        if candidate == EMBEDDING_MODEL:
            return

    available = []
    for model in data.get("models", []):
        candidate = model.get("name") or model.get("model")
        if candidate:
            available.append(candidate)

    raise RuntimeError(
        f"Ollama model '{EMBEDDING_MODEL}' is not available; found: {available or 'none'}"
    )

def seed_data():
    print(f"[{datetime.utcnow().isoformat()}] [SEED] Connecting to Qdrant at {QDRANT_HOST}")
    tag = ensure_test_tag(state_file=TAG_STATE_FILE, prefix="test-tag-context-")
    tag_id = tag["tag_id"]
    print(f"[SEED] Using tag {tag['tag_name']} (ID: {tag_id})")
    ensure_ollama_model_available()
    qdrant_use_tls = os.getenv("QDRANT_USE_TLS", "true") == "true"
    client = QdrantClient(host=QDRANT_HOST, port=6333, https=qdrant_use_tls, prefer_grpc=False, timeout=30)
    
    print(f"[SEED] Ensuring collection '{COLLECTION_NAME}' (size: {VECTOR_SIZE})...")
    try:
        client.get_collection(COLLECTION_NAME)
        collection_exists = True
    except Exception:
        collection_exists = False

    if not collection_exists:
        try:
            client.create_collection(
                collection_name=COLLECTION_NAME,
                vectors_config=models.VectorParams(size=VECTOR_SIZE, distance=models.Distance.COSINE),
            )
            print(f"  - Created collection {COLLECTION_NAME}")
        except Exception as e:
            if "already exists" in str(e):
                print(f"  - Collection {COLLECTION_NAME} already exists (race condition), continuing.")
            else:
                raise
    
    points = []
    failures = []
    for item in TEST_DATA:
        print(f"  - Embedding chunk {item['id']} using {EMBEDDING_MODEL}...")
        try:
            vector = get_ollama_embeddings(item["text"])
            
            # Ensure correct size
            if len(vector) != VECTOR_SIZE:
                print(f"    [WARN] Vector size mismatch: expected {VECTOR_SIZE}, got {len(vector)}")
            
            payload = item.copy()
            # The stack expects 'text' and 'tags' in the top-level payload for search.
            # Use the real tag ID so the query filter and Qdrant payload stay aligned.
            payload["tags"] = [tag_id]
            payload["embedding_model"] = EMBEDDING_MODEL
            payload["vector_size"] = VECTOR_SIZE
            
            points.append(models.PointStruct(
                id=item["id"],
                vector=vector,
                payload=payload
            ))
        except Exception as e:
            print(f"    [ERROR] Failed to embed {item['id']}: {e}")
            failures.append(item["id"])

    if failures:
        raise RuntimeError(f"Embedding failed for test points: {failures}")
    
    if points:
        print(f"  - Upserting {len(points)} points...")
        client.upsert(collection_name=COLLECTION_NAME, points=points)
        print(f"[{datetime.utcnow().isoformat()}] [SEED] Done.")
    else:
        raise RuntimeError(f"No points to upsert for collection {COLLECTION_NAME}")

if __name__ == "__main__":
    try:
        seed_data()
    except Exception as exc:
        print(f"[SEED][ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
