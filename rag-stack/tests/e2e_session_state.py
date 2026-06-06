import os
import time
import uuid

import psycopg2


DEFAULT_SESSION_PREFIXES = (
    "CRUD-Test-",
    "Session ",
    "Test-",
    "context-",
    "e2e-session-",
    "retrieval-path-",
    "test-session-",
    "trace-session-",
)


def unique_session_id() -> int:
    return time.time_ns()


def unique_session_name(prefix: str) -> str:
    cleaned_prefix = prefix if prefix.endswith("-") else f"{prefix}-"
    return f"{cleaned_prefix}{time.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}"


def cleanup_test_sessions(prefixes=None):
    db_conn_string = os.getenv("DB_CONN_STRING")
    if not db_conn_string:
        raise RuntimeError("DB_CONN_STRING is required to clean up test sessions")

    target_prefixes = prefixes or DEFAULT_SESSION_PREFIXES
    conn = psycopg2.connect(db_conn_string)
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            for prefix in target_prefixes:
                pattern = f"{prefix}%"
                cur.execute("DELETE FROM sessions WHERE name ILIKE %s", (pattern,))
                print(f"  - Deleted {cur.rowcount} stale sessions matching {pattern}")
    finally:
        conn.close()
