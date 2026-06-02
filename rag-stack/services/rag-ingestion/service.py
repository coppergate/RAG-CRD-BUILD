from fastapi import FastAPI, BackgroundTasks, HTTPException
import hashlib
import re
import os
import ssl
import boto3
import psycopg2
import psycopg2.pool
import json
import uuid
import logging
import time
import threading
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
from datetime import datetime, timezone

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


def _pg_now():
    return datetime.now(timezone.utc)


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
DEFAULT_EMBEDDING_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1:latest")
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
    ingestion_id: Optional[int] = None
    tag_names: Optional[List[str]] = None
    tag_ids: List[int]
    session_id: Optional[int] = None
    vector_size: Optional[int] = None
    file_names: Optional[List[str]] = None
    embedding_model: Optional[str] = None
    bucket_name: Optional[str] = None
    prefix: Optional[str] = None
    index: Optional[str] = None
    force_reingest: Optional[bool] = False

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

def _effective_embedding_model(requested_model: Optional[str]) -> str:
    model = (requested_model or "").strip()
    if model:
        return model
    return DEFAULT_EMBEDDING_MODEL


def _normalize_model_name(model: str) -> str:
    """Normalize a model name to a safe identifier segment.

    Matches the behaviour of Go's contracts.NormalizeEmbeddingModelName:
    lowercase, collapse runs of non-alphanumeric chars to a single '-',
    strip leading/trailing dashes.  Uses str.isalnum() so Unicode
    letters/digits are treated identically to Go's unicode.IsLetter/IsDigit.
    """
    normalized = []
    last_dash = False
    for ch in model.strip().lower():
        if ch.isalnum():
            normalized.append(ch)
            last_dash = False
        elif not last_dash:
            normalized.append("-")
            last_dash = True
    return "".join(normalized).strip("-")


def _build_collection_name(prefix: str, embedding_model: str, vector_size: int) -> str:
    prefix = (prefix or "").strip() or "vectors"
    model = _normalize_model_name(embedding_model)
    if model and vector_size > 0:
        return f"{prefix}-{model}-{vector_size}"
    if model:
        return f"{prefix}-{model}"
    if vector_size > 0:
        return f"{prefix}-{vector_size}"
    return prefix


def get_ollama_embeddings_with_retry(text: str, model_name: str) -> List[float]:
    """Get embeddings from Ollama with exponential backoff retry."""
    url = f"{OLLAMA_URL}/api/embeddings"
    payload = {
        "model": model_name,
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

_pulsar_client: "pulsar.Client | None" = None
_pulsar_client_lock = threading.Lock()


def get_pulsar_client() -> "pulsar.Client":
    """Return the module-level Pulsar client, creating it on first call.

    Creating a TLS connection per ingest job is expensive; sharing one client
    across all background tasks avoids repeated TLS handshakes.
    """
    global _pulsar_client
    if _pulsar_client is not None:
        return _pulsar_client
    with _pulsar_client_lock:
        if _pulsar_client is not None:
            return _pulsar_client
        kwargs = {}
        if PULSAR_URL.startswith("pulsar+ssl://"):
            if SSL_CERT_FILE and os.path.isfile(SSL_CERT_FILE):
                kwargs["tls_trust_certs_file_path"] = SSL_CERT_FILE
                logger.info(f"Pulsar client using TLS with CA from: {SSL_CERT_FILE}")
            else:
                logger.warning("Pulsar URL uses TLS but SSL_CERT_FILE is not set or not found")
        _pulsar_client = pulsar.Client(PULSAR_URL, **kwargs)
        logger.info("Pulsar client singleton initialised")
        return _pulsar_client

def _source_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _vector_preview(vector: List[float], count: int = 5) -> str:
    if not vector:
        return "[]"
    preview = ", ".join(f"{value:.6f}" for value in vector[:count])
    if len(vector) > count:
        preview += ", ..."
    return f"[{preview}]"


def _log_qdrant_point_summary(
    ingestion_id: int,
    file_name: str,
    chunk_index: int,
    tags: List[int],
    vector: List[float],
    current_model: str,
    current_vs: int,
    source_hash: str,
) -> None:
    logger.info(
        "[ingestion=%s] qdrant-point file=%r chunk=%d model=%r vector_size=%d tag_count=%d tags=%r source_hash=%s vector_preview=%s",
        ingestion_id,
        file_name,
        chunk_index,
        current_model,
        current_vs,
        len(tags),
        tags,
        source_hash,
        _vector_preview(vector),
    )


def _log_qdrant_op(
    ingestion_id: int,
    action: str,
    collection: str,
    vector_size: int,
    embedding_model: str,
    point_count: int = 0,
) -> None:
    logger.info(
        "[ingestion=%s] qdrant-op action=%s collection=%r vector_size=%d embedding_model=%r point_count=%d",
        ingestion_id,
        action,
        collection,
        vector_size,
        embedding_model,
        point_count,
    )


def run_ingestion(ingestion_id: int, tag_names: List[str], tag_ids: List[int],
                  vector_size: Optional[int] = None, file_names: Optional[List[str]] = None,
                  session_id: Optional[int] = None, bucket_name: Optional[str] = None,
                  prefix: Optional[str] = None, index: Optional[str] = None,
                  embedding_model: Optional[str] = None):
    pool = get_db_pool()
    conn = None
    failed_chunks = []
    current_model = _effective_embedding_model(embedding_model)

    try:
        current_vs = vector_size
        if not current_vs:
            current_vs = get_model_dimensions(current_model)

        effective_bucket = bucket_name or BUCKET_NAME
        effective_prefix = index or prefix or ""
        
        # S3 Prefix (index) should not have leading slash for boto3
        if effective_prefix.startswith("/"):
            effective_prefix = effective_prefix.lstrip("/")

        logger.info(
            "[SID:%s] starting ingestion ingestion_id=%s model=%r dims=%d bucket=%r prefix=%r requested_tags=%r file_allowlist=%r",
            session_id,
            ingestion_id,
            current_model,
            current_vs,
            effective_bucket,
            effective_prefix,
            tag_ids,
            file_names,
        )

        q_prod = get_pulsar_client().create_producer(PULSAR_QDRANT_OPS_TOPIC)

        s3_client = get_s3_client()
        collection_name = _build_collection_name(COLLECTION_NAME, current_model, current_vs)

        logger.info(
            "[ingestion=%s] ensuring qdrant collection collection=%r base_collection=%r vector_size=%d embedding_model=%r",
            ingestion_id,
            collection_name,
            COLLECTION_NAME,
            current_vs,
            current_model,
        )
        op = rag_stack_pb2.QdrantOp()
        op.id = f"create-{ingestion_id}"
        op.action = "create_collection"
        op.collection = COLLECTION_NAME
        op.vector_size = current_vs
        op.embedding_model = current_model
        _log_qdrant_op(ingestion_id, op.action, op.collection, op.vector_size, op.embedding_model)
        q_prod.send(json_format.MessageToJson(op, preserving_proto_field_name=True).encode('utf-8'))
        logger.info(
            "[ingestion=%s] sent qdrant collection creation op id=%s action=%s collection=%r vector_size=%d embedding_model=%r",
            ingestion_id,
            op.id,
            op.action,
            op.collection,
            op.vector_size,
            op.embedding_model,
        )

        # List files
        files = []
        if file_names:
            logger.info("[ingestion=%s] filtering to explicit file allowlist %r", ingestion_id, file_names)
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

        logger.info("[ingestion=%s] discovered %d files to process", ingestion_id, len(files))

        conn = pool.getconn()

        # Resolve tag names if provided
        if tag_names:
            logger.info("[ingestion=%s] resolving tag names %r", ingestion_id, tag_names)
            try:
                with conn.cursor() as cur:
                    for name in tag_names:
                        cur.execute("SELECT tag_id FROM tag WHERE tag_name = %s", (name,))
                        row = cur.fetchone()
                        if row:
                            if row[0] not in tag_ids:
                                tag_ids.append(row[0])
                        else:
                            logger.warning("[ingestion=%s] tag name %r not found in database", ingestion_id, name)
            except Exception as e:
                logger.error("[ingestion=%s] error resolving tag names: %s", ingestion_id, e)

        # Ensure tag_ids are unique integers
        tag_ids = list(set([int(tid) for tid in tag_ids if tid is not None]))

        # Ingestion entry is now created in trigger_ingest, but we ensure it here just in case
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO code_ingestion (ingestion_id, s3_bucket_id, created_at) VALUES (%s, %s, %s) ON CONFLICT (ingestion_id) DO NOTHING",
                (ingestion_id, effective_bucket, _pg_now())
            )
            
            # Populate code_ingestion_tag mapping
            for t_id in tag_ids:
                cur.execute(
                    "INSERT INTO code_ingestion_tag (ingestion_id, tag_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                    (ingestion_id, t_id)
                )
            conn.commit()
            if tag_ids:
                logger.info("[ingestion=%s] mapped ingestion to tags %r", ingestion_id, tag_ids)

        points = []
        idx = 0

        for s3_key in files:
            logger.info("[ingestion=%s] processing file %r", ingestion_id, s3_key)
            try:
                response = s3_client.get_object(Bucket=effective_bucket, Key=s3_key)
                content = response['Body'].read().decode('utf-8')

                # Use langchain text splitter for sentence/paragraph-aware chunking
                chunks = text_splitter.split_text(content)
                logger.info("[ingestion=%s] split file %r into %d chunks", ingestion_id, s3_key, len(chunks))

                for i, chunk in enumerate(chunks):
                    try:
                        source_hash = _source_hash(chunk)
                        logger.info(
                            "[ingestion=%s] embedding chunk file=%r chunk=%d chars=%d model=%r dims=%d tags=%r hash=%s",
                            ingestion_id,
                            s3_key,
                            i,
                            len(chunk),
                            current_model,
                            current_vs,
                            tag_ids,
                            source_hash,
                        )
                        vector = get_ollama_embeddings_with_retry(chunk, current_model)
                        logger.info(
                            "[ingestion=%s] embedding ready file=%r chunk=%d vector_len=%d preview=%s",
                            ingestion_id,
                            s3_key,
                            i,
                            len(vector),
                            _vector_preview(vector),
                        )
                    except Exception as e:
                        logger.error("[ingestion=%s] skipping chunk file=%r chunk=%d after embedding failure: %s", ingestion_id, s3_key, i, e)
                        failed_chunks.append({"file": s3_key, "chunk": i, "error": str(e)})
                        continue

                    effective_tags = list(tag_ids)

                    payload_struct = Struct()
                    payload_dict = {
                        "path": s3_key,
                        "chunk": i,
                        "text": chunk,
                        "tags": effective_tags,
                        "ingestion_id": ingestion_id,
                        "embedding_model": current_model,
                        "vector_size": current_vs,
                        "source_hash": source_hash,
                    }
                    payload_struct.update(payload_dict)
                    logger.info(
                        "[ingestion=%s] qdrant payload file=%r chunk=%d payload=%s",
                        ingestion_id,
                        s3_key,
                        i,
                        json.dumps(payload_dict, sort_keys=True),
                    )

                    p = rag_stack_pb2.QdrantPoint()
                    p.id = str(uuid.uuid4())
                    p.vector.extend(vector)
                    p.payload.CopyFrom(payload_struct)
                    _log_qdrant_point_summary(
                        ingestion_id,
                        s3_key,
                        i,
                        effective_tags,
                        vector,
                        current_model,
                        current_vs,
                        source_hash,
                    )
                    points.append(p)

                    # TimescaleDB Backup
                    with conn.cursor() as cur:
                        cur.execute(
                            "INSERT INTO code_embedding (ingestion_id, embedding_vector, metadata, created_at) VALUES (%s, %s, %s, %s) RETURNING embedding_id",
                            (ingestion_id, json.dumps(vector), json.dumps({
                            "path": s3_key,
                            "chunk": i,
                            "embedding_model": current_model,
                            "vector_size": current_vs,
                            "source_hash": _source_hash(chunk),
                        }), _pg_now())
                        )
                        emb_id = cur.fetchone()[0]
                        logger.info(
                            "[ingestion=%s] inserted code_embedding embedding_id=%s file=%r chunk=%d tags=%r",
                            ingestion_id,
                            emb_id,
                            s3_key,
                            i,
                            effective_tags,
                        )
                        for t_id in tag_ids:
                            cur.execute("INSERT INTO code_embedding_tag (embedding_id, tag_id) VALUES (%s, %s)", (emb_id, t_id))
                        if tag_ids:
                            logger.info(
                                "[ingestion=%s] mapped code_embedding embedding_id=%s to tags=%r",
                                ingestion_id,
                                emb_id,
                                tag_ids,
                            )

                    idx += 1
                    if len(points) >= INGEST_BATCH_SIZE:
                        op = rag_stack_pb2.QdrantOp()
                        op.id = f"upsert-{uuid.uuid4()}"
                        op.action = "upsert"
                        op.collection = COLLECTION_NAME
                        op.vector_size = current_vs
                        op.embedding_model = current_model
                        op.points.extend(points)
                        _log_qdrant_op(
                            ingestion_id,
                            op.action,
                            op.collection,
                            op.vector_size,
                            op.embedding_model,
                            len(points),
                        )
                        conn.commit()
                        logger.info("[ingestion=%s] committed batch; total processed chunks=%d", ingestion_id, idx)
                        q_prod.send(json_format.MessageToJson(op, preserving_proto_field_name=True).encode('utf-8'))
                        logger.info(
                            "[ingestion=%s] sent qdrant upsert op id=%s points=%d collection=%r model=%r dims=%d",
                            ingestion_id,
                            op.id,
                            len(points),
                            op.collection,
                            op.embedding_model,
                            op.vector_size,
                        )
                        points = []

            except Exception as e:
                logger.error(f"Error processing {s3_key}: {e}")

        if points:
            op = rag_stack_pb2.QdrantOp()
            op.id = f"upsert-{uuid.uuid4()}"
            op.action = "upsert"
            op.collection = COLLECTION_NAME
            op.vector_size = current_vs
            op.embedding_model = current_model
            op.points.extend(points)
            _log_qdrant_op(
                ingestion_id,
                op.action,
                op.collection,
                op.vector_size,
                op.embedding_model,
                len(points),
            )
            conn.commit()
            q_prod.send(json_format.MessageToJson(op, preserving_proto_field_name=True).encode('utf-8'))
            logger.info(
                "[ingestion=%s] sent final qdrant upsert op id=%s points=%d collection=%r model=%r dims=%d",
                ingestion_id,
                op.id,
                len(points),
                op.collection,
                op.embedding_model,
                op.vector_size,
            )

        if failed_chunks:
            logger.warning(
                "[ingestion=%s] completed with %d failed chunks out of %d total; failures=%r",
                ingestion_id,
                len(failed_chunks),
                idx + len(failed_chunks),
                failed_chunks,
            )
        else:
            logger.info("[ingestion=%s] completed successfully; total chunks=%d", ingestion_id, idx)

    except Exception as e:
        logger.error("[ingestion=%s] ingestion task failed: %s", ingestion_id, e)
    finally:
        if conn and pool:
            pool.putconn(conn)

@app.get("/extensions")
async def get_extensions():
    return {"extensions": ALLOWED_EXTENSIONS}

@app.post("/ingest")
async def trigger_ingest(req: IngestRequest, background_tasks: BackgroundTasks):
    ingestion_id = req.ingestion_id or 0
    tag_names = req.tag_names or []
    effective_bucket = req.bucket_name or BUCKET_NAME

    # Ensure ingestion entry exists to satisfy FK and return a real ID
    if ingestion_id == 0:
        try:
            pool = get_db_pool()
            conn = pool.getconn()
            try:
                with conn.cursor() as cur:
                    cur.execute(
                        "INSERT INTO code_ingestion (s3_bucket_id, created_at) VALUES (%s, %s) RETURNING ingestion_id",
                        (effective_bucket, _pg_now())
                    )
                    ingestion_id = cur.fetchone()[0]
                    conn.commit()
                    logger.info("[ingest] created new ingestion record ingestion_id=%s bucket=%r", ingestion_id, effective_bucket)
            finally:
                pool.putconn(conn)
        except Exception as e:
            logger.error("[ingest] failed to create ingestion record: %s", e)
            # Fallback to 0 if DB fails, though task might fail too
    
    logger.info(
        "[ingest] received request ingestion_id=%s bucket=%r index=%r prefix=%r tag_ids=%r tag_names=%r file_names=%r vector_size=%r embedding_model=%r force_reingest=%r",
        ingestion_id,
        effective_bucket,
        req.index,
        req.prefix,
        req.tag_ids,
        tag_names,
        req.file_names,
        req.vector_size,
        req.embedding_model,
        req.force_reingest,
    )
    background_tasks.add_task(
        run_ingestion, 
        ingestion_id, 
        tag_names, 
        req.tag_ids, 
        req.vector_size, 
        req.file_names, 
        req.session_id,
        req.bucket_name,
        req.prefix,
        req.index,
        req.embedding_model
    )
    return {"status": "accepted", "ingestion_id": ingestion_id}

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

    # Check Pulsar (uses shared singleton — no create/close per probe)
    try:
        get_pulsar_client()
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
