import os
import sys
import psycopg2
import requests
from qdrant_client import QdrantClient
from qdrant_client.http import models

# Config from env
DB_HOST = os.getenv("DB_HOST", "timescaledb.timescaledb.svc.cluster.local")
DB_NAME = os.getenv("DB_NAME", "app")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "")
DB_CONN_STRING = os.getenv("DB_CONN_STRING", "")

QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant.rag-system.svc.cluster.local")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", "6333"))
QDRANT_USE_TLS = os.getenv("QDRANT_USE_TLS", "true").lower() == "true"

RETAIN_RUNS = int(os.getenv("RETAIN_RUNS", "2"))
TEST_TAG_PREFIXES = os.getenv("TEST_TAG_PREFIXES", "test-tag-,iso-test-").split(",")
DRY_RUN = os.getenv("DRY_RUN", "true").lower() == "true"

def get_tags_to_cleanup(cur):
    to_delete = []
    for prefix in TEST_TAG_PREFIXES:
        if not prefix: continue
        print(f"Checking tag prefix: {prefix}")
        # Get tags and their most recent ingestion timestamp
        cur.execute("""
            SELECT t.tag_id, t.tag_name, MAX(ci.created_at) as last_seen
            FROM tag t
            LEFT JOIN code_ingestion_tag cit ON t.tag_id = cit.tag_id
            LEFT JOIN code_ingestion ci ON cit.ingestion_id = ci.ingestion_id
            WHERE t.tag_name LIKE %s
            GROUP BY t.tag_id, t.tag_name
            ORDER BY last_seen DESC NULLS LAST, t.tag_name DESC
        """, (prefix + "%",))
        
        tags = cur.fetchall()
        print(f"  Found {len(tags)} tags for prefix {prefix}")
        
        if len(tags) > RETAIN_RUNS:
            prefix_to_delete = tags[RETAIN_RUNS:]
            print(f"  Will delete {len(prefix_to_delete)} old tags for prefix {prefix}")
            to_delete.extend(prefix_to_delete)
        else:
            print(f"  No old tags to delete for prefix {prefix} (Retaining {len(tags)})")
            
    return to_delete

def get_sessions_to_cleanup(cur):
    to_delete = []
    # Sessions with test-like names or associated with test tags
    prefixes = ["e2e-", "iso-", "test-"]
    for prefix in prefixes:
        print(f"Checking session prefix: {prefix}")
        cur.execute("""
            SELECT session_id, name, created_at
            FROM sessions
            WHERE name LIKE %s
            ORDER BY created_at DESC
        """, (prefix + "%",))
        
        sess = cur.fetchall()
        print(f"  Found {len(sess)} sessions for prefix {prefix}")
        # We can be aggressive here, but let's keep RETAIN_RUNS if we want some history
        if len(sess) > RETAIN_RUNS:
            to_delete.extend(sess[RETAIN_RUNS:])
            
    return to_delete

def cleanup_qdrant(client, tag_id, tag_name):
    try:
        collections = client.get_collections().collections
        for coll in collections:
            if coll.name.startswith("vectors-"):
                if DRY_RUN:
                    print(f"  [DRY-RUN] Would delete points with tag {tag_id} ({tag_name}) from Qdrant collection {coll.name}")
                else:
                    print(f"  Deleting points with tag {tag_id} ({tag_name}) from Qdrant collection {coll.name}...")
                    client.delete(
                        collection_name=coll.name,
                        points_selector=models.Filter(
                            must=[
                                models.FieldCondition(
                                    key="tags",
                                    match=models.MatchAny(any=[tag_id])
                                )
                            ]
                        )
                    )
    except Exception as e:
        print(f"  Error cleaning up Qdrant for tag {tag_name}: {e}")

def main():
    print(f"--- RAG Test Data Cleanup (Retain: {RETAIN_RUNS}, Dry Run: {DRY_RUN}) ---")
    
    conn = None
    try:
        if DB_CONN_STRING:
            conn = psycopg2.connect(DB_CONN_STRING)
        else:
            conn = psycopg2.connect(
                host=DB_HOST,
                database=DB_NAME,
                user=DB_USER,
                password=DB_PASS
            )
        cur = conn.cursor()
        
        # 1. Cleanup Tags and Vectors
        tags_to_delete = get_tags_to_cleanup(cur)
        if tags_to_delete:
            qdrant_client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, https=QDRANT_USE_TLS, prefer_grpc=False)
            for tag_id, tag_name, last_seen in tags_to_delete:
                print(f"Processing cleanup for tag: {tag_name} (ID: {tag_id})")
                cleanup_qdrant(qdrant_client, tag_id, tag_name)
                if not DRY_RUN:
                    cur.execute("DELETE FROM tag WHERE tag_id = %s", (tag_id,))
        
        # 2. Cleanup Sessions
        sessions_to_delete = get_sessions_to_cleanup(cur)
        for sess_id, sess_name, created_at in sessions_to_delete:
            print(f"Processing cleanup for session: {sess_name} (ID: {sess_id}, Created: {created_at})")
            if DRY_RUN:
                print(f"  [DRY-RUN] Would delete session {sess_id} from database")
            else:
                cur.execute("DELETE FROM sessions WHERE session_id = %s", (sess_id,))

        if not DRY_RUN:
            conn.commit()
            print("\nCleanup committed successfully.")
        else:
            print("\nDry run completed. No changes made.")
            
    except Exception as e:
        print(f"Cleanup failed: {e}")
        if conn and not DRY_RUN:
            conn.rollback()
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    main()
