import json
import os
from jsonschema import validate, Draft7Validator

BASE = "/mnt/hegemon-share/share/code/complete-build/rag-stack/contracts"

def load_schema(name):
    with open(os.path.join(BASE, name), 'r') as f:
        return json.load(f)

PROMPT_SCHEMA = load_schema("PromptMessage.schema.json")
RESPONSE_SCHEMA = load_schema("ResponseMessage.schema.json")
DBOP_SCHEMA = load_schema("DbOpMessage.schema.json")
MEMORY_WRITE_SCHEMA = load_schema("MemoryWriteRequest.schema.json")
MEMORY_RETRIEVE_SCHEMA = load_schema("MemoryRetrieveRequest.schema.json")
MEMORY_PACK_SCHEMA = load_schema("MemoryPack.schema.json")


def test_prompt_schema_examples():
    ok = {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "session_id": 12345,
        "content": "Who is Junie?",
        "metadata": {"source": "test"}
    }
    Draft7Validator(PROMPT_SCHEMA).validate(ok)


def test_response_schema_examples():
    ok = {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "prompt_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "content": "Junie is an autonomous programmer.",
        "sequence_number": 0,
        "model_name": "llama3.1:latest"
    }
    Draft7Validator(RESPONSE_SCHEMA).validate(ok)


def test_dbop_schema_examples():
    ok = {"op": "delete_session", "id": 12345}
    Draft7Validator(DBOP_SCHEMA).validate(ok)


def test_memory_write_schema_examples():
    ok = {
        "request_id": "123e4567-e89b-12d3-a456-426614174000",
        "scope": {
            "session_id": 12345,
            "project_id": 67890
        },
        "writes": [
            {
                "memory_id": 999,
                "memory_type": "short_term_memory",
                "summary": "Junie likes tea.",
                "content": "Junie likes tea."
            }
        ]
    }
    Draft7Validator(MEMORY_WRITE_SCHEMA).validate(ok)


def test_memory_retrieve_schema_examples():
    ok = {
        "request_id": "123e4567-e89b-12d3-a456-426614174000",
        "scope": {
            "session_id": 12345,
            "project_id": 67890
        },
        "query_text": "Junie",
        "limits": {
            "max_items": 5,
            "max_tokens": 1024
        }
    }
    Draft7Validator(MEMORY_RETRIEVE_SCHEMA).validate(ok)


def test_memory_pack_schema_examples():
    ok = {
        "request_id": "123e4567-e89b-12d3-a456-426614174000",
        "generated_at": "2026-03-25T11:00:00Z",
        "token_budget": {
            "max_tokens": 4096,
            "used_tokens": 100
        },
        "items": [
            {
                "memory_id": 999,
                "memory_type": "short_term_memory",
                "summary": "Junie likes tea.",
                "rank_score": 0.95
            }
        ]
    }
    Draft7Validator(MEMORY_PACK_SCHEMA).validate(ok)
