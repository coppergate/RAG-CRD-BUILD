import boto3
import os
import time
import requests
import json
from datetime import datetime
from qdrant_client import QdrantClient
from qdrant_client.http import models
from e2e_session_state import unique_session_id, unique_session_name
from e2e_tag_state import ensure_test_tag
from model_matrix import EMBEDDING_MODEL, model_cases

# Environment Configuration
endpoint_env = os.getenv("S3_ENDPOINT", "https://rook-ceph-rgw-ceph-object-store.rook-ceph.svc")
if endpoint_env and not endpoint_env.startswith("http"):
    S3_ENDPOINT = "https://" + endpoint_env
else:
    S3_ENDPOINT = endpoint_env

QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
CHAT_URL = os.getenv("RAG_CHAT_URL", "https://rag-admin-api.rag.hierocracy.home/api/chat/v1/rag/chat")
BUCKET_NAME = os.getenv("BUCKET_NAME", "rag-codebase-bucket")
TAG_STATE_FILE = os.getenv(
    "RAG_E2E_TAG_STATE_FILE", "/tmp/rag-e2e-context-tag-state.json"
)
GATEWAY_TIMEOUT_SECONDS = int(os.getenv("GATEWAY_TIMEOUT_SECONDS", "600"))

# A set of facts that are NOT in the model's base training but will be in the context
TEST_CODEBASE = {
    "project_alpha/README.md": "Project Alpha uses the 'Zeltron-9' protocol for inter-pod communication. The primary maintainer is 'Dr. Aris Thorne'.",
    "project_alpha/config.yaml": "protocol: zeltron-9\nport: 9999\nsecurity: high",
    "project_beta/secrets.txt": "The secret passphrase for the beta portal is 'Crimson-Sky-77'. Contact 'Unit-X' for access."
}

# Queries designed to verify context injection
CONTEXT_QUERIES = [
    {
        "question": "Using only the uploaded context, what protocol does Project Alpha use? Answer with the exact protocol name.",
        "expected_substring": "Zeltron-9"
    },
    {
        "question": "Using only the uploaded context, who is the primary maintainer of Project Alpha? Answer with the exact name.",
        "expected_substring": "Aris Thorne"
    },
    {
        "question": "Using only the uploaded context, what is the secret passphrase for the beta portal? Answer with the exact passphrase.",
        "expected_substring": "Crimson-Sky-77"
    }
]

def setup_test_data():
    print(f"[{datetime.utcnow().isoformat()}] [SETUP] Injecting fixed test context into S3...")
    ca_bundle = os.getenv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
    s3 = boto3.client('s3', endpoint_url=S3_ENDPOINT, verify=ca_bundle)
    for path, content in TEST_CODEBASE.items():
        s3.put_object(Bucket=BUCKET_NAME, Key=path, Body=content)
        print(f"  - Uploaded {path}")

def trigger_ingestion():
    print(f"[{datetime.utcnow().isoformat()}] [SETUP] Triggering Ingestion Job...")
    # In this environment, we manually trigger the logic or wait for the existing job
    # For a deterministic test, we'll wait a bit for the ingestor to pick it up if automated
    # or print instructions. 
    # Since we have the ingest-s3-script ConfigMap, we assume the job runs on demand.
    print("  - NOTE: Ensure the 'ingest-codebase-s3' job has run to process these new files.")
    time.sleep(5) 

def run_context_tests():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Running Context Verification Queries (Heat 0)...")
    results = []
    
    # We use a unique session for this test run to track it in TimescaleDB
    tag = ensure_test_tag(state_file=TAG_STATE_FILE, prefix="test-tag-context-")
    tag_id = tag["tag_id"]
    print(f"  - Using tag {tag['tag_name']} (ID: {tag_id})")

    for case in model_cases():
        print(
            f"  - Case planner={case['planner']} executor={case['executor']} "
            f"embedding={EMBEDDING_MODEL}"
        )
        for query in CONTEXT_QUERIES:
            session_id = unique_session_id()
            request_session_name = unique_session_name(f"context-{case['label']}")
            print(f"    - Query: {query['question']} (session_id={session_id})")
            payload = {
                "prompt": query["question"],
                "session_id": session_id,
                "session_name": request_session_name,
                "tags": [tag_id],
                "planner": case["planner"],
                "executor": case["executor"],
                "embedding_model": EMBEDDING_MODEL,
                "include_global": False,
            }

            try:
                response = requests.post(CHAT_URL, json=payload, timeout=GATEWAY_TIMEOUT_SECONDS, verify=False)
                if response.status_code == 200:
                    data = response.json()
                    answer = data.get("result", "")
                    passed = query["expected_substring"].lower() in answer.lower()
                    results.append({
                        "case": case["name"],
                        "question": query["question"],
                        "passed": passed,
                        "answer": answer[:100] + "...",
                    })
                    print(f"      - Pass: {passed}")
                else:
                    print(f"      - Error: {response.status_code} - {response.text}")
                    results.append({
                        "case": case["name"],
                        "question": query["question"],
                        "passed": False,
                        "answer": response.text[:100] + "...",
                    })
            except Exception as e:
                print(f"      - Failed to connect: {e}")
                results.append({
                    "case": case["name"],
                    "question": query["question"],
                    "passed": False,
                    "answer": str(e)[:100] + "...",
                })

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
