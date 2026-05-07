import os
import time
import requests
import json
from datetime import datetime
from qdrant_client import QdrantClient
from qdrant_client.http import models

QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama.llms-ollama.svc.cluster.local:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:latest")
VECTOR_SIZE = int(os.getenv("VECTOR_SIZE", "4096"))
COLLECTION_NAME = f"vectors-{VECTOR_SIZE}"

TEST_DATA = [
    {
        "id": 1001,
        "text": "Project Alpha uses the 'Zeltron-9' protocol for inter-pod communication. The primary maintainer is 'Dr. Aris Thorne'.",
        "metadata": {"source": "project_alpha/README.md", "tags": ["test-tag"]}
    },
    {
        "id": 1002,
        "text": "The secret passphrase for the beta portal is 'Crimson-Sky-77'. Contact 'Unit-X' for access.",
        "metadata": {"source": "project_beta/secrets.txt", "tags": ["test-tag"]}
    }
]

def get_ollama_embeddings(text: str):
    url = f"{OLLAMA_URL}/api/embeddings"
    payload = {
        "model": OLLAMA_MODEL,
        "prompt": text
    }
    resp = requests.post(url, json=payload, timeout=60)
    resp.raise_for_status()
    return resp.json()["embedding"]

def seed_data():
    print(f"[{datetime.utcnow().isoformat()}] [SEED] Connecting to Qdrant at {QDRANT_HOST}")
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
    for item in TEST_DATA:
        print(f"  - Embedding chunk {item['id']} using {OLLAMA_MODEL}...")
        try:
            vector = get_ollama_embeddings(item["text"])
            
            # Ensure correct size
            if len(vector) != VECTOR_SIZE:
                print(f"    [WARN] Vector size mismatch: expected {VECTOR_SIZE}, got {len(vector)}")
            
            payload = item.copy()
            # The stack expects 'text' and 'tags' in the top-level payload for search
            # We use a fixed integer ID for "test-tag" to match BIGINT refactor
            payload["tags"] = [999] 
            
            points.append(models.PointStruct(
                id=item["id"],
                vector=vector,
                payload=payload
            ))
        except Exception as e:
            print(f"    [ERROR] Failed to embed {item['id']}: {e}")
    
    if points:
        print(f"  - Upserting {len(points)} points...")
        client.upsert(collection_name=COLLECTION_NAME, points=points)
        print(f"[{datetime.utcnow().isoformat()}] [SEED] Done.")
    else:
        print(f"[{datetime.utcnow().isoformat()}] [SEED] No points to upsert.")

if __name__ == "__main__":
    seed_data()
