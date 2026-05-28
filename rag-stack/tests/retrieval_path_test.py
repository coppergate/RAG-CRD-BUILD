import json
import os
import time
from datetime import datetime

import boto3
import requests

from e2e_session_state import cleanup_test_sessions, unique_session_id, unique_session_name
from e2e_tag_state import ensure_test_tag
from model_matrix import EMBEDDING_MODEL, model_cases


ADMIN_URL = os.getenv("RAG_ADMIN_API_URL", "https://rag-admin-api.rag.hierocracy.home").rstrip("/")
CHAT_URL = os.getenv("RAG_CHAT_URL", f"{ADMIN_URL}/api/chat/v1/rag/chat")
S3_ENDPOINT = os.getenv("S3_ENDPOINT", "https://rook-ceph-rgw-ceph-object-store.rook-ceph.svc")
BUCKET_NAME = os.getenv("BUCKET_NAME", "rag-codebase-bucket")
TAG_STATE_FILE = os.getenv("RAG_E2E_RETRIEVAL_TAG_STATE_FILE", "/tmp/rag-e2e-retrieval-tag-state.json")
GATEWAY_TIMEOUT_SECONDS = int(os.getenv("GATEWAY_TIMEOUT_SECONDS", "600"))
VECTOR_SIZE = int(os.getenv("VECTOR_SIZE", "4096"))


def _s3_client():
    verify = os.getenv("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
    return boto3.client("s3", endpoint_url=S3_ENDPOINT, verify=verify)


def _upload_file(key: str, content: str) -> None:
    _s3_client().put_object(Bucket=BUCKET_NAME, Key=key, Body=content)


def _trigger_ingest(session_id: int, session_name: str, tag_id: int, file_name: str):
    case = model_cases()[0]
    payload = {
        "ingestion_id": session_id,
        "tag_ids": [tag_id],
        "tag_names": [f"retrieval-path-{tag_id}"],
        "session_id": session_id,
        "session_name": session_name,
        "vector_size": VECTOR_SIZE,
        "file_names": [file_name],
        "embedding_model": EMBEDDING_MODEL,
        "bucket_name": BUCKET_NAME,
        "index": "e2eTestBucket",
    }
    resp = requests.post(
        f"{ADMIN_URL}/api/ingest/ingest",
        json=payload,
        timeout=GATEWAY_TIMEOUT_SECONDS,
        verify=False,
    )
    resp.raise_for_status()
    print(
        f"  - Ingestion accepted (planner={case['planner']} executor={case['executor']}, "
        f"status={resp.status_code})"
    )


def _associate_session_tags(session_id: int, tag_id: int):
    resp = requests.post(
        f"{ADMIN_URL}/api/db/sessions/tags?session_id={session_id}",
        json={"tag_ids": [tag_id]},
        timeout=60,
        verify=False,
    )
    resp.raise_for_status()


def _wait_for_synced_file(session_id: int, file_name: str) -> bool:
    url = f"{ADMIN_URL}/api/db/storage/files?session_id={session_id}"
    start = time.time()
    while time.time() - start < 180:
        resp = requests.get(url, timeout=60, verify=False)
        resp.raise_for_status()
        files = resp.json()
        for item in files:
            if item.get("path") == file_name and item.get("status") == "SYNCED":
                print(f"  - Verified synced file in storage API: {file_name}")
                return True
        time.sleep(3)
    print(f"  - [WARN] Timed out waiting for synced file {file_name}")
    return False


def _submit_query(session_id: int, session_name: str, tag_id: int, question: str, expected: str):
    case = model_cases()[0]
    payload = {
        "prompt": question,
        "session_id": session_id,
        "session_name": session_name,
        "tags": [tag_id],
        "planner": case["planner"],
        "executor": case["executor"],
        "embedding_model": EMBEDDING_MODEL,
        "include_global": False,
        "messages": [
            {"role": "system", "content": "Use only the uploaded context."},
            {"role": "user", "content": question},
        ],
    }
    resp = requests.post(CHAT_URL, json=payload, timeout=GATEWAY_TIMEOUT_SECONDS, verify=False)
    print(f"  - Chat submission status: {resp.status_code}")
    resp.raise_for_status()
    data = resp.json()
    result = data.get("result", "")
    planning = data.get("planning_response", "")
    if expected.lower() not in result.lower():
        raise RuntimeError(f"expected {expected!r} in result, got {result!r}")
    if not planning:
        raise RuntimeError(f"missing planning_response in gateway response: {json.dumps(data)[:500]}")
    print(f"  - Retrieval result verified: {result}")
    return data


def _verify_replay(session_id: int):
    resp = requests.get(f"{ADMIN_URL}/api/db/sessions/{session_id}/messages", timeout=60, verify=False)
    resp.raise_for_status()
    messages = resp.json()
    if not isinstance(messages, list) or not messages:
        raise RuntimeError(f"session replay returned no messages for {session_id}")
    print(f"  - Replay returned {len(messages)} messages")


def _verify_audit(session_id: int):
    resp = requests.get(f"{ADMIN_URL}/api/db/audit/retrieval?session_id={session_id}", timeout=60, verify=False)
    resp.raise_for_status()
    logs = resp.json()
    if not any(item.get("type") == "RETRIEVAL" for item in logs):
        raise RuntimeError(f"no retrieval audit log found for session {session_id}")
    print("  - Retrieval audit log verified")


def main():
    print(f"[{datetime.utcnow().isoformat()}] [TEST] Retrieval Path Isolation")
    cleanup_test_sessions()

    tag = ensure_test_tag(state_file=TAG_STATE_FILE, prefix="test-tag-retrieval-")
    tag_id = tag["tag_id"]
    session_id = unique_session_id()
    session_name = unique_session_name("retrieval-path")
    file_name = f"e2eTestBucket/retrieval-path-{session_id}.txt"
    secret_code = f"BLUE-RETRIEVAL-{session_id}"
    content = (
        f"Retrieval path test document. The secret code is {secret_code}. "
        f"This text is used to verify ingestion, retrieval, submission, and response."
    )
    failures = []

    print(f"  - Using tag {tag['tag_name']} (ID: {tag_id})")
    print(f"  - Session ID: {session_id}")
    print(f"  - Session Name: {session_name}")
    print(f"  - Uploading file: {file_name}")
    _upload_file(file_name, content)

    print("  - Triggering ingestion...")
    _trigger_ingest(session_id, session_name, tag_id, file_name)
    _associate_session_tags(session_id, tag_id)
    if not _wait_for_synced_file(session_id, file_name):
        failures.append("file did not reach SYNCED state within the wait window")

    print("  - Submitting retrieval query...")
    question = "What is the secret code in the retrieval path test document? Answer with the exact code."
    try:
        _submit_query(session_id, session_name, tag_id, question, secret_code)
    except Exception as exc:
        failures.append(f"retrieval query failed: {exc}")
    else:
        try:
            _verify_replay(session_id)
        except Exception as exc:
            failures.append(f"session replay verification failed: {exc}")

        try:
            _verify_audit(session_id)
        except Exception as exc:
            failures.append(f"retrieval audit verification failed: {exc}")

    if failures:
        raise RuntimeError("; ".join(failures))

    print("[SUCCESS] Retrieval path test passed.")


if __name__ == "__main__":
    main()
