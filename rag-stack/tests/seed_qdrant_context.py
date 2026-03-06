import os
import time
from qdrant_client import QdrantClient
from qdrant_client.http import models
from sentence_transformers import SentenceTransformer

QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
COLLECTION_NAME = "codebase"

TEST_DATA = [
    {
        "id": 1001,
        "text": "Project Alpha uses the 'Zeltron-9' protocol for inter-pod communication. The primary maintainer is 'Dr. Aris Thorne'.",
        "metadata": {"source": "project_alpha/README.md"}
    },
    {
        "id": 1002,
        "text": "The secret passphrase for the beta portal is 'Crimson-Sky-77'. Contact 'Unit-X' for access.",
        "metadata": {"source": "project_beta/secrets.txt"}
    }
]

def seed_data():
    print(f"[SEED] Connecting to Qdrant at {QDRANT_HOST}")
    client = QdrantClient(host=QDRANT_HOST, port=6333)
    
    print("[SEED] Loading embedding model...")
    model = SentenceTransformer('all-MiniLM-L6-v2')
    
    print(f"[SEED] Upserting test context into '{COLLECTION_NAME}'...")
    
    points = []
    for i, item in enumerate(TEST_DATA):
        print(f"  - Embedding chunk {item['id']}...")
        vector = model.encode(item["text"]).tolist()
        
        points.append(models.PointStruct(
            id=item["id"],
            vector=vector,
            payload=item
        ))
    
    client.upsert(collection_name=COLLECTION_NAME, points=points)
    print("[SEED] Done.")

if __name__ == "__main__":
    seed_data()
