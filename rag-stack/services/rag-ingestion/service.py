from fastapi import FastAPI, BackgroundTasks, HTTPException
import os
import boto3
import psycopg2
import json
import uuid
import logging
import time
import requests
import pulsar
from botocore.client import Config
from pydantic import BaseModel
from typing import List, Optional

from opentelemetry import trace
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

# Setup Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("rag-ingestor")

# OpenTelemetry Setup
resource = Resource(attributes={SERVICE_NAME: "rag-ingestion"})
provider = TracerProvider(resource=resource)
otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector.monitoring.svc.cluster.local:4318/v1/traces")
if os.getenv("OTEL_USE_TLS") == "true":
    if otlp_endpoint.startswith("http://"):
        otlp_endpoint = otlp_endpoint.replace("http://", "https://")
    elif not otlp_endpoint.startswith("https://"):
        otlp_endpoint = f"https://{otlp_endpoint}"

processor = BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint))
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

RequestsInstrumentor().instrument()

app = FastAPI(title="RAG Ingestion Service")
FastAPIInstrumentor.instrument_app(app)

# Configuration
QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", "6333"))
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama.llms-ollama.svc.cluster.local:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1")
COLLECTION_NAME = "vectors"
CHUNK_SIZE = 1000
S3_ENDPOINT = os.getenv("S3_ENDPOINT")
if S3_ENDPOINT and not S3_ENDPOINT.startswith("http"):
    S3_ENDPOINT = f"http://{S3_ENDPOINT}"

S3_ACCESS_KEY = os.getenv("AWS_ACCESS_KEY_ID")
S3_SECRET_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
BUCKET_NAME = os.getenv("BUCKET_NAME")
DB_CONN_STRING = os.getenv("DB_CONN_STRING")
ALLOWED_EXTENSIONS = os.getenv("ALLOWED_EXTENSIONS", ".md,.sh,.yaml,.yml,.py,.txt,.c,.h,.cpp,.hpp,.cs,.json").split(",")

PULSAR_URL = os.getenv("PULSAR_URL", "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650")
PULSAR_QDRANT_OPS_TOPIC = os.getenv("PULSAR_QDRANT_OPS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops")

class IngestRequest(BaseModel):
    ingestion_id: str
    tag_names: List[str]
    tag_ids: List[str]
    vector_size: Optional[int] = None

def get_db_connection():
    return psycopg2.connect(DB_CONN_STRING)

def get_s3_client():
    return boto3.client(
        's3',
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=S3_ACCESS_KEY,
        aws_secret_access_key=S3_SECRET_KEY,
        config=Config(signature_version='s3v4'),
        region_name='us-east-1'
    )

def get_ollama_embeddings(text: str) -> List[float]:
    url = f"{OLLAMA_URL}/api/embeddings"
    payload = {
        "model": OLLAMA_MODEL,
        "prompt": text
    }
    resp = requests.post(url, json=payload, timeout=60)
    resp.raise_for_status()
    return resp.json()["embedding"]

def get_model_dimensions(model_name: str) -> int:
    try:
        resp = requests.post(f"{OLLAMA_URL}/api/show", json={"name": model_name}, timeout=5)
        if resp.status_code == 200:
            info = resp.json()
            # Try to find dimensions in the response
            # Sometimes it's in model_info, sometimes in details
            dims = info.get("model_info", {}).get("llama.embedding_length") or \
                   info.get("details", {}).get("embedding_length")
            if dims:
                logger.info(f"Detected model {model_name} dimensions: {dims}")
                return int(dims)
    except Exception as e:
        logger.warning(f"Could not probe model dimensions for {model_name}: {e}")
    return 0

def chunk_text(text, size):
    return [text[i:i + size] for i in range(0, len(text), size)]

def run_ingestion(ingestion_id: str, tag_names: List[str], tag_ids: List[str], vector_size: Optional[int] = None):
    try:
        current_vs = vector_size
        if not current_vs:
            current_vs = get_model_dimensions(OLLAMA_MODEL)
        
        logger.info(f"Starting ingestion task for {ingestion_id} using Ollama model {OLLAMA_MODEL} (dims: {current_vs})")
        
        pulsar_client = pulsar.Client(PULSAR_URL, tls_trust_certs_file_path=os.getenv("SSL_CERT_FILE"))
        q_prod = pulsar_client.create_producer(PULSAR_QDRANT_OPS_TOPIC)
        
        s3_client = get_s3_client()
        
        logger.info(f"Ensuring collection {COLLECTION_NAME} via Pulsar (vector_size: {current_vs})")
        q_prod.send(json.dumps({
            "id": f"create-{ingestion_id}",
            "action": "create_collection",
            "collection": COLLECTION_NAME,
            "vector_size": current_vs
        }).encode('utf-8'))

        # List files
        files = []
        paginator = s3_client.get_paginator('list_objects_v2')
        for page in paginator.paginate(Bucket=BUCKET_NAME):
            if 'Contents' in page:
                for obj in page['Contents']:
                    if any(obj['Key'].endswith(ext) for ext in ALLOWED_EXTENSIONS):
                        files.append(obj['Key'])

        logger.info(f"Found {len(files)} files to process.")
        
        conn = get_db_connection()
        points = []
        idx = 0

        for s3_key in files:
            try:
                response = s3_client.get_object(Bucket=BUCKET_NAME, Key=s3_key)
                content = response['Body'].read().decode('utf-8')
                chunks = chunk_text(content, CHUNK_SIZE)
                
                for i, chunk in enumerate(chunks):
                    vector = get_ollama_embeddings(chunk)
                    
                    payload = {
                        "path": s3_key,
                        "chunk": i,
                        "text": chunk,
                        "tags": tag_ids,
                        "ingestion_id": ingestion_id
                    }
                    
                    point_id = str(uuid.uuid4())
                    points.append({
                        "id": point_id,
                        "vector": vector,
                        "payload": payload
                    })
                    
                    # TimescaleDB Backup
                    with conn.cursor() as cur:
                        cur.execute(
                            "INSERT INTO code_embedding (ingestion_id, embedding_vector, metadata) VALUES (%s, %s, %s) RETURNING embedding_id",
                            (ingestion_id, vector, json.dumps({"path": s3_key, "chunk": i}))
                        )
                        emb_id = cur.fetchone()[0]
                        for t_id in tag_ids:
                            cur.execute("INSERT INTO code_embedding_tag (embedding_id, tag_id) VALUES (%s, %s)", (emb_id, t_id))
                    
                    idx += 1
                    if len(points) >= 20: # Smaller batch for Ollama as it might be slower per call
                        q_prod.send(json.dumps({
                            "id": f"upsert-{uuid.uuid4()}",
                            "action": "upsert",
                            "collection": COLLECTION_NAME,
                            "vector_size": current_vs,
                            "points": points
                        }).encode('utf-8'))
                        points = []
                        conn.commit()
                        logger.info(f"Ingested {idx} chunks...")

            except Exception as e:
                logger.error(f"Error processing {s3_key}: {e}")

        if points:
            q_prod.send(json.dumps({
                "id": f"upsert-{uuid.uuid4()}",
                "action": "upsert",
                "collection": COLLECTION_NAME,
                "vector_size": current_vs,
                "points": points
            }).encode('utf-8'))
            conn.commit()
            
        conn.close()
        pulsar_client.close()
        logger.info(f"Ingestion {ingestion_id} completed. Total chunks: {idx}")

    except Exception as e:
        logger.error(f"Ingestion task failed: {e}")

@app.post("/ingest")
async def trigger_ingest(req: IngestRequest, background_tasks: BackgroundTasks):
    logger.info(f"Received ingestion request for ID: {req.ingestion_id} (requested vector_size: {req.vector_size})")
    background_tasks.add_task(run_ingestion, req.ingestion_id, req.tag_names, req.tag_ids, req.vector_size)
    return {"status": "accepted", "ingestion_id": req.ingestion_id}

@app.get("/health")
async def health():
    return {"status": "ok"}

if __name__ == "__main__":
    import uvicorn
    tls_cert = os.getenv("TLS_CERT")
    tls_key = os.getenv("TLS_KEY")
    if tls_cert and tls_key:
        logger.info(f"Starting RAG Ingestion Service with TLS on port 8000")
        uvicorn.run(app, host="0.0.0.0", port=8000, ssl_certfile=tls_cert, ssl_keyfile=tls_key)
    else:
        logger.info(f"Starting RAG Ingestion Service without TLS on port 8000")
        uvicorn.run(app, host="0.0.0.0", port=8000)
