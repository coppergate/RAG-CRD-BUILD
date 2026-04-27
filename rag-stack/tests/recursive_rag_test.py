import os
import json
import time
import uuid
import sys
import logging
from datetime import datetime
from pulsar import Client, MessageId, Producer, Consumer

# Configuration from environment
PULSAR_URL = os.getenv("PULSAR_URL", "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650")
INGRESS_TOPIC = os.getenv("PULSAR_INGRESS_TOPIC", "persistent://rag-pipeline/stage/ingress")
RESULTS_TOPIC = os.getenv("PULSAR_RESULTS_TOPIC", "persistent://rag-pipeline/stage/results")
STATUS_TOPIC = os.getenv("PULSAR_STATUS_TOPIC", "persistent://rag-pipeline/stage/status")

def test_recursive_rag_flow():
    # Configure Pulsar logger to ERROR only
    pulsar_logger = logging.getLogger('pulsar')
    pulsar_logger.setLevel(logging.ERROR)
    
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Recursive Multi-Model RAG Flow")
    
    # 1. Initialize Pulsar Client
    print(f"  - Connecting to Pulsar at {PULSAR_URL}")
    client_args = {"logger": pulsar_logger}
    ca_bundle = os.getenv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
    if PULSAR_URL.startswith("pulsar+ssl"):
        client_args["tls_trust_certs_file_path"] = ca_bundle
    client = Client(PULSAR_URL, **client_args)
    
    # Producer for Ingress
    ingress_producer = client.create_producer(INGRESS_TOPIC)
    
    # Consumer for Results
    result_consumer = client.subscribe(RESULTS_TOPIC, "test-recursive-rag-res-" + str(uuid.uuid4())[:8])
    
    # Consumer for Status (Thinking Trace)
    status_consumer = client.subscribe(STATUS_TOPIC, "test-recursive-rag-status-" + str(uuid.uuid4())[:8])

    # 2. Setup Test Request
    correlation_id = str(uuid.uuid4())
    session_id = str(uuid.uuid4())
    
    # A query that should ideally trigger some planning and execution
    # To test recursion, we would need a response that contains "insufficient context"
    # For a general flow test, we'll use a normal query.
    user_query = "What is the primary protocol for Project Alpha?"
    
    payload = {
        "id": correlation_id,
        "session_id": session_id,
        "type": "chat_completion",
        "payload": {
            "model": "granite3.1-dense:8b", # Executor model
            "messages": [{"role": "user", "content": user_query}]
        },
        "timestamp": datetime.now().isoformat()
    }
    
    print(f"  - Sending request to Ingress topic {INGRESS_TOPIC} (ID: {correlation_id})")
    ingress_producer.send(json.dumps(payload).encode('utf-8'))

    # 3. Monitor Status Topic for "Thinking Trace"
    print("  - Monitoring Status messages (Thinking Trace)...")
    expected_states = ["INGRESS_RECEIVED", "PLANNING_TASK", "RETRIEVING_CONTEXT", "EXECUTING_TASK", "COMPLETED"]
    received_states = []
    
    start_time = time.time()
    timeout = 120 # 2 minutes
    
    while time.time() - start_time < timeout:
        try:
            msg = status_consumer.receive(timeout_millis=1000)
            if msg:
                status_data = json.loads(msg.data())
                if status_data.get('id') == correlation_id:
                    state = status_data.get('state')
                    details = status_data.get('details', '')
                    print(f"    [STATUS] {state}: {details}")
                    received_states.append(state)
                    status_consumer.acknowledge(msg)
                    if state == "COMPLETED" or state == "ERROR":
                        break
        except Exception:
            pass

    # 4. Catch final response in Results topic
    print("  - Waiting for final response on Results topic...")
    final_response = None
    try:
        msg = result_consumer.receive(timeout_millis=30000) # Wait 30s more for the result
        if msg:
            res_data = json.loads(msg.data())
            if res_data.get('id') == correlation_id:
                final_response = res_data.get('result')
                print(f"    [OK] Received final result: {final_response[:50]}...")
                result_consumer.acknowledge(msg)
    except Exception as e:
        print(f"    [WARN] Did not receive final result in Pulsar: {e}")

    # 5. Assertions
    print("\n  - Verifying Thinking Trace states:")
    # We expect at least INGRESS, PLAN, RETRIEVE, EXEC
    # Some might be missed due to timing if not using persistent subscriptions properly,
    # but here we use a new sub for the test.
    for state in ["INGRESS_RECEIVED", "PLANNING_TASK", "RETRIEVING_CONTEXT", "EXECUTING_TASK"]:
        if state in received_states:
            print(f"    [PASS] State '{state}' observed.")
        else:
            print(f"    [FAIL] State '{state}' NOT observed.")

    if final_response:
        print("    [PASS] Final response received.")
    else:
        print("    [FAIL] Final response NOT received.")

    # 6. Cleanup
    client.close()
    print("\n[DONE] Recursive RAG Flow test finished.")

if __name__ == "__main__":
    test_recursive_rag_flow()
