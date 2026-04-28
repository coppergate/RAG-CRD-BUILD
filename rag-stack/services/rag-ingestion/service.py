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
import rag_stack_pb2
from google.protobuf.struct_pb2 import Struct
from google.protobuf import json_format
from botocore.client import Config
from pydantic import BaseModel
from typing import List, Optional

from langchain_text_splitters import RecursiveCharacterTextSplitter

from opentelemetry import trace
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
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
otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector.monitoring.svc.cluster.local:4317")
if otlp_endpoint.startswith("http://"):
    otlp_endpoint = otlp_endpoint.replace("http://", "")
elif otlp_endpoint.startswith("https://"):
    otlp_endpoint = otlp_endpoint.replace("https://", "")

use_tls = os.getenv("OTEL_USE_TLS", "false").lower() == "true"
insecure = not use_tls

# Ensure OTEL exporter trusts our CA if using TLS
credentials = None
if use_tls:
    if SSL_CERT_FILE and os.path.isfile(SSL_CERT_FILE):
        with open(SSL_CERT_FILE, "rb") as f:
            from grpc import ssl_channel_credentials
            credentials = ssl_channel_credentials(root_certificates=f.read())
            logger.info(f"OTEL exporter using CA from SSL_CERT_FILE: {SSL_CERT_FILE}")

processor = BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint, insecure=insecure, credentials=credentials))
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
    session_id: Optional[str] = None
    vector_size: Optional[int] = None
    file_names: Optional[List[str]] = None
    bucket_name: Optional[str] = None
    prefix: Optional[str] = None
    index: Optional[str] = None

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

def run_ingestion(ingestion_id: str, tag_names: List[str], tag_ids: List[str], 
                  vector_size: Optional[int] = None, file_names: Optional[List[str]] = None, 
                  session_id: Optional[str] = None, bucket_name: Optional[str] = None, 
                  prefix: Optional[str] = None, index: Optional[str] = None):
    pool = get_db_pool()
    conn = None
    pulsar_client = None
    failed_chunks = []

    try:
        current_vs = vector_size
        if not current_vs:
            current_vs = get_model_dimensions(QDRANT_MODEL)

        effective_bucket = bucket_name or BUCKET_NAME
        effective_prefix = index or prefix or ""
        
        # S3 Prefix (index) should not have leading slash for boto3
        if effective_prefix.startswith("/"):
            effective_prefix = effective_prefix.lstrip("/")

        logger.info(f"Starting ingestion task for {ingestion_id} using Ollama model {QDRANT_MODEL} (dims: {current_vs}) on bucket {effective_bucket} (prefix: {effective_prefix})")

        pulsar_client = _create_pulsar_client()
        q_prod = pulsar_client.create_producer(PULSAR_QDRANT_OPS_TOPIC)

        s3_client = get_s3_client()

        logger.info(f"Ensuring collection {COLLECTION_NAME} via Protobuf Pulsar (vector_size: {current_vs})")
        op = rag_stack_pb2.QdrantOp()
        op.id = f"create-{ingestion_id}"
        op.action = "create_collection"
        op.collection = COLLECTION_NAME
        op.vector_size = current_vs
        q_prod.send(json_format.MessageToJson(op).encode('utf-8'))

        # List files
        files = []
        if file_names:
            logger.info(f"Filtering ingestion to explicit file allowlist: {file_names}")
            files = file_names
        else:
            paginator = s3_client.get_paginator('list_objects_v2')
            paginate_kwargs = {'Bucket': effective_bucket}
            if effective_prefix:
                paginate_kwargs['Prefix'] = effective_prefix
            
            for page in paginator.paginate(**paginate_kwargs):
                if 'Contents' in page:
                    for obj in page['Contents']:
                        if any(obj['Key'].endswith(ext) for ext in ALLOWED_EXTENSIONS):
                            files.append(obj['Key'])

        logger.info(f"Found {len(files)} files to process.")

        conn = pool.getconn()

        # Ensure ingestion entry exists to satisfy FK for code_embedding
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO code_ingestion (ingestion_id, s3_bucket_id) VALUES (%s, %s) ON CONFLICT (ingestion_id) DO NOTHING",
                (ingestion_id, effective_bucket)
            )
            conn.commit()

        points = []
        idx = 0

        for s3_key in files:
            try:
                response = s3_client.get_object(Bucket=effective_bucket, Key=s3_key)
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

                    # Ensure ingestion_id is in the tags list for searchability
                    effective_tags = list(tag_ids)
                    if ingestion_id not in effective_tags:
                        effective_tags.append(ingestion_id)

                    payload_struct = Struct()
                    payload_dict = {
                        "path": s3_key,
                        "chunk": i,
                        "text": chunk,
                        "tags": effective_tags,
                        "ingestion_id": ingestion_id
                    }
                    if session_id:
                        payload_dict["session_id"] = session_id
                    payload_struct.update(payload_dict)

                    p = rag_stack_pb2.QdrantPoint()
                    p.id = str(uuid.uuid4())
                    p.vector.extend(vector)
                    p.payload.CopyFrom(payload_struct)
                    points.append(p)

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
                        op = rag_stack_pb2.QdrantOp()
                        op.id = f"upsert-{uuid.uuid4()}"
                        op.action = "upsert"
                        op.collection = COLLECTION_NAME
                        op.vector_size = current_vs
                        op.points.extend(points)
                        q_prod.send(json_format.MessageToJson(op).encode('utf-8'))
                        points = []
                        conn.commit()
                        logger.info(f"Ingested {idx} chunks...")

            except Exception as e:
                logger.error(f"Error processing {s3_key}: {e}")

        if points:
            op = rag_stack_pb2.QdrantOp()
            op.id = f"upsert-{uuid.uuid4()}"
            op.action = "upsert"
            op.collection = COLLECTION_NAME
            op.vector_size = current_vs
            op.points.extend(points)
            q_prod.send(json_format.MessageToJson(op).encode('utf-8'))
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

@app.get("/extensions")
async def get_extensions():
    return {"extensions": ALLOWED_EXTENSIONS}

@app.post("/ingest")
async def trigger_ingest(req: IngestRequest, background_tasks: BackgroundTasks):
    logger.info(f"Received ingestion request for ID: {req.ingestion_id} (bucket: {req.bucket_name}, index/prefix: {req.index or req.prefix}, files: {req.file_names})")
    background_tasks.add_task(
        run_ingestion, 
        req.ingestion_id, 
        req.tag_names, 
        req.tag_ids, 
        req.vector_size, 
        req.file_names, 
        req.session_id,
        req.bucket_name,
        req.prefix,
        req.index
    )
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
