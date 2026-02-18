import os
import json
import time
import uuid
import psycopg2
from pulsar import Client, MessageId, Producer, Consumer
from datetime import datetime

# Configuration from environment
PULSAR_URL = os.getenv("PULSAR_URL", "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650")
PROMPT_TOPIC = os.getenv("PULSAR_PROMPT_TOPIC", "persistent://rag-pipeline/data/chat-prompts")
RESPONSE_TOPIC = os.getenv("PULSAR_RESPONSE_TOPIC", "persistent://rag-pipeline/data/chat-responses")
DB_OPS_TOPIC = os.getenv("PULSAR_DB_OPS_TOPIC", "persistent://rag-pipeline/operations/db-ops")
QDRANT_OPS_TOPIC = os.getenv("PULSAR_QDRANT_OPS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops")
QDRANT_RESULTS_TOPIC = os.getenv("PULSAR_QDRANT_RESULTS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops-results")
DB_CONN_STRING = os.getenv("DB_CONN_STRING", "postgres://app:app@timescaledb-rw.timescaledb.svc.cluster.local:5432/app?sslmode=disable")

def test_pulsar_db_crud():
    print("[TEST] Pulsar & Database CRUD Interaction")
    
    # 1. Initialize Pulsar Client
    print(f"  - Connecting to Pulsar at {PULSAR_URL}")
    client = Client(PULSAR_URL)
    
    producer = client.create_producer(PROMPT_TOPIC)
    ops_producer = client.create_producer(DB_OPS_TOPIC)
    
    # We create a consumer on the response topic to catch the worker's output
    consumer = client.subscribe(RESPONSE_TOPIC, "test-crud-sub-" + str(uuid.uuid4())[:8])

    # 2. Connect to Database
    print("  - Connecting to TimescaleDB")
    conn = psycopg2.connect(DB_CONN_STRING)
    conn.autocommit = True
    cur = conn.cursor()

    # 3. Setup Test Session
    session_id = str(uuid.uuid4())
    session_name = f"CRUD-Test-{int(time.time())}"
    print(f"  - Creating test session: {session_id}")
    cur.execute("INSERT INTO sessions (session_id, name, description) VALUES (%s, %s, %s)", 
                (session_id, session_name, "Pulsar CRUD Test Session"))

    # 4. Step A: Send Prompt via Pulsar
    correlation_id = str(uuid.uuid4())
    prompt_content = "Who is Junie?"
    
    prompt_payload = {
        "id": correlation_id,
        "session_id": session_id,
        "content": prompt_content
    }
    
    print(f"  - Sending prompt to Pulsar topic {PROMPT_TOPIC} (ID: {correlation_id})")
    producer.send(json.dumps(prompt_payload).encode('utf-8'))

    # 5. Step B: Verify DB Adapter picked it up (Prompts table)
    print("  - Waiting for DB Adapter to insert prompt into TimescaleDB...")
    found_prompt = False
    for _ in range(10):
        cur.execute("SELECT content FROM prompts WHERE prompt_id = %s", (correlation_id,))
        row = cur.fetchone()
        if row:
            assert row[0] == prompt_content
            print("    [OK] Prompt found in 'prompts' table.")
            found_prompt = True
            break
        time.sleep(2)
    
    if not found_prompt:
        raise Exception("Timed out waiting for prompt in DB")

    # 6. Step C: Verify RAG Worker picked it up and produced a response
    print("  - Waiting for RAG Worker and DB Adapter to process response...")
    
    REQUEST_TOPIC = os.getenv("PULSAR_REQUEST_TOPIC", "persistent://rag-pipeline/data/llm-tasks")
    task_producer = client.create_producer(REQUEST_TOPIC)
    
    task_payload = {
        "id": correlation_id,
        "session_id": session_id,
        "type": "chat_completion",
        "payload": {
            "model": "llama3.1",
            "messages": [{"role": "user", "content": prompt_content}]
        },
        "timestamp": datetime.now().isoformat()
    }
    
    print(f"  - Sending task to Pulsar topic {REQUEST_TOPIC}")
    task_producer.send(json.dumps(task_payload).encode('utf-8'))

    # 7. Step D: Catch response in Pulsar
    print("  - Waiting for response on Pulsar topic chat-responses...")
    pulsar_response_received = False
    try:
        msg = consumer.receive(timeout_millis=60000) # 60s timeout
        if msg is None:
            raise Exception("Timeout: No message received on chat-responses topic after 60s")
        res_data = json.loads(msg.data())
        print(f"    [OK] Received response from Pulsar: {res_data.get('result', 'N/A')[:50]}...")
        assert res_data['id'] == correlation_id
        consumer.acknowledge(msg)
        pulsar_response_received = True
    except Exception as e:
        print(f"    [FAIL] Did not receive response in Pulsar: {e}")
        raise e

    # 8. Step E: Verify DB Adapter inserted response into DB
    print("  - Verifying response in TimescaleDB 'responses' table...")
    found_response = False
    for _ in range(10):
        cur.execute("SELECT content FROM responses WHERE prompt_id = (SELECT id FROM prompts WHERE prompt_id = %s LIMIT 1)", (correlation_id,))
        row = cur.fetchone()
        if row:
            print(f"    [OK] Response found in 'responses' table: {row[0][:50]}...")
            found_response = True
            break
        time.sleep(2)

    if not found_response:
        raise Exception("Timed out waiting for response in DB")

    # 9. Step F: Test Pulsar-driven Delete
    print(f"  - Sending delete session op via Pulsar for {session_id}...")
    delete_payload = {
        "op": "delete_session",
        "id": session_id
    }
    ops_producer.send(json.dumps(delete_payload).encode('utf-8'))
    
    print("  - Verifying deletion in DB...")
    deleted = False
    for _ in range(10):
        cur.execute("SELECT 1 FROM sessions WHERE session_id = %s", (session_id,))
        if not cur.fetchone():
            print("    [OK] Session successfully deleted via Pulsar.")
            deleted = True
            break
        time.sleep(2)
    
    if not deleted:
        raise Exception("Timed out waiting for session deletion in DB")

    print("\n[SUCCESS] Pulsar <-> DB CRUD Cycle Verified!")
    client.close()
    conn.close()

def test_pulsar_qdrant_ops():
    print("\n[TEST] Pulsar & Qdrant Search Interaction")
    client = Client(PULSAR_URL)
    
    q_ops_producer = client.create_producer(QDRANT_OPS_TOPIC)
    q_res_consumer = client.subscribe(QDRANT_RESULTS_TOPIC, "test-qdrant-sub-" + str(uuid.uuid4())[:8])

    op_id = str(uuid.uuid4())
    search_payload = {
        "id": op_id,
        "action": "search",
        "collection": "codebase",
        "vector": [0.1] * 384,
        "limit": 1
    }

    print(f"  - Sending Qdrant search op to Pulsar topic {QDRANT_OPS_TOPIC} (ID: {op_id})")
    q_ops_producer.send(json.dumps(search_payload).encode('utf-8'))

    print("  - Waiting for Qdrant result on Pulsar topic...")
    try:
        msg = q_res_consumer.receive(timeout_millis=30000)
        res_data = json.loads(msg.data())
        print(f"    [OK] Received Qdrant result: {res_data}")
        assert res_data['id'] == op_id
        q_res_consumer.acknowledge(msg)
    except Exception as e:
        print(f"    [FAIL] Did not receive Qdrant result in Pulsar: {e}")
        raise e

    print("\n[SUCCESS] Pulsar <-> Qdrant Search Flow Verified!")
    client.close()

if __name__ == "__main__":
    try:
        test_pulsar_db_crud()
        test_pulsar_qdrant_ops()
    except Exception as e:
        print(f"\n[FAILURE] CRUD Test failed: {e}")
        exit(1)
