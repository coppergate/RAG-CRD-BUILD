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
        print(f"Checking prefix: {prefix}")
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

def cleanup_qdrant(client, tag_id, tag_name):
    # We need to check multiple collections (vectors-384, vectors-4096, etc.)
    # In practice we can list all collections or just target vectors-*
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
        
        to_delete = get_tags_to_cleanup(cur)
        
        if not to_delete:
            print("No test data found for cleanup.")
            return

        qdrant_client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, https=QDRANT_USE_TLS, prefer_grpc=False)

        for tag_id, tag_name, last_seen in to_delete:
            print(f"Processing cleanup for tag: {tag_name} (ID: {tag_id}, Last Seen: {last_seen})")
            
            # 1. Cleanup Qdrant
            cleanup_qdrant(qdrant_client, tag_id, tag_name)
            
            # 2. Cleanup DB (Tag table cascades)
            if DRY_RUN:
                print(f"  [DRY-RUN] Would delete tag {tag_name} from database")
            else:
                print(f"  Deleting tag {tag_name} from database...")
                cur.execute("DELETE FROM tag WHERE tag_id = %s", (tag_id,))
                
        if not DRY_RUN:
            conn.commit()
            print("\nDatabase changes committed.")
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
