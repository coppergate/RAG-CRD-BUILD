import hashlib
import json
import os
import uuid
from datetime import datetime
from typing import List, Optional, Sequence

import boto3
import psycopg2
import requests
from requests import exceptions as requests_exceptions
from qdrant_client import QdrantClient
from qdrant_client.http import models

from e2e_session_state import cleanup_test_sessions, unique_session_id, unique_session_name
from model_matrix import EMBEDDING_MODEL


S3_ENDPOINT = os.getenv("S3_ENDPOINT", "https://rook-ceph-rgw-ceph-object-store.rook-ceph.svc")
BUCKET_NAME = os.getenv("BUCKET_NAME", "rag-codebase-bucket")
QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", "6333"))
QDRANT_USE_TLS = os.getenv("QDRANT_USE_TLS", "false").lower() == "true"
OLLAMA_URL = os.getenv("OLLAMA_URL", "https://ollama.llms-ollama.svc.cluster.local:11434").rstrip("/")
DB_CONN_STRING = os.getenv("DB_CONN_STRING", "")
VECTOR_SIZE = int(os.getenv("VECTOR_SIZE", "4096"))
CHUNK_SIZE = int(os.getenv("MANUAL_CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.getenv("MANUAL_CHUNK_OVERLAP", "200"))
COLLECTION_PREFIX = os.getenv("QDRANT_COLLECTION", "vectors")
REQUEST_TIMEOUT = int(os.getenv("MANUAL_REQUEST_TIMEOUT", "120"))
QUERY_TOP_K = int(os.getenv("MANUAL_QUERY_TOP_K", "10"))


def _utc() -> str:
    return datetime.utcnow().isoformat()


def log_step(step: str, message: str) -> None:
    print(f"[{_utc()}] [{step}] {message}", flush=True)


def log_json(step: str, label: str, payload) -> None:
    print(f"[{_utc()}] [{step}] {label}: {json.dumps(payload, sort_keys=True, ensure_ascii=False)}", flush=True)


def _ssl_verify_path() -> Optional[str]:
    cert = os.getenv("SSL_CERT_FILE", "")
    if cert and os.path.isfile(cert):
        return cert
    return None


def _requests_session() -> requests.Session:
    session = requests.Session()
    verify = _ssl_verify_path()
    session.verify = verify if verify else False
    return session


def _s3_client():
    verify = _ssl_verify_path()
    return boto3.client("s3", endpoint_url=S3_ENDPOINT, verify=verify if verify else False)


def _qdrant_client() -> QdrantClient:
    return QdrantClient(
        host=QDRANT_HOST,
        port=QDRANT_PORT,
        https=QDRANT_USE_TLS,
        prefer_grpc=False,
        timeout=60,
    )


def _db_connect():
    if not DB_CONN_STRING:
        raise RuntimeError("DB_CONN_STRING is required for the manual ingestion test")
    return psycopg2.connect(DB_CONN_STRING)


def _normalize_model_name(model: str) -> str:
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


def _collection_name(prefix: str, embedding_model: str, vector_size: int) -> str:
    base = prefix.strip() or "vectors"
    normalized = _normalize_model_name(embedding_model)
    if normalized and vector_size > 0:
        return f"{base}-{normalized}-{vector_size}"
    if normalized:
        return f"{base}-{normalized}"
    if vector_size > 0:
        return f"{base}-{vector_size}"
    return base


def _source_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _ollama_embeddings(text: str, model: str) -> List[float]:
    session = _requests_session()
    candidates = [OLLAMA_URL]
    if OLLAMA_URL.startswith("https://"):
        candidates.append("http://" + OLLAMA_URL[len("https://"):])
    elif OLLAMA_URL.startswith("http://"):
        candidates.append("https://" + OLLAMA_URL[len("http://"):])

    last_error: Optional[Exception] = None
    for base_url in candidates:
        try:
            resp = session.post(
                f"{base_url}/api/embeddings",
                json={"model": model, "prompt": text},
                timeout=REQUEST_TIMEOUT,
            )
            resp.raise_for_status()
            payload = resp.json()
            vector = payload["embedding"]
            if not isinstance(vector, list):
                raise TypeError(f"unexpected embedding payload: {type(vector)!r}")
            if base_url != OLLAMA_URL:
                log_step("EMBED", f"fallback Ollama URL succeeded: {base_url}")
            return vector
        except requests_exceptions.SSLError as exc:
            last_error = exc
            log_step("EMBED", f"Ollama SSL error for {base_url}: {exc}")
            continue
        except Exception as exc:
            last_error = exc
            log_step("EMBED", f"Ollama request failed for {base_url}: {exc}")
            continue

    raise RuntimeError(f"failed to obtain embeddings from Ollama after trying {candidates}: {last_error}")


def _vector_preview(vector: Sequence[float], count: int = 5) -> str:
    if not vector:
        return "[]"
    preview = ", ".join(f"{value:.6f}" for value in vector[:count])
    if len(vector) > count:
        preview += ", ..."
    return f"[{preview}]"


def _read_bucket_object(bucket: str, key: str) -> str:
    client = _s3_client()
    resp = client.get_object(Bucket=bucket, Key=key)
    return resp["Body"].read().decode("utf-8")


def _upload_object(bucket: str, key: str, content: str) -> None:
    client = _s3_client()
    client.put_object(Bucket=bucket, Key=key, Body=content.encode("utf-8"))


def _list_bucket_prefix(bucket: str, prefix: str) -> List[str]:
    client = _s3_client()
    resp = client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    keys = []
    for item in resp.get("Contents", []):
        key = item.get("Key")
        if key:
            keys.append(key)
    return keys


def _split_text(text: str, chunk_size: int, chunk_overlap: int) -> List[str]:
    stripped = text.strip()
    if not stripped:
        return []
    if chunk_size <= 0:
        return [stripped]

    paragraphs = [part.strip() for part in stripped.split("\n\n") if part.strip()]
    chunks: List[str] = []
    current = ""

    def flush_current() -> None:
        nonlocal current
        if current.strip():
            chunks.append(current.strip())
        current = ""

    def hard_split(segment: str) -> None:
        if len(segment) <= chunk_size:
            chunks.append(segment.strip())
            return
        step = max(1, chunk_size - max(chunk_overlap, 0))
        start = 0
        while start < len(segment):
            end = min(len(segment), start + chunk_size)
            piece = segment[start:end].strip()
            if piece:
                chunks.append(piece)
            if end >= len(segment):
                break
            start += step

    for paragraph in paragraphs:
        if not current:
            if len(paragraph) <= chunk_size:
                current = paragraph
            else:
                hard_split(paragraph)
            continue

        candidate = f"{current}\n\n{paragraph}"
        if len(candidate) <= chunk_size:
            current = candidate
            continue

        flush_current()
        if len(paragraph) <= chunk_size:
            current = paragraph
        else:
            hard_split(paragraph)

    flush_current()

    if not chunks:
        return [stripped]
    return chunks


def _ensure_collection(client: QdrantClient, collection_name: str, vector_size: int) -> None:
    log_step("QDRANT", f"ensuring collection: {collection_name} vector_size={vector_size}")
    try:
        client.create_collection(
            collection_name=collection_name,
            vectors_config=models.VectorParams(size=vector_size, distance=models.Distance.COSINE),
        )
        log_step("QDRANT", f"created collection: {collection_name} vector_size={vector_size}")
    except Exception as exc:
        if "already exists" in str(exc).lower():
            log_step("QDRANT", f"collection already exists: {collection_name}; continuing")
            return
        raise


def _record_embedding_rows(
    conn,
    ingestion_id: int,
    tag_id: int,
    file_name: str,
    embedding_model: str,
    vector_size: int,
    chunks: List[str],
    vectors: List[List[float]],
    session_id: int,
) -> None:
    with conn.cursor() as cur:
        for index, (chunk, vector) in enumerate(zip(chunks, vectors)):
            metadata = {
                "path": file_name,
                "chunk": index,
                "embedding_model": embedding_model,
                "vector_size": vector_size,
                "source_hash": _source_hash(chunk),
                "session_id": session_id,
            }
            cur.execute(
                "INSERT INTO code_embedding (ingestion_id, embedding_vector, metadata, created_at) "
                "VALUES (%s, %s, %s, NOW()) RETURNING embedding_id",
                (ingestion_id, json.dumps(vector), json.dumps(metadata)),
            )
            embedding_id = cur.fetchone()[0]
            cur.execute(
                "INSERT INTO code_embedding_tag (embedding_id, tag_id) VALUES (%s, %s)",
                (embedding_id, tag_id),
            )
            log_step(
                "DB",
                f"stored code_embedding embedding_id={embedding_id} chunk={index} vector_len={len(vector)} tag_id={tag_id}",
            )
        conn.commit()


def _direct_qdrant_retrieve(
    collection_name: str,
    tag_id: int,
    question: str,
    embedding_model: str,
    expected_secret: str,
) -> dict:
    client = _qdrant_client()
    query_vector = _ollama_embeddings(question, embedding_model)
    tag_filter = models.Filter(
        must=[
            models.FieldCondition(
                key="tags",
                match=models.MatchAny(any=[tag_id]),
            )
        ]
    )

    log_step("QDRANT", f"searching collection={collection_name} with tag_filter={tag_id} query_len={len(question)} vector_len={len(query_vector)}")
    hits = client.search(
        collection_name=collection_name,
        query_vector=query_vector,
        query_filter=tag_filter,
        limit=QUERY_TOP_K,
        with_payload=True,
    )

    summaries = []
    full_texts = []
    for idx, hit in enumerate(hits):
        payload = hit.payload or {}
        text = payload.get("text") or payload.get("content") or ""
        full_texts.append(text)
        summary = {
            "rank": idx,
            "id": hit.id,
            "score": round(float(hit.score), 6),
            "path": payload.get("path"),
            "chunk": payload.get("chunk"),
            "session_id": payload.get("session_id"),
            "tags": payload.get("tags"),
            "text_preview": text[:240],
        }
        summaries.append(summary)
        log_json("QDRANT", f"hit[{idx}]", summary)

    matched = any(expected_secret in text for text in full_texts)
    if not matched:
        raise RuntimeError(
            f"Qdrant search did not return the expected secret {expected_secret!r}; top_hits={json.dumps(summaries[:3], sort_keys=True)}"
        )

    return {"hit_count": len(hits), "top_hits": summaries}


def main() -> None:
    log_step("TEST", "Manual ingestion/retrieval path starting")
    log_json(
        "TEST",
        "config",
        {
            "bucket_name": BUCKET_NAME,
            "collection_prefix": COLLECTION_PREFIX,
            "embedding_model": EMBEDDING_MODEL,
            "qdrant_host": QDRANT_HOST,
            "qdrant_port": QDRANT_PORT,
            "qdrant_use_tls": QDRANT_USE_TLS,
            "chunk_size": CHUNK_SIZE,
            "chunk_overlap": CHUNK_OVERLAP,
            "vector_size": VECTOR_SIZE,
        },
    )

    cleanup_prefixes = (
        "CRUD-Test-",
        "context-",
        "e2e-session-",
        "manual-path-",
        "retrieval-path-",
        "test-session-",
        "trace-session-",
    )
    cleanup_test_sessions(prefixes=cleanup_prefixes)

    ingest_session_id = unique_session_id()
    ingest_session_name = unique_session_name("manual-path-ingest")
    query_session_id = unique_session_id()
    query_session_name = unique_session_name("manual-path-query")
    file_name = f"e2eTestBucket/manual-path-{ingest_session_id}.txt"
    answer = "the best way to tend a flower is to water it lightly, trim dead petals, and place it where it gets soft morning sunlight"
    question = "What is the best way to tend a flower? Return the exact answer from the document."

    content = (
        "Manual ingestion path test document.\n\n"
        f"The best way to tend a flower is {answer}. "
        "This document is intentionally verbose so we can observe chunking, embedding, "
        "Qdrant writes, database writes, and retrieval without going through Pulsar.\n\n"
        "The second paragraph confirms that the object store upload succeeded and that "
        "the retrieval layer can recover the content using the tag-filtered embedding path.\n\n"
        "The final paragraph exists to create another chunk boundary so the test exercises "
        "multiple embedding and upsert operations rather than a single trivial record.\n\n"
        "Additional diagnostic detail: the manual path should upload the exact document, "
        "read it back byte-for-byte, split it into deterministic chunks, embed each chunk "
        "individually, write the points into Qdrant, mirror the metadata into TimescaleDB, "
        "and then retrieve the secret from the vector store using a tag-filtered query.\n\n"
        "This sentence is repeated to push the document comfortably past the default chunk "
        "threshold so the log shows multiple chunk embeddings and multiple Qdrant points."
    )

    log_step("TEST", f"ingest_session_id={ingest_session_id} ingest_session_name={ingest_session_name}")
    log_step("TEST", f"query_session_id={query_session_id} query_session_name={query_session_name}")
    log_step("TEST", f"file_name={file_name}")
    log_step("TEST", f"answer={answer}")
    log_step("TEST", f"question={question}")
    log_step("TEST", f"content_length={len(content)} sha256={_source_hash(content)}")

    conn = _db_connect()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO tag (tag_name, created_at) VALUES (%s, NOW()) "
                "ON CONFLICT (tag_name) DO UPDATE SET tag_name = EXCLUDED.tag_name "
                "RETURNING tag_id, tag_name",
                (f"manual-path-{ingest_session_id}",),
            )
            tag_row = cur.fetchone()
            tag_id = int(tag_row[0])
            tag_name = tag_row[1]

            for session_id, session_name in ((ingest_session_id, ingest_session_name), (query_session_id, query_session_name)):
                cur.execute(
                    "INSERT INTO sessions (session_id, name, created_at, last_active_at) "
                    "VALUES (%s, %s, NOW(), NOW()) "
                    "ON CONFLICT (session_id) DO UPDATE SET name = EXCLUDED.name, last_active_at = NOW() "
                    "RETURNING session_id, name",
                    (session_id, session_name),
                )
                session_row = cur.fetchone()
                cur.execute(
                    "INSERT INTO session_tag (session_id, tag_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                    (int(session_row[0]), tag_id),
                )

            cur.execute(
                "INSERT INTO code_ingestion (ingestion_id, s3_bucket_id, created_at) VALUES (%s, %s, NOW()) "
                "ON CONFLICT (ingestion_id) DO NOTHING",
                (ingest_session_id, BUCKET_NAME),
            )
            cur.execute(
                "INSERT INTO code_ingestion_tag (ingestion_id, tag_id) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                (ingest_session_id, tag_id),
            )
        conn.commit()
        log_step("DB", f"created manual tag tag_id={tag_id} tag_name={tag_name!r}")
        log_step("DB", f"created session rows and session_tag mappings for {ingest_session_id} and {query_session_id}")
        log_step("DB", f"created ingestion record ingestion_id={ingest_session_id}")

        log_step("S3", f"uploading object bucket={BUCKET_NAME!r} key={file_name!r}")
        _upload_object(BUCKET_NAME, file_name, content)
        stored_content = _read_bucket_object(BUCKET_NAME, file_name)
        if stored_content != content:
            raise RuntimeError("uploaded content did not round-trip through object storage")
        log_step("S3", "verified uploaded object round-tripped exactly")
        log_json("S3", "bucket listing", {"prefix": "e2eTestBucket", "keys": _list_bucket_prefix(BUCKET_NAME, "e2eTestBucket")[:10]})

        chunks = _split_text(content, CHUNK_SIZE, CHUNK_OVERLAP)
        if not chunks:
            raise RuntimeError("chunking produced no chunks")
        log_step("CHUNK", f"split document into {len(chunks)} chunk(s)")
        for index, chunk in enumerate(chunks):
            log_json(
                "CHUNK",
                f"chunk[{index}]",
                {
                    "chars": len(chunk),
                    "preview": chunk[:240],
                    "sha256": _source_hash(chunk),
                },
            )

        collection_name = _collection_name(COLLECTION_PREFIX, EMBEDDING_MODEL, VECTOR_SIZE)
        qdrant = _qdrant_client()
        _ensure_collection(qdrant, collection_name, VECTOR_SIZE)

        vectors: List[List[float]] = []
        points = []
        for index, chunk in enumerate(chunks):
            log_step("EMBED", f"embedding chunk[{index}] chars={len(chunk)} model={EMBEDDING_MODEL!r}")
            vector = _ollama_embeddings(chunk, EMBEDDING_MODEL)
            if len(vector) != VECTOR_SIZE:
                log_step("EMBED", f"warning: vector length {len(vector)} did not match configured vector_size={VECTOR_SIZE}")
            vectors.append(vector)
            log_step("EMBED", f"chunk[{index}] vector_len={len(vector)} preview={_vector_preview(vector)}")

            payload = {
                "path": file_name,
                "chunk": index,
                "text": chunk,
                "tags": [tag_id],
                "ingestion_id": ingest_session_id,
                "embedding_model": EMBEDDING_MODEL,
                "vector_size": VECTOR_SIZE,
                "source_hash": _source_hash(chunk),
                "session_id": ingest_session_id,
            }
            point = models.PointStruct(
                id=str(uuid.uuid5(uuid.NAMESPACE_URL, f"{file_name}#{index}")),
                vector=vector,
                payload=payload,
            )
            points.append(point)
            log_json("QDRANT", f"point[{index}]", payload)

        _record_embedding_rows(
            conn,
            ingest_session_id,
            tag_id,
            file_name,
            EMBEDDING_MODEL,
            VECTOR_SIZE,
            chunks,
            vectors,
            ingest_session_id,
        )

        log_step("QDRANT", f"upserting {len(points)} point(s) into collection={collection_name!r}")
        qdrant.upsert(collection_name=collection_name, points=points)
        log_step("QDRANT", "upsert completed")

        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM code_ingestion WHERE ingestion_id = %s", (ingest_session_id,))
            ingestion_rows = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM code_ingestion_tag WHERE ingestion_id = %s", (ingest_session_id,))
            ingestion_tag_rows = cur.fetchone()[0]
            cur.execute(
                "SELECT COUNT(*) FROM code_embedding WHERE ingestion_id = %s",
                (ingest_session_id,),
            )
            embedding_rows = cur.fetchone()[0]
            cur.execute(
                "SELECT COUNT(*) FROM code_embedding_tag t JOIN code_embedding e ON e.embedding_id = t.embedding_id WHERE e.ingestion_id = %s",
                (ingest_session_id,),
            )
            embedding_tag_rows = cur.fetchone()[0]
        log_json(
            "DB",
            "row counts",
            {
                "code_embedding": int(embedding_rows),
                "code_embedding_tag": int(embedding_tag_rows),
                "code_ingestion": int(ingestion_rows),
                "code_ingestion_tag": int(ingestion_tag_rows),
            },
        )

        qdrant_probe = qdrant.scroll(
            collection_name=collection_name,
            scroll_filter=models.Filter(
                must=[
                    models.FieldCondition(
                        key="tags",
                        match=models.MatchAny(any=[tag_id]),
                    )
                ]
            ),
            limit=20,
            with_payload=True,
            with_vectors=False,
        )
        scroll_points = qdrant_probe[0]
        log_step("QDRANT", f"scroll by tag returned {len(scroll_points)} point(s)")
        for idx, point in enumerate(scroll_points[:5]):
            payload = point.payload or {}
            log_json(
                "QDRANT",
                f"scroll[{idx}]",
                {
                    "id": point.id,
                    "path": payload.get("path"),
                    "chunk": payload.get("chunk"),
                    "session_id": payload.get("session_id"),
                    "tags": payload.get("tags"),
                },
            )

        retrieval_summary = _direct_qdrant_retrieve(
            collection_name=collection_name,
            tag_id=tag_id,
            question=question,
            embedding_model=EMBEDDING_MODEL,
            expected_secret=answer,
        )
        log_json("RESULT", "direct retrieval summary", retrieval_summary)

    finally:
        conn.close()

    log_step("SUCCESS", "manual ingestion/retrieval path passed")


if __name__ == "__main__":
    main()
