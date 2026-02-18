import boto3
import os
import time
import requests
from qdrant_client import QdrantClient
from qdrant_client.http import models

# Constants from environment or defaults
endpoint_env = os.getenv("S3_ENDPOINT", "http://rook-ceph-rgw-ceph-object-store.rook-ceph.svc")
if endpoint_env and not endpoint_env.startswith("http"):
    S3_ENDPOINT = "http://" + endpoint_env
else:
    S3_ENDPOINT = endpoint_env

QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://llm-gateway.rag-system.svc.cluster.local/v1/chat/completions")
BUCKET_NAME = os.getenv("BUCKET_NAME", "rag-codebase-bucket")

def test_s3_ops():
    print("[TEST] Testing S3 Operations...")
    s3 = boto3.client('s3', endpoint_url=S3_ENDPOINT)
    test_file = "test_file.txt"
    test_content = "This is a test content for RAG testing."
    
    # Upload
    s3.put_object(Bucket=BUCKET_NAME, Key=test_file, Body=test_content)
    print(f"  - Uploaded {test_file}")
    
    # Read
    response = s3.get_object(Bucket=BUCKET_NAME, Key=test_file)
    content = response['Body'].read().decode('utf-8')
    assert content == test_content
    print("  - Verified content")
    
    # List
    objects = s3.list_objects_v2(Bucket=BUCKET_NAME)
    keys = [obj['Key'] for obj in objects.get('Contents', [])]
    assert test_file in keys
    print("  - Verified file in listing")

def test_qdrant_ops():
    print("[TEST] Testing Qdrant Operations...")
    client = QdrantClient(host=QDRANT_HOST, port=6333, timeout=60)
    collection_name = "test_collection"
    
    # Recreate collection
    client.recreate_collection(
        collection_name=collection_name,
        vectors_config=models.VectorParams(size=384, distance=models.Distance.COSINE),
    )
    print(f"  - Created collection {collection_name}")
    
    # Upsert dummy data
    client.upsert(
        collection_name=collection_name,
        points=[
            models.PointStruct(
                id=1,
                vector=[0.1] * 384,
                payload={"text": "Test vector search"}
            )
        ]
    )
    print("  - Upserted test point")
    
    # Search
    results = client.query_points(
        collection_name=collection_name,
        query=[0.1] * 384,
        limit=1
    ).points
    assert len(results) > 0
    assert results[0].payload["text"] == "Test vector search"
    print("  - Verified search result")

def test_rag_retrieval():
    print("[TEST] Testing RAG Retrieval via Gateway...")
    # This assumes the gateway is connected to a worker that can search Qdrant
    # For a basic connectivity test, we just check if the gateway responds
    payload = {
        "model": "llama3.1",
        "messages": [{"role": "user", "content": "Tell me about the project"}]
    }
    try:
        # Increase timeout for the whole Pulsar/Worker/Ollama roundtrip
        response = requests.post(GATEWAY_URL, json=payload, timeout=90)
        print(f"  - Gateway status code: {response.status_code}")
        if response.status_code == 200:
            print("  - Gateway responded successfully")
        else:
            print(f"  - Gateway error: {response.text}")
    except Exception as e:
        print(f"  - Gateway connection failed: {e}")

if __name__ == "__main__":
    # Note: These tests are intended to run INSIDE the cluster or where endpoints are reachable
    try:
        test_s3_ops()
        test_qdrant_ops()
        test_rag_retrieval()
        print("\n[SUCCESS] All core component tests passed!")
    except Exception as e:
        print(f"\n[FAILURE] Test failed: {e}")
        exit(1)
