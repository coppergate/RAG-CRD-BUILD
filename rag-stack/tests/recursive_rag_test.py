import os
import json
import time
import uuid
import sys
import logging
from datetime import datetime
from pulsar import Client, MessageId, Producer, Consumer
from model_matrix import EMBEDDING_MODEL, model_cases

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

    user_query = "What is the primary protocol for Project Alpha?"

    for case in model_cases():
        # 2. Setup Test Request
        correlation_id = str(uuid.uuid4())
        session_id = int(time.time())

        payload = {
            "id": correlation_id,
            "session_id": session_id,
            "session_name": f"Test-{session_id}",
            "prompt": user_query,
            "planner_model": case["planner"],
            "executor_model": case["executor"],
            "embedding_model": EMBEDDING_MODEL,
            "timestamp": datetime.now().isoformat()
        }

        print(
            f"  - Sending request to Ingress topic {INGRESS_TOPIC} "
            f"(planner={case['planner']} executor={case['executor']} embedding={EMBEDDING_MODEL})"
        )
        ingress_producer.send(json.dumps(payload).encode('utf-8'))

        # 3. Monitor Status Topic for "Thinking Trace"
        print("  - Monitoring Status messages (Thinking Trace)...")
        expected_states = ["INGRESS_RECEIVED", "PLANNING_TASK", "RETRIEVING_CONTEXT", "REFINING_PLAN", "EXECUTING_TASK", "COMPLETED"]
        received_states = []

        start_time = time.time()
        timeout = 900 # 15 minutes — llama3.1 makes 2 serial planning calls before EXECUTING_TASK

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
        planning_received = False

        start_time = time.time()
        timeout = 300 # 5 minutes to collect all chunks

        try:
            while time.time() - start_time < timeout:
                msg = result_consumer.receive(timeout_millis=5000)
                if msg:
                    res_data = json.loads(msg.data())
                    if res_data.get('id') == correlation_id:
                        # Collect planning data if present
                        if res_data.get('planning_response'):
                            print(f"    [PLAN] {res_data.get('planning_response')[:50]}...")
                            planning_received = True

                        # Collect result chunk
                        chunk_result = res_data.get('result')
                        if chunk_result:
                            if final_response is None:
                                final_response = ""
                            final_response += chunk_result

                        is_last = res_data.get('is_last', False)
                        if is_last:
                            print(f"    [OK] Received final chunk. Total length: {len(final_response) if final_response else 0}")
                            result_consumer.acknowledge(msg)
                            break

                    result_consumer.acknowledge(msg)
        except Exception as e:
            if "timeout" not in str(e).lower():
                print(f"    [WARN] Error receiving result in Pulsar: {e}")

        # 5. Assertions
        print("\n  - Verifying Thinking Trace states:")
        for state in ["INGRESS_RECEIVED", "PLANNING_TASK", "RETRIEVING_CONTEXT", "REFINING_PLAN", "EXECUTING_TASK"]:
            if state in received_states:
                print(f"    [PASS] State '{state}' observed for {case['name']}.")
            else:
                print(f"    [FAIL] State '{state}' NOT observed for {case['name']}.")

        if final_response:
            print(f"    [PASS] Final response received for {case['name']}.")
        else:
            print(f"    [FAIL] Final response NOT received for {case['name']}.")

    # 6. Cleanup
    client.close()
    print("\n[DONE] Recursive RAG Flow test finished.")

if __name__ == "__main__":
    test_recursive_rag_flow()
