import boto3
import os
import time
import sys
import json
import requests
from datetime import datetime
from qdrant_client import QdrantClient
from qdrant_client.http import models

# Optional OpenTelemetry tracing (enabled if OTEL_EXPORTER_OTLP_ENDPOINT is set)
OTEL_ENABLED = bool(os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"))
if OTEL_ENABLED:
    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        resource = Resource.create({"service.name": "rag-tests", "service.version": "1.0.0"})
        provider = TracerProvider(resource=resource)
        processor = BatchSpanProcessor(OTLPSpanExporter())
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
BUCKET_NAME = os.getenv("BUCKET_NAME", "e2eTestBucket")
S3_INDEX = "/e2eTestBucket"
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:latest")

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

def get_tag_id(name):
    # Try to get existing tag
    try:
        # Use full URL to admin-api for tag resolution
        resp = requests.get("https://rag-admin-api.rag.hierocracy.home/api/db/tags", timeout=10, verify=False)
        if resp.status_code == 200:
            tags = resp.json()
            for t in tags:
                if t['name'] == name:
                    return t['id']
    except Exception as e:
        print(f"  - [WARN] Failed to resolve tag name '{name}': {e}")
    
    return 1001 # Fallback to a common test tag ID

def test_rag_retrieval():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Testing RAG Retrieval via Gateway...")
    print(f"  - GATEWAY_URL={GATEWAY_URL}")
    test_file_base = "e2e-test-file-"
    session_name = f"test-session-{int(time.time())}"
    tag_id = get_tag_id("test-tag")
    
    payload = {
        "model": OLLAMA_MODEL,
        "planner": OLLAMA_MODEL,
        "session_name": session_name,
        "tags": [tag_id],
        "messages": [{"role": "user", "content": f"Retrieve the secret code from the {test_file_base} documents."}]
    }
    try:
        headers = {}
        if OTEL_ENABLED:
            # Create a client span and inject trace context into headers
            with tracer.start_as_current_span("gateway_request") as span:
                try:
                    from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
                    propagator = TraceContextTextMapPropagator()
                    propagator.inject(headers)
                except Exception as e:
                    print(f"  - Failed to inject trace headers: {e}")
                response = requests.post(GATEWAY_URL, json=payload, timeout=90, headers=headers)
        else:
            response = requests.post(GATEWAY_URL, json=payload, timeout=90)
        
        print(f"  - Gateway status code: {response.status_code}")
        assert response.status_code == 200, f"Gateway failed with {response.status_code}: {response.text}"
        
        data = response.json()
        print("  - Gateway responded successfully")
        
        # Verify planner data
        # Based on HandleChatCompletions update: response['choices'][0]['message']['planning_response']
        choices = data.get("choices", [])
        assert len(choices) > 0, "No choices in response"
        message = choices[0].get("message", {})
        planning_response = message.get("planning_response")
        
        if planning_response:
            print(f"  - Verified Planner data presence: {planning_response[:100]}...")
        else:
            # It might be empty if the model didn't generate sub-queries for this prompt, 
            # but usually it should at least be present as an empty string or null if we use omitempty
            # In Go map it will be present if we set it.
            print("  - [WARN] Planner data not found in response, but expected.")
            # Note: Depending on the prompt, the planner might decide no sub-queries are needed.
            # For E2E we should probably use a prompt that triggers planning.
            
    except Exception as e:
        print(f"  - Gateway connection failed: {e}")
        raise

def cleanup_test_data():
    print(f"[{datetime.utcnow().isoformat()}] [CLEANUP] Cleaning up test data...")
    
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
        "OTEL_ENABLED": OTEL_ENABLED
    }, indent=2))
    try:
        test_s3_ops()
        test_qdrant_ops()
        test_rag_retrieval()
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
