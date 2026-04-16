import os
import json
import time
import uuid
import sys
from datetime import datetime
from pulsar import Client, MessageId, Producer, Consumer

# Configuration from environment
PULSAR_URL = os.getenv("PULSAR_URL", "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650")
COMPLETION_TOPIC = os.getenv("PULSAR_COMPLETION_TOPIC", "persistent://rag-pipeline/stage/completion")
RESULTS_TOPIC = os.getenv("PULSAR_RESULTS_TOPIC", "persistent://rag-pipeline/stage/results")

def test_aggregator_flow():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Prompt Aggregator Flow")
    
    # 1. Initialize Pulsar Client
    print(f"  - Connecting to Pulsar at {PULSAR_URL}")
    client_args = {}
    ca_bundle = os.getenv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
    if PULSAR_URL.startswith("pulsar+ssl"):
        client_args["tls_trust_certs_file_path"] = ca_bundle
    client = Client(PULSAR_URL, **client_args)
    
    try:
        request_id = str(uuid.uuid4())
        session_id = str(uuid.uuid4())
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
        print(f"  - Sending {len(chunks)} chunks to {session_topic}")
        
        for i, text in enumerate(chunks):
            chunk_payload = {
                "id": request_id,
                "session_id": session_id,
                "chunk": text,
                "sequence_number": i,
                "is_last": (i == len(chunks) - 1),
                "model": "test-aggregator-model",
                "metadata": {"test_source": "aggregator_test.py"},
                "in_conversation": True
            }
            session_producer.send(json.dumps(chunk_payload).encode('utf-8'))
            print(f"    [OK] Chunk {i} sent")

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
                    print(f"    [OK] Received result for {request_id}")
                    print(f"    [DATA] Result: '{res_data.get('result')}'")
                    
                    expected_text = "".join(chunks)
                    assert res_data.get("result") == expected_text, f"Result mismatch! Expected '{expected_text}', got '{res_data.get('result')}'"
                    assert res_data.get("session_id") == session_id
                    assert res_data.get("metadata", {}).get("test_source") == "aggregator_test.py"
                    
                    print(f"    [SUCCESS] Aggregation verified correctly!")
                    consumer.acknowledge(msg)
                    found_result = True
                    break
                else:
                    print(f"    [SKIP] Received message for different ID: {res_data.get('id')}")
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
