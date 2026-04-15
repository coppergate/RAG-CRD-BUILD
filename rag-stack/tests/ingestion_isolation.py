import os
import json
import time
import uuid
import requests
import sys
from datetime import datetime
from qdrant_client import QdrantClient
from qdrant_client.http import models

# In-cluster endpoints
BASE_URL = "https://rag-web-ui.rag-system.svc.cluster.local" # rag-web-ui Service Name (internal)
QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", "6333"))
QDRANT_USE_TLS = os.getenv("QDRANT_USE_TLS", "true") == "true"
CA_BUNDLE = os.getenv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")

# 1. API Actions for rag-web-ui
def create_tag(tag_name):
    print(f"  - Creating tag: {tag_name}")
    resp = requests.post(f"{BASE_URL}/create-tag", data={"tag_name": tag_name}, verify=False, timeout=10)
    if resp.status_code not in [200, 204, 302]:
        raise Exception(f"Failed to create tag: {resp.status_code} - {resp.text}")

def get_tag_id(tag_name):
    print(f"  - Fetching tag ID for: {tag_name}")
    resp = requests.get(f"{BASE_URL}/", verify=False, timeout=10)
    # Simple regex-like extraction from HTML
    import re
    matches = re.findall(r'<input type="checkbox" name="tags" value="([^"]+)"> ([^<]+)', resp.text)
    for tid, tname in matches:
        if tname.strip() == tag_name:
            return tid
    raise Exception(f"Tag ID for {tag_name} not found in HTML response.")

def upload_file(tag_id, filename, content):
    print(f"  - Uploading file: {filename} with tag ID: {tag_id}")
    files = {'file': (filename, content)}
    resp = requests.post(f"{BASE_URL}/upload", files=files, verify=False, timeout=10)
    if resp.status_code not in [200, 204, 302]:
        raise Exception(f"Failed to upload file: {resp.status_code} - {resp.text}")

def trigger_ingest(tag_id, filename):
    print(f"  - Triggering ingestion for tag ID: {tag_id} (files: {filename})")
    resp = requests.post(f"{BASE_URL}/trigger-ingest", data={"tags": tag_id, "file_names": filename}, verify=False, timeout=10)
    if resp.status_code not in [200, 204, 302]:
        raise Exception(f"Failed to trigger ingest: {resp.status_code} - {resp.text}")

# 2. Vector Store Verification
def verify_in_qdrant(tag_name, expected_text, vector_size, timeout=120):
    # Use tag_id for strict UUID filtering in Qdrant
    tag_id = get_tag_id(tag_name)
    print(f"  - Verifying points in Qdrant for tag_id: {tag_id} (dims: {vector_size})...")
    client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, https=QDRANT_USE_TLS, prefer_grpc=False, timeout=30)
    
    collection_name = f"vectors-{vector_size}"
    
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            results = client.scroll(
                collection_name=collection_name,
                scroll_filter=models.Filter(
                    must=[
                        models.FieldCondition(
                            key="tags",
                            match=models.MatchAny(any=[tag_id])
                        )
                    ]
                ),
                limit=10,
                with_payload=True
            )[0]
            
            if results:
                print(f"    [OK] Found {len(results)} points in Qdrant.")
                for point in results:
                    if expected_text.lower() in str(point.payload.get('text', '')).lower():
                        print(f"    [SUCCESS] Found expected content: '{expected_text}'")
                        return True
                print("    [INFO] Found points, but text content didn't match yet.")
            else:
                print("    [WAIT] No points found yet for this tag.")
        except Exception as e:
            print(f"    [ERROR] Qdrant search failed: {e}")
            
        time.sleep(10)
    
    print("    [FAIL] Timed out waiting for points in Qdrant.")
    return False

def run_isolation_test():
    test_id = str(uuid.uuid4())[:8]
    tag_name = f"iso-test-{test_id}"
    filename = f"iso-file-{test_id}.txt"
    secret_code = f"SECRET-CODE-{test_id}"
    content = f"The isolated test secret code is {secret_code}. Verify this in Qdrant."
    
    # We assume Llama 3.1 (4096 dims)
    vector_size = int(os.getenv("VECTOR_SIZE", "4096"))

    print(f"\n--- Starting Isolated Ingestion Test [{tag_name}] ---")
    try:
        create_tag(tag_name)
        tag_id = get_tag_id(tag_name)
        upload_file(tag_id, filename, content)
        trigger_ingest(tag_id, filename)
        
        # Pass tag_id to verification
        success = verify_in_qdrant(tag_name, secret_code, vector_size)
        if success:
            print(f"\n[PASS] Ingestion pipeline isolated verification: SUCCESS")
        else:
            print(f"\n[FAIL] Ingestion pipeline isolated verification: FAILED")
            sys.exit(1)
            
    except Exception as e:
        print(f"\n[ERROR] Isolation test failed with exception: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run_isolation_test()
