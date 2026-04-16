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
BUCKET_NAME = os.getenv("BUCKET_NAME", "rag-codebase-bucket")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:latest")

def test_s3_ops():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Testing S3 Operations...")
    print(f"  - S3_ENDPOINT={S3_ENDPOINT} BUCKET_NAME={BUCKET_NAME}")
    s3 = boto3.client('s3', endpoint_url=S3_ENDPOINT)
    test_file = "test_file.txt"
    test_content = "This is a test content for RAG testing."
    
    # Upload
    s3.put_object(Bucket=BUCKET_NAME, Key=test_file, Body=test_content)
    print(f"  - Uploaded {test_file}")
    
    # Read
    response = s3.get_object(Bucket=BUCKET_NAME, Key=test_file)
    content = response['Body'].read().decode('utf-8')
    assert content == test_content
    print("  - Verified content")
    
    # List
    objects = s3.list_objects_v2(Bucket=BUCKET_NAME)
    keys = [obj['Key'] for obj in objects.get('Contents', [])]
    assert test_file in keys
    print("  - Verified file in listing")

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

def test_rag_retrieval():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Testing RAG Retrieval via Gateway...")
    print(f"  - GATEWAY_URL={GATEWAY_URL}")
    test_file_base = "e2e-test-file-"
    payload = {
        "model": OLLAMA_MODEL,
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
        if response.status_code == 200:
            print("  - Gateway responded successfully")
        else:
            print(f"  - Gateway error: {response.text}")
    except Exception as e:
        print(f"  - Gateway connection failed: {e}")
        raise

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
