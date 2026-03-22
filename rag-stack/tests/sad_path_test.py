import os
import json
import time
import uuid
import requests
from datetime import datetime
from pulsar import Client

# Configuration from environment
PULSAR_URL = os.getenv("PULSAR_URL", "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650")
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://llm-gateway.rag-system.svc.cluster.local:8080")
if not GATEWAY_URL.startswith("http"):
    GATEWAY_URL = f"http://{GATEWAY_URL}"
# Ensure we don't have double /v1/chat/completions if the env var already includes it
if "/v1/chat/completions" in GATEWAY_URL:
    GATEWAY_BASE_URL = GATEWAY_URL.split("/v1/chat/completions")[0]
else:
    GATEWAY_BASE_URL = GATEWAY_URL

def test_sad_path_gateway():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Sad Path: LLM Gateway")
    
    # 1. Test 405 Method Not Allowed
    print(f"  - Testing 405 Method Not Allowed (GET instead of POST) on {GATEWAY_BASE_URL}/v1/chat/completions ...")
    try:
        resp = requests.get(f"{GATEWAY_BASE_URL}/v1/chat/completions")
        if resp.status_code == 405:
            print(f"    [PASS] Received 405 as expected.")
        else:
            print(f"    [FAIL] Expected 405, got {resp.status_code}")
    except Exception as e:
        print(f"    [ERROR] Connection failed: {e}")

    # 2. Test 400 Bad Request (Malformed JSON)
    print(f"  - Testing 400 Bad Request (Malformed JSON) on {GATEWAY_BASE_URL}/v1/chat/completions ...")
    try:
        headers = {'Content-Type': 'application/json'}
        resp = requests.post(f"{GATEWAY_BASE_URL}/v1/chat/completions", data="invalid-json", headers=headers)
        if resp.status_code == 400:
            print(f"    [PASS] Received 400 as expected.")
        else:
            print(f"    [FAIL] Expected 400, got {resp.status_code}")
    except Exception as e:
        print(f"    [ERROR] Connection failed: {e}")

    # 3. Test 400 Bad Request (Missing required fields - empty body)
    print("  - Testing 400 Bad Request (Empty JSON object)...")
    try:
        resp = requests.post(f"{GATEWAY_BASE_URL}/v1/chat/completions", json={})
        # Note: Depending on how the Go struct is unmarshaled, this might not fail immediately 
        # unless we have validation. But it should trigger some error if 'model' or 'messages' are missing.
        # Based on current code, it doesn't explicitly fail for missing fields, 
        # but worker will fail later if 'prompt' is missing.
        # However, let's see if we get a 503 if Pulsar request fails due to invalid data.
        print(f"    [INFO] Result for empty JSON: {resp.status_code}")
    except Exception as e:
        print(f"    [ERROR] Connection failed: {e}")

def test_sad_path_worker_invalid_payload():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Sad Path: Worker Invalid Payload")
    INGRESS_TOPIC = "persistent://rag-pipeline/stage/ingress"
    
    try:
        # Support TLS for Pulsar if pulsar+ssl is used
        client_args = {}
        ca_bundle = os.getenv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
        if PULSAR_URL.startswith("pulsar+ssl"):
            client_args["tls_trust_certs_file_path"] = ca_bundle
        
        client = Client(PULSAR_URL, **client_args)
        producer = client.create_producer(INGRESS_TOPIC)
        
        # Send a completely invalid payload to ingress
        print(f"  - Sending malformed payload to {INGRESS_TOPIC}...")
        producer.send(b"not a json at all")
        
        # We can't easily assert the worker's log here without access to logs, 
        # but we've triggered the code path:
        # log.Printf("Error unmarshaling payload: %v. Raw: %s", err, string(msg.Payload()))
        
        client.close()
        print("    [DONE] Malformed payload sent to worker.")
    except Exception as e:
        print(f"    [ERROR] Pulsar failure: {e}")

if __name__ == "__main__":
    test_sad_path_gateway()
    print("\n" + "="*50 + "\n")
    test_sad_path_worker_invalid_payload()
