from fastapi import FastAPI, BackgroundTasks, HTTPException
import os
import ssl
import boto3
import psycopg2
import psycopg2.pool
import json
import uuid
import logging
import time
import requests
import pulsar
from botocore.client import Config
from pydantic import BaseModel
from typing import List, Optional

from langchain_text_splitters import RecursiveCharacterTextSplitter

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

# TLS Configuration
SSL_CERT_FILE = os.getenv("SSL_CERT_FILE", "")
ALLOW_INSECURE = os.getenv("ALLOW_INSECURE", "false").lower() == "true"


def _build_requests_session() -> requests.Session:
    """Build an HTTP session with proper CA verification."""
    session = requests.Session()
    if SSL_CERT_FILE and os.path.isfile(SSL_CERT_FILE):
        session.verify = SSL_CERT_FILE
        logger.info(f"HTTP session using CA from SSL_CERT_FILE: {SSL_CERT_FILE}")
    elif not ALLOW_INSECURE:
        logger.warning("SSL_CERT_FILE is not set; using system default CA bundle")
    else:
        logger.warning("Running in INSECURE mode (ALLOW_INSECURE=true)")
    return session


http_session = _build_requests_session()

# OpenTelemetry Setup
resource = Resource(attributes={SERVICE_NAME: "rag-ingestion"})
provider = TracerProvider(resource=resource)
otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector.monitoring.svc.cluster.local:4318/v1/traces")
if os.getenv("OTEL_USE_TLS") == "true":
    if otlp_endpoint.startswith("http://"):
        otlp_endpoint = otlp_endpoint.replace("http://", "https://")
    elif not otlp_endpoint.startswith("https://"):
        otlp_endpoint = f"https://{otlp_endpoint}"
    # Ensure OTEL exporter trusts our CA
    if SSL_CERT_FILE and os.path.isfile(SSL_CERT_FILE):
        os.environ["OTEL_EXPORTER_OTLP_CERTIFICATE"] = SSL_CERT_FILE

processor = BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint))
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

RequestsInstrumentor().instrument()

app = FastAPI(title="RAG Ingestion Service")
FastAPIInstrumentor.instrument_app(app)

# Configuration — defaults are HTTP for Ollama in-cluster
QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", "6333"))
# the current ollama deploy does not support https
_ollama_default = "http://ollama.llms-ollama.svc.cluster.local:11434"
OLLAMA_URL = os.getenv("OLLAMA_URL", _ollama_default)
QDRANT_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:latest")
COLLECTION_NAME = os.getenv("QDRANT_COLLECTION", "vectors")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))
INGEST_BATCH_SIZE = int(os.getenv("INGEST_BATCH_SIZE", "20"))
S3_ENDPOINT = os.getenv("S3_ENDPOINT")
BUCKET_PORT = os.getenv("BUCKET_PORT", "80")
if S3_ENDPOINT and not S3_ENDPOINT.startswith("http"):
    scheme = "https" if BUCKET_PORT == "443" else "http"
    S3_ENDPOINT = f"{scheme}://{S3_ENDPOINT}"

S3_ACCESS_KEY = os.getenv("AWS_ACCESS_KEY_ID")
S3_SECRET_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
BUCKET_NAME = os.getenv("BUCKET_NAME")
DB_CONN_STRING = os.getenv("DB_CONN_STRING")
ALLOWED_EXTENSIONS = os.getenv("ALLOWED_EXTENSIONS", ".md,.sh,.yaml,.yml,.py,.txt,.c,.h,.cpp,.hpp,.cs,.json").split(",")

_pulsar_default = "pulsar+ssl://pulsar-proxy.apache-pulsar.svc.cluster.local:6651" if not ALLOW_INSECURE else "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650"
PULSAR_URL = os.getenv("PULSAR_URL", _pulsar_default)
PULSAR_QDRANT_OPS_TOPIC = os.getenv("PULSAR_QDRANT_OPS_TOPIC", "persistent://rag-pipeline/operations/qdrant-ops")

# Retry configuration
OLLAMA_MAX_RETRIES = int(os.getenv("OLLAMA_MAX_RETRIES", "3"))
OLLAMA_RETRY_BACKOFF = float(os.getenv("OLLAMA_RETRY_BACKOFF", "2.0"))

# Connection pool
DB_POOL_MIN = int(os.getenv("DB_POOL_MIN", "2"))
DB_POOL_MAX = int(os.getenv("DB_POOL_MAX", "10"))

_db_pool = None

def get_db_pool():
    global _db_pool
    if _db_pool is None and DB_CONN_STRING:
        _db_pool = psycopg2.pool.ThreadedConnectionPool(
            DB_POOL_MIN, DB_POOL_MAX, DB_CONN_STRING
        )
        logger.info(f"Database connection pool created (min={DB_POOL_MIN}, max={DB_POOL_MAX})")
    return _db_pool

# Text splitter — sentence/paragraph-aware chunking
text_splitter = RecursiveCharacterTextSplitter(
    chunk_size=CHUNK_SIZE,
    chunk_overlap=CHUNK_OVERLAP,
    length_function=len,
    separators=["\n\n", "\n", ". ", " ", ""],
)

class IngestRequest(BaseModel):
    ingestion_id: str
    tag_names: List[str]
    tag_ids: List[str]
    vector_size: Optional[int] = None
    file_names: Optional[List[str]] = None

def get_s3_client():
    verify = SSL_CERT_FILE if SSL_CERT_FILE and os.path.isfile(SSL_CERT_FILE) else True
    return boto3.client(
        's3',
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=S3_ACCESS_KEY,
        aws_secret_access_key=S3_SECRET_KEY,
        config=Config(signature_version='s3v4'),
        region_name='us-east-1',
        verify=verify
    )

def get_ollama_embeddings_with_retry(text: str) -> List[float]:
    """Get embeddings from Ollama with exponential backoff retry."""
    url = f"{OLLAMA_URL}/api/embeddings"
    payload = {
        "model": QDRANT_MODEL,
        "prompt": text
    }
    last_error = None
    for attempt in range(OLLAMA_MAX_RETRIES):
        try:
            resp = http_session.post(url, json=payload, timeout=60)
            resp.raise_for_status()
            return resp.json()["embedding"]
        except Exception as e:
            last_error = e
            if attempt < OLLAMA_MAX_RETRIES - 1:
                wait = OLLAMA_RETRY_BACKOFF ** attempt
                logger.warning(f"Ollama embedding failed (attempt {attempt + 1}/{OLLAMA_MAX_RETRIES}): {e}. Retrying in {wait:.1f}s...")
                time.sleep(wait)
            else:
                logger.error(f"Ollama embedding failed after {OLLAMA_MAX_RETRIES} attempts: {e}")
    raise last_error

def get_model_dimensions(model_name: str) -> int:
    try:
        resp = http_session.post(f"{OLLAMA_URL}/api/show", json={"name": model_name}, timeout=5)
        if resp.status_code == 200:
            info = resp.json()
            dims = info.get("model_info", {}).get("llama.embedding_length") or \
                   info.get("details", {}).get("embedding_length")
            if dims:
                logger.info(f"Detected model {model_name} dimensions: {dims}")
                return int(dims)
    except Exception as e:
        logger.warning(f"Could not probe model dimensions for {model_name}: {e}")
    return 0

def _create_pulsar_client():
    """Create a Pulsar client with proper TLS configuration."""
    kwargs = {}
    if PULSAR_URL.startswith("pulsar+ssl://"):
        if SSL_CERT_FILE and os.path.isfile(SSL_CERT_FILE):
            kwargs["tls_trust_certs_file_path"] = SSL_CERT_FILE
            logger.info(f"Pulsar client using TLS with CA from: {SSL_CERT_FILE}")
        else:
            logger.warning("Pulsar URL uses TLS but SSL_CERT_FILE is not set or not found")
    return pulsar.Client(PULSAR_URL, **kwargs)

def run_ingestion(ingestion_id: str, tag_names: List[str], tag_ids: List[str], vector_size: Optional[int] = None, file_names: Optional[List[str]] = None):
    pool = get_db_pool()
    conn = None
    pulsar_client = None
    failed_chunks = []

    try:
        current_vs = vector_size
        if not current_vs:
            current_vs = get_model_dimensions(QDRANT_MODEL)

        logger.info(f"Starting ingestion task for {ingestion_id} using Ollama model {QDRANT_MODEL} (dims: {current_vs})")

        pulsar_client = _create_pulsar_client()
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
        if file_names:
            logger.info(f"Filtering ingestion to explicit file allowlist: {file_names}")
            files = file_names
        else:
            paginator = s3_client.get_paginator('list_objects_v2')
            for page in paginator.paginate(Bucket=BUCKET_NAME):
                if 'Contents' in page:
                    for obj in page['Contents']:
                        if any(obj['Key'].endswith(ext) for ext in ALLOWED_EXTENSIONS):
                            files.append(obj['Key'])

        logger.info(f"Found {len(files)} files to process.")

        conn = pool.getconn()
        points = []
        idx = 0

        for s3_key in files:
            try:
                response = s3_client.get_object(Bucket=BUCKET_NAME, Key=s3_key)
                content = response['Body'].read().decode('utf-8')

                # Use langchain text splitter for sentence/paragraph-aware chunking
                chunks = text_splitter.split_text(content)

                for i, chunk in enumerate(chunks):
                    try:
                        vector = get_ollama_embeddings_with_retry(chunk)
                    except Exception as e:
                        logger.error(f"Skipping chunk {i} of {s3_key} after all retries failed: {e}")
                        failed_chunks.append({"file": s3_key, "chunk": i, "error": str(e)})
                        continue

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
                    if len(points) >= INGEST_BATCH_SIZE:
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

        if failed_chunks:
            logger.warning(f"Ingestion {ingestion_id} completed with {len(failed_chunks)} failed chunks out of {idx + len(failed_chunks)} total")
        else:
            logger.info(f"Ingestion {ingestion_id} completed successfully. Total chunks: {idx}")

    except Exception as e:
        logger.error(f"Ingestion task failed: {e}")
    finally:
        if conn and pool:
            pool.putconn(conn)
        if pulsar_client:
            pulsar_client.close()

@app.post("/ingest")
async def trigger_ingest(req: IngestRequest, background_tasks: BackgroundTasks):
    logger.info(f"Received ingestion request for ID: {req.ingestion_id} (requested vector_size: {req.vector_size}, files: {req.file_names})")
    background_tasks.add_task(run_ingestion, req.ingestion_id, req.tag_names, req.tag_ids, req.vector_size, req.file_names)
    return {"status": "accepted", "ingestion_id": req.ingestion_id}

@app.get("/healthz")
async def healthz():
    return {"status": "ok"}

@app.get("/readyz")
async def readyz():
    errors = {}

    # Check DB
    try:
        pool = get_db_pool()
        if pool:
            conn = pool.getconn()
            try:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
            finally:
                pool.putconn(conn)
        else:
            errors["database"] = "connection pool not initialized"
    except Exception as e:
        errors["database"] = str(e)

    # Check Pulsar
    try:
        client = _create_pulsar_client()
        client.close()
    except Exception as e:
        errors["pulsar"] = str(e)

    # Check Ollama
    try:
        logger.info(f"Checking Ollama health at: {OLLAMA_URL}/api/tags")
        resp = http_session.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        resp.raise_for_status()
    except Exception as e:
        logger.error(f"Ollama health check failed for {OLLAMA_URL}: {e}")
        errors["ollama"] = str(e)

    # Check S3
    try:
        s3 = get_s3_client()
        s3.list_buckets()
    except Exception as e:
        errors["s3"] = str(e)

    if errors:
        logger.error(f"Readiness check failed: {errors}")
        raise HTTPException(status_code=503, detail=errors)

    return {"status": "ready"}

@app.get("/health")
async def health_legacy():
    return await healthz()

@app.on_event("shutdown")
async def shutdown_event():
    global _db_pool
    if _db_pool:
        _db_pool.closeall()
        logger.info("Database connection pool closed")

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
