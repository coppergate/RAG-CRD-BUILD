import boto3
import os
import time
import requests
import json
from qdrant_client import QdrantClient
from qdrant_client.http import models

# Environment Configuration
endpoint_env = os.getenv("S3_ENDPOINT", "http://rook-ceph-rgw-ceph-object-store.rook-ceph.svc")
if endpoint_env and not endpoint_env.startswith("http"):
    S3_ENDPOINT = "http://" + endpoint_env
else:
    S3_ENDPOINT = endpoint_env

QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://llm-gateway.rag-system.svc.cluster.local/v1/chat/completions")
BUCKET_NAME = os.getenv("BUCKET_NAME", "rag-codebase-bucket")

# A set of facts that are NOT in the model's base training but will be in the context
TEST_CODEBASE = {
    "project_alpha/README.md": "Project Alpha uses the 'Zeltron-9' protocol for inter-pod communication. The primary maintainer is 'Dr. Aris Thorne'.",
    "project_alpha/config.yaml": "protocol: zeltron-9\nport: 9999\nsecurity: high",
    "project_beta/secrets.txt": "The secret passphrase for the beta portal is 'Crimson-Sky-77'. Contact 'Unit-X' for access."
}

# Queries designed to verify context injection
CONTEXT_QUERIES = [
    {
        "question": "What protocol does Project Alpha use?",
        "expected_substring": "Zeltron-9"
    },
    {
        "question": "Who is the primary maintainer of Project Alpha?",
        "expected_substring": "Aris Thorne"
    },
    {
        "question": "What is the secret passphrase for the beta portal?",
        "expected_substring": "Crimson-Sky-77"
    }
]

def setup_test_data():
    print("[SETUP] Injecting fixed test context into S3...")
    s3 = boto3.client('s3', endpoint_url=S3_ENDPOINT)
    for path, content in TEST_CODEBASE.items():
        s3.put_object(Bucket=BUCKET_NAME, Key=path, Body=content)
        print(f"  - Uploaded {path}")

def trigger_ingestion():
    print("[SETUP] Triggering Ingestion Job...")
    # In this environment, we manually trigger the logic or wait for the existing job
    # For a deterministic test, we'll wait a bit for the ingestor to pick it up if automated
    # or print instructions. 
    # Since we have the ingest-s3-script ConfigMap, we assume the job runs on demand.
    print("  - NOTE: Ensure the 'ingest-codebase-s3' job has run to process these new files.")
    time.sleep(5) 

def run_context_tests():
    print("[TEST] Running Context Verification Queries (Heat 0)...")
    results = []
    
    # We use a unique session for this test run to track it in TimescaleDB
    session_id = f"test-session-{int(time.time())}"
    
    for query in CONTEXT_QUERIES:
        print(f"  - Query: {query['question']}")
        payload = {
            "model": "llama3.1",
            "session_id": session_id,
            "messages": [{"role": "user", "content": query['question']}],
            "temperature": 0.0 # Heat 0 for deterministic output
        }
        
        try:
            response = requests.post(GATEWAY_URL, json=payload, timeout=60)
            if response.status_code == 200:
                answer = response.json()['choices'][0]['message']['content']
                passed = query['expected_substring'].lower() in answer.lower()
                results.append({
                    "question": query['question'],
                    "passed": passed,
                    "answer": answer[:100] + "..."
                })
                print(f"    - Pass: {passed}")
            else:
                print(f"    - Error: {response.status_code} - {response.text}")
        except Exception as e:
            print(f"    - Failed to connect: {e}")

    return results

if __name__ == "__main__":
    import sys
    if "--query-only" in sys.argv:
        results = run_context_tests()
        all_passed = all(r['passed'] for r in results)
        print(f"\n[SUMMARY] Context verification: {'SUCCESS' if all_passed else 'FAILURE'}")
        if not all_passed:
            sys.exit(1)
    else:
        setup_test_data()
        print("\n[INFO] Test data is ready in S3. Run the ingestion job, then run this script with --query-only.")
