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

def run_aggregator_test(test_name, chunks):
    # Configure Pulsar logger to ERROR only
    pulsar_logger = logging.getLogger('pulsar')
    pulsar_logger.setLevel(logging.ERROR)
    
    print(f"[{datetime.utcnow().isoformat()}] [TEST] {test_name}")
    
    # 1. Initialize Pulsar Client
    client_args = {"logger": pulsar_logger}
    ca_bundle = os.getenv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
    if PULSAR_URL.startswith("pulsar+ssl"):
        client_args["tls_trust_certs_file_path"] = ca_bundle
    client = Client(PULSAR_URL, **client_args)
    
    try:
        request_id = str(uuid.uuid4())
        session_id = str(uuid.uuid4())
        session_topic = f"persistent://rag-pipeline/sessions/{request_id}"
        
        print(f"  - Request ID: {request_id}")
        print(f"  - Session Topic: {session_topic}")
        
        # 2. Setup Producers and Consumers
        session_producer = client.create_producer(session_topic)
        completion_producer = client.create_producer(COMPLETION_TOPIC)
        
        # Subscribe to results topic
        sub_name = f"test-{test_name.replace(' ', '-').lower()}-" + str(uuid.uuid4())[:8]
        consumer = client.subscribe(RESULTS_TOPIC, sub_name)
        
        # 3. Send Chunks to Session Topic
        print(f"  - Sending {len(chunks)} chunks to {session_topic}...", end="", flush=True)
        
        for i, text in enumerate(chunks):
            chunk_payload = {
                "id": request_id,
                "sessionId": session_id,
                "result": text,
                "sequenceNumber": i,
                "isLast": (i == len(chunks) - 1),
                "model": "test-aggregator-model",
                "metadata": {"test_name": test_name},
                "inConversation": True
            }
            session_producer.send(json.dumps(chunk_payload).encode('utf-8'))

        print(" [OK]")

        # 4. Trigger Aggregation
        completion_payload = {
            "id": request_id,
            "sessionId": session_id,
            "startTimestamp": datetime.utcnow().isoformat() + "Z",
            "model": "test-aggregator-model",
            "status": "COMPLETED"
        }
        completion_producer.send(json.dumps(completion_payload).encode('utf-8'))
        
        # 5. Wait for Aggregated Result
        print(f"  - Waiting for aggregated result...")
        found_result = False
        start_wait = time.time()
        
        while time.time() - start_wait < 10:
            try:
                msg = consumer.receive(timeout_millis=2500)
                res_data = json.loads(msg.data())
                
                if res_data.get("id") == request_id:
                    result_text = res_data.get("result")
                    expected_text = "".join(chunks)
                    
                    if result_text == expected_text:
                        print(f"    [SUCCESS] Aggregation verified!")
                        found_result = True
                    else:
                        print(f"    [ERROR] Mismatch!")
                        print(f"      Expected: '{expected_text.encode('utf-8')}'")
                        print(f"      Actual:   '{result_text.encode('utf-8')}'")
                        raise Exception("Result mismatch")
                        
                    consumer.acknowledge(msg)
                    break
                else:
                    consumer.acknowledge(msg)
            except Exception as e:
                if "timeout" in str(e).lower():
                    continue
                print(f"    [ERROR] While waiting for result: {e}")
                raise e
        
        if not found_result:
            raise Exception(f"Timed out waiting for result for {request_id}")

    finally:
        client.close()

def main():
    test_cases = [
        {
            "name": "Embedded JSON Test",
            "chunks": [
                '{"key": ',
                '"value", ',
                '"list": [1, 2, 3]}',
                '\nAnd some more text here.'
            ]
        },
        {
            "name": "Special Characters Test",
            "chunks": [
                "Line 1\n",
                "Line 2\r\n",
                "Tab\there\r",
                "End."
            ]
        },
        {
            "name": "Quotes and Backslashes Test",
            "chunks": [
                'He said "Hello \\ World"',
                " it was \"quoted\" and backslashed \\\\"
            ]
        },
        {
            "name": "UTF-8 Multi-byte Characters Test",
            "chunks": [
                "Hello 世界",
                " 👋 \U0001f30e ",
                " \u00a9 2026"
            ]
        },
        {
            "name": "Null Byte Test",
            "chunks": [
                "Before Null\x00After Null",
                " More text after null byte in next chunk"
            ]
        }
    ]
    
    all_passed = True
    for test in test_cases:
        try:
            run_aggregator_test(test["name"], test["chunks"])
        except Exception as e:
            print(f"\n[FAILED] {test['name']}: {e}\n")
            all_passed = False
            
    if all_passed:
        print("\n[ALL TESTS PASSED]")
        sys.exit(0)
    else:
        print("\n[SOME TESTS FAILED]")
        sys.exit(1)

if __name__ == "__main__":
    main()
