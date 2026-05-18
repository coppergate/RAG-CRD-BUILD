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
COMPLETION_TOPIC = os.getenv("PULSAR_COMPLETION_TOPIC", "persistent://rag-pipeline/stage/completion")
RESULTS_TOPIC = os.getenv("PULSAR_RESULTS_TOPIC", "persistent://rag-pipeline/stage/results")

def test_aggregator_flow():
    # Configure Pulsar logger to ERROR only
    pulsar_logger = logging.getLogger('pulsar')
    pulsar_logger.setLevel(logging.ERROR)
    
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Prompt Aggregator Flow")
    
    # 1. Initialize Pulsar Client
    print(f"  - Connecting to Pulsar at {PULSAR_URL}")
    client_args = {"logger": pulsar_logger}
    ca_bundle = os.getenv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
    if PULSAR_URL.startswith("pulsar+ssl"):
        client_args["tls_trust_certs_file_path"] = ca_bundle
    client = Client(PULSAR_URL, **client_args)
    
    try:
        request_id = str(time.time_ns())
        session_id = int(time.time())
        session_topic = f"persistent://rag-pipeline/sessions/{request_id}"
        
        print(f"  - Request ID: {request_id}")
        print(f"  - Session ID: {session_id}")
        print(f"  - Session Topic: {session_topic}")
        
        # 2. Setup Producers and Consumers
        session_producer = client.create_producer(session_topic)
        completion_producer = client.create_producer(COMPLETION_TOPIC)
        
        # Subscribe to results topic to verify output
        sub_name = "test-aggregator-sub-" + str(uuid.uuid4())[:8]
        consumer = client.subscribe(RESULTS_TOPIC, sub_name)
        
        # 3. Send Chunks to Session Topic
        chunks = ["The quick ", "brown fox ", "jumps over ", "the lazy ", "dog."]
        print(f"  - Sending {len(chunks)} chunks to {session_topic}...", end="", flush=True)
        
        for i, text in enumerate(chunks):
            chunk_payload = {
                "id": request_id,
                "session_id": session_id,
                "result": text,
                "sequence_number": i,
                "is_last": (i == len(chunks) - 1),
                "model": "test-aggregator-model",
                "metadata": {"test_source": "aggregator_test.py"},
                "in_conversation": True
            }
            session_producer.send(json.dumps(chunk_payload).encode('utf-8'))
        
        print(" [OK]")

        # 4. Trigger Aggregation with Completion Event
        completion_payload = {
            "id": request_id,
            "session_id": session_id,
            "start_timestamp": datetime.utcnow().isoformat() + "Z",
            "model": "test-aggregator-model",
            "status": "COMPLETED"
        }
        print(f"  - Triggering aggregation via {COMPLETION_TOPIC}")
        completion_producer.send(json.dumps(completion_payload).encode('utf-8'))
        
        # 5. Wait for Aggregated Result
        print(f"  - Waiting for aggregated result on {RESULTS_TOPIC}...")
        found_result = False
        start_wait = time.time()
        
        # We might receive other messages, so we loop and check ID
        while time.time() - start_wait < 30:
            try:
                msg = consumer.receive(timeout_millis=5000)
                res_data = json.loads(msg.data())
                
                if res_data.get("id") == request_id:
                    result_text = res_data.get("result")
                    print(f"    [OK] Received result for {request_id}")
                    print(f"    [DEBUG] Full Payload: {json.dumps(res_data)}")
                    
                    expected_text = "".join(chunks)
                    print(f"    [DEBUG] Validating result text: '{result_text[:20]}...' vs '{expected_text[:20]}...'")
                    if result_text != expected_text:
                         print(f"    [FAIL] Result mismatch! Expected '{expected_text}', got '{result_text}'")
                    
                    received_sid = res_data.get("session_id")
                    print(f"    [DEBUG] Validating session_id: {received_sid} (type: {type(received_sid)}) vs {session_id} (type: {type(session_id)})")
                    if str(received_sid) != str(session_id):
                         print(f"    [FAIL] SessionID mismatch! Expected {session_id}, got {received_sid}")
                    
                    metadata = res_data.get("metadata", {})
                    found_source = metadata.get("test_source")
                    print(f"    [DEBUG] Validating metadata source: '{found_source}'")
                    if found_source != "aggregator_test.py":
                         print(f"    [FAIL] Metadata mismatch! Expected 'aggregator_test.py', got '{found_source}'")

                    if result_text == expected_text and str(received_sid) == str(session_id) and found_source == "aggregator_test.py":
                        print(f"    [SUCCESS] Aggregation verified correctly!")
                        consumer.acknowledge(msg)
                        found_result = True
                        break
                    else:
                        print(f"    [FAIL] Validation failed for {request_id}")
                        consumer.acknowledge(msg)
                        break
                else:
                    consumer.acknowledge(msg)
            except Exception as e:
                # Timeout is normal if we are waiting
                if "timeout" in str(e).lower():
                    continue
                print(f"    [ERROR] While waiting for result: {e}")
                break
        
        if not found_result:
            raise Exception(f"Timed out waiting for aggregated result for ID {request_id}")

    finally:
        client.close()
        print(f"[{datetime.utcnow().isoformat()}] [TEST] Aggregator test finished.")

if __name__ == "__main__":
    try:
        test_aggregator_flow()
        sys.exit(0)
    except Exception as e:
        print(f"TEST FAILED: {e}")
        sys.exit(1)
