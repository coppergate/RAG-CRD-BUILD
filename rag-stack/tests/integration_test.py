import boto3
import os
import time
import sys
import json
import requests
from datetime import datetime
from qdrant_client import QdrantClient
from qdrant_client.http import models
from e2e_session_state import unique_session_id, unique_session_name
from e2e_tag_state import ensure_test_tag
from model_matrix import EMBEDDING_MODEL, model_cases

# Optional OpenTelemetry tracing (enabled if OTEL_EXPORTER_OTLP_ENDPOINT is set)
OTEL_ENABLED = bool(os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"))
if OTEL_ENABLED:
    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from grpc import ssl_channel_credentials

        otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector.monitoring.svc.cluster.local:4317")
        if otlp_endpoint.startswith("http://"):
            otlp_endpoint = otlp_endpoint.replace("http://", "")
        elif otlp_endpoint.startswith("https://"):
            otlp_endpoint = otlp_endpoint.replace("https://", "")

        use_tls = os.getenv("OTEL_USE_TLS", "false").lower() == "true"
        credentials = None
        if use_tls:
            ssl_cert_file = os.getenv("SSL_CERT_FILE", "")
            if ssl_cert_file and os.path.isfile(ssl_cert_file):
                with open(ssl_cert_file, "rb") as f:
                    credentials = ssl_channel_credentials(root_certificates=f.read())

        resource = Resource.create({"service.name": "rag-tests", "service.version": "1.0.0"})
        provider = TracerProvider(resource=resource)
        processor = BatchSpanProcessor(
            OTLPSpanExporter(endpoint=otlp_endpoint, insecure=not use_tls, credentials=credentials)
        )
        provider.add_span_processor(processor)
        trace.set_tracer_provider(provider)
        tracer = trace.get_tracer("rag-tests.integration")
    except Exception as e:
        print(f"[WARN] Failed to initialize OTEL tracing: {e}")
        OTEL_ENABLED = False

# Constants from environment or defaults
endpoint_env = os.getenv("S3_ENDPOINT", "rook-ceph-rgw-ceph-object-store.rook-ceph.svc")
bucket_port = os.getenv("BUCKET_PORT", "443")
if endpoint_env and not endpoint_env.startswith("http"):
    scheme = "https" if bucket_port == "443" else "http"
    S3_ENDPOINT = f"{scheme}://{endpoint_env}"
else:
    S3_ENDPOINT = endpoint_env

QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
GATEWAY_URL = os.getenv("GATEWAY_URL", "https://llm-gateway.rag-system.svc.cluster.local/v1/chat/completions")
CHAT_URL = os.getenv("RAG_CHAT_URL", "https://rag-admin-api.rag.hierocracy.home/api/chat/v1/rag/chat")
ADMIN_URL = os.getenv("ADMIN_URL", "https://rag-admin-api.rag.hierocracy.home")
BUCKET_NAME = os.getenv("BUCKET_NAME", "e2eTestBucket")
S3_INDEX = "/e2eTestBucket"
TAG_STATE_FILE = os.getenv(
    "RAG_E2E_TAG_STATE_FILE", "/tmp/rag-e2e-context-tag-state.json"
)
GATEWAY_TIMEOUT_SECONDS = int(os.getenv("GATEWAY_TIMEOUT_SECONDS", "600"))

def test_s3_ops():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Testing S3 Operations...")
    print(f"  - S3_ENDPOINT={S3_ENDPOINT} BUCKET_NAME={BUCKET_NAME} S3_INDEX={S3_INDEX}")
    s3 = boto3.client('s3', endpoint_url=S3_ENDPOINT)
    test_file = f"{S3_INDEX.strip('/')}/test_file.txt"
    test_content = "This is a test content for RAG testing."
    
    # Ensure bucket exists (optional, depends on environment)
    try:
        s3.create_bucket(Bucket=BUCKET_NAME)
    except:
        pass

    # Upload
    s3.put_object(Bucket=BUCKET_NAME, Key=test_file, Body=test_content)
    print(f"  - Uploaded {test_file}")
    
    # Read
    response = s3.get_object(Bucket=BUCKET_NAME, Key=test_file)
    content = response['Body'].read().decode('utf-8')
    assert content == test_content
    print("  - Verified content")
    
    # List
    objects = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=S3_INDEX.strip('/'))
    keys = [obj['Key'] for obj in objects.get('Contents', [])]
    assert test_file in keys
    print("  - Verified file in listing with prefix")

def test_qdrant_ops():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Testing Qdrant Operations...")
    print(f"  - QDRANT_HOST={QDRANT_HOST}")
    qdrant_use_tls = os.getenv("QDRANT_USE_TLS", "false") == "true"
    client = QdrantClient(host=QDRANT_HOST, port=6333, https=qdrant_use_tls, prefer_grpc=False, timeout=60)
    
    vector_size = int(os.getenv("VECTOR_SIZE", "4096"))
    collection_name = f"test_collection_{vector_size}"
    
    # Recreate collection (handles existing collections gracefully)
    client.recreate_collection(
        collection_name=collection_name,
        vectors_config=models.VectorParams(size=vector_size, distance=models.Distance.COSINE),
    )
    print(f"  - Created collection {collection_name} (size: {vector_size})")
    
    # Upsert dummy data
    client.upsert(
        collection_name=collection_name,
        points=[
            models.PointStruct(
                id=1,
                vector=[0.1] * vector_size,
                payload={"text": "Test vector search"}
            )
        ]
    )
    print("  - Upserted test point")
    
    # Search
    results = client.search(
        collection_name=collection_name,
        query_vector=[0.1] * vector_size,
        limit=1
    )
    assert len(results) > 0
    assert results[0].payload["text"] == "Test vector search"
    print("  - Verified search result")

def test_rag_retrieval(tag_id):
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Testing RAG Retrieval via Gateway...")
    print(f"  - RAG_CHAT_URL={CHAT_URL}")
    print(f"  - Embedding model: {EMBEDDING_MODEL}")
    print(f"  - Tag ID: {tag_id}")
    query = "What is the primary protocol for Project Alpha?"
    system_prompt = "Use only the uploaded context. Reply with the exact secret code and nothing else."

    for case in model_cases():
        session_name = unique_session_name(f"test-session-{case['label']}")
        session_id = unique_session_id()
        payload = {
            "prompt": query,
            "session_id": session_id,
            "session_name": session_name,
            "tags": [tag_id],
            "planner": case["planner"],
            "executor": case["executor"],
            "embedding_model": EMBEDDING_MODEL,
            "include_global": False,
            "messages": [
                {
                    "role": "system",
                    "content": system_prompt,
                },
                {
                    "role": "user",
                    "content": query,
                },
            ],
        }
        try:
            headers = {}
            if OTEL_ENABLED:
                with tracer.start_as_current_span("gateway_request") as span:
                    try:
                        from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
                        propagator = TraceContextTextMapPropagator()
                        propagator.inject(headers)
                    except Exception as e:
                        print(f"  - Failed to inject trace headers: {e}")
                response = requests.post(
                    CHAT_URL,
                    json=payload,
                    timeout=GATEWAY_TIMEOUT_SECONDS,
                    headers=headers,
                    verify=False,
                )
            else:
                response = requests.post(
                    CHAT_URL,
                    json=payload,
                    timeout=GATEWAY_TIMEOUT_SECONDS,
                    verify=False,
                )

            print(
                f"  - Gateway status code ({case['name']}): {response.status_code} "
                f"[planner={case['planner']} executor={case['executor']}]"
            )
            if response.status_code != 200:
                raise RuntimeError(f"gateway returned {response.status_code}: {response.text}")

            data = response.json()
            result = data.get("result", "")
            planning_response = data.get("planning_response", "")
            if "Zeltron-9" not in result:
                raise RuntimeError(f"unexpected result for {case['name']}: {result}")
            if not planning_response:
                raise RuntimeError(f"missing planning_response for {case['name']}: {data}")

            print(f"  - Result verified for {case['name']}")
        except Exception as e:
            print(f"  - [WARN] Gateway connection failed during smoke check for {case['name']}: {e}")
            raise

def test_planner_trace_replay():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Verifying planner trace replay...")
    query = "Inspect the planner output contract and summarize the actions."
    for case in model_cases():
        session_name = unique_session_name(f"trace-session-{case['label']}")
        payload = {
            "prompt": query,
            "session_name": session_name,
            "planner": case["planner"],
            "executor": case["executor"],
            "embedding_model": EMBEDDING_MODEL,
            "messages": [{"role": "user", "content": query}],
        }

        response = requests.post(CHAT_URL, json=payload, timeout=GATEWAY_TIMEOUT_SECONDS, verify=False)
        print(f"  - Gateway status code ({case['name']}): {response.status_code}")
        if response.status_code != 200:
            raise RuntimeError(
                f"gateway planner replay smoke check failed for {case['name']} with "
                f"{response.status_code}: {response.text}"
            )

        data = response.json()
        session_id = data.get("session_id")
        if session_id is None:
            raise RuntimeError(f"missing session_id in gateway response for {case['name']}")

        planning_response = data.get("planning_response", "")
        if not planning_response:
            raise RuntimeError(f"missing planning_response for {case['name']}")
        if "Refined sub-queries for " not in planning_response:
            raise RuntimeError(
                f"planning response did not include refinement output for {case['name']}: {planning_response}"
            )

        admin_resp = requests.get(f"{ADMIN_URL}/api/db/sessions/{int(session_id)}/messages", timeout=60, verify=False)
        print(f"  - Admin replay status code ({case['name']}): {admin_resp.status_code}")
        if admin_resp.status_code != 200:
            raise RuntimeError(f"failed to fetch session replay for {case['name']}: {admin_resp.text}")

        messages = admin_resp.json()
        if not isinstance(messages, list) or not messages:
            raise RuntimeError(f"session replay returned no messages for {case['name']}")

        assistant_messages = [m for m in messages if m.get("role") == "assistant" and m.get("planning_response")]
        if not assistant_messages:
            raise RuntimeError(f"no assistant message with planning_response found for {case['name']}")
        replay_message = assistant_messages[-1]
        replay_planning = replay_message.get("planning_response", "")
        if "Refined sub-queries for " not in replay_planning:
            raise RuntimeError(f"persisted planning response is missing refinement output for {case['name']}")

        metadata = replay_message.get("metadata") or {}
        if "planner_task" not in metadata or "planner_trace" not in metadata:
            raise RuntimeError(f"planner metadata missing from replay for {case['name']}: {metadata}")
        if "chunk_groups" not in metadata or not isinstance(metadata.get("chunk_groups"), list):
            raise RuntimeError(f"chunk_groups missing or invalid in replay metadata for {case['name']}: {metadata}")
        if "plan_step_contexts" not in metadata or not isinstance(metadata.get("plan_step_contexts"), list):
            raise RuntimeError(f"plan_step_contexts missing or invalid in replay metadata for {case['name']}: {metadata}")
        segments = metadata.get("message_segments") or []
        if not segments:
            raise RuntimeError(f"message_segments missing from replay metadata for {case['name']}: {metadata}")
        planning_segments = [seg for seg in segments if seg.get("kind") == "planning"]
        if not planning_segments or len(planning_segments) < 2:
            raise RuntimeError(f"expected multiple planning segments in replay metadata for {case['name']}: {segments}")
        if len(segments) < 3:
            raise RuntimeError(f"replay segments were incomplete for {case['name']}: {segments}")
        if segments[0].get("kind") != "planning" or segments[1].get("kind") != "planning" or segments[2].get("kind") != "content":
            raise RuntimeError(f"replay segment ordering was unexpected for {case['name']}: {segments}")
        if "Planning complete." not in segments[0].get("content", ""):
            raise RuntimeError(f"planner task segment was not preserved for {case['name']}")
        if "Refined sub-queries for " not in segments[1].get("content", ""):
            raise RuntimeError(f"planner refinement segment was not preserved for {case['name']}")
        if not segments[2].get("content", "").strip():
            raise RuntimeError(f"assistant content segment was empty for {case['name']}")
        if segments[2].get("in_conversation") is not True:
            raise RuntimeError(f"assistant content segment lost conversation context for {case['name']}")
        print(f"  - Planner output and replay metadata verified successfully for {case['name']}")

def cleanup_test_data():
    print(f"[{datetime.utcnow().isoformat()}] [CLEANUP] Cleaning up test data...")

    if os.getenv("TEST_CLEANUP_ON_EXIT", "false").lower() != "true":
        print("  - Preserving test artifacts for troubleshooting.")
        print("  - Start-of-run cleanup will remove stale data on the next run.")
        return

    # 1. S3 Cleanup
    try:
        s3 = boto3.client('s3', endpoint_url=S3_ENDPOINT)
        # List all objects in the test index prefix and delete them
        prefix = S3_INDEX.strip('/') + "/"
        print(f"  - Cleaning up S3 prefix: {prefix} in bucket {BUCKET_NAME}")
        
        paginator = s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix=prefix)
        
        delete_keys = []
        for page in pages:
            if 'Contents' in page:
                for obj in page['Contents']:
                    delete_keys.append({'Key': obj['Key']})
        
        if delete_keys:
            print(f"  - Deleting {len(delete_keys)} objects from S3...")
            for i in range(0, len(delete_keys), 1000):
                batch = delete_keys[i:i + 1000]
                s3.delete_objects(Bucket=BUCKET_NAME, Delete={'Objects': batch})
            print(f"  - Successfully deleted {len(delete_keys)} objects.")
        else:
            print(f"  - No objects found to clean up in S3 prefix {prefix}")

        # If bucket is empty, we could delete it, but let's just leave it for now if it's a shared test bucket
        if BUCKET_NAME == "e2eTestBucket":
             print(f"  - Note: Leaving bucket {BUCKET_NAME} in place for other tests.")
    except Exception as e:
        print(f"  - S3 Cleanup warning: {e}")

    # 2. Qdrant Cleanup
    try:
        qdrant_use_tls = os.getenv("QDRANT_USE_TLS", "false") == "true"
        client = QdrantClient(host=QDRANT_HOST, port=6333, https=qdrant_use_tls, prefer_grpc=False)
        vector_size = int(os.getenv("VECTOR_SIZE", "4096"))
        collection_name = f"test_collection_{vector_size}"
        print(f"  - Deleting Qdrant collection: {collection_name}")
        client.delete_collection(collection_name=collection_name)
    except Exception as e:
        print(f"  - Qdrant Cleanup warning: {e}")

if __name__ == "__main__":
    # Note: These tests are intended to run INSIDE the cluster or where endpoints are reachable
    print(f"[{datetime.utcnow().isoformat()}] [ENV] Test configuration:")
    print(json.dumps({
        "S3_ENDPOINT": S3_ENDPOINT,
        "BUCKET_NAME": BUCKET_NAME,
        "QDRANT_HOST": QDRANT_HOST,
        "GATEWAY_URL": GATEWAY_URL,
        "RAG_CHAT_URL": CHAT_URL,
        "MODEL_A": os.getenv("MODEL_A", os.getenv("OLLAMA_MODEL", "llama3.1:latest")),
        "MODEL_B": os.getenv("MODEL_B", "granite3.1-dense:8b"),
        "EMBEDDING_MODEL": EMBEDDING_MODEL,
        "OTEL_ENABLED": OTEL_ENABLED
    }, indent=2))
    try:
        test_s3_ops()
        test_qdrant_ops()
        tag = ensure_test_tag(state_file=TAG_STATE_FILE, prefix="test-tag-integration-")
        test_rag_retrieval(tag["tag_id"])
        test_planner_trace_replay()
        print(f"\n[{datetime.utcnow().isoformat()}] [SUCCESS] All core component tests passed!")
    except Exception as e:
        print(f"\n[{datetime.utcnow().isoformat()}] [FAILURE] Test failed: {e}")
        # Try to provide more diagnostics on failure
        print("[DIAG] Python version:", sys.version)
        print("[DIAG] Installed packages:")
        try:
            import pkgutil
            print([m.name for m in pkgutil.iter_modules()][:50])
        except Exception:
            pass
        exit(1)
    finally:
        cleanup_test_data()
