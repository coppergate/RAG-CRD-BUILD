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
        "session_id": "eb984c67-00b6-4794-b848-6d72f20c034b",
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
        "model_name": "llama3.1"
    }
    Draft7Validator(RESPONSE_SCHEMA).validate(ok)


def test_dbop_schema_examples():
    ok = {"op": "delete_session", "id": "eb984c67-00b6-4794-b848-6d72f20c034b"}
    Draft7Validator(DBOP_SCHEMA).validate(ok)


def test_memory_write_schema_examples():
    ok = {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "session_id": "eb984c67-00b6-4794-b848-6d72f20c034b",
        "tags": ["test"],
        "content": "Junie likes tea.",
        "embedding": [0.1] * 4096
    }
    Draft7Validator(MEMORY_WRITE_SCHEMA).validate(ok)


def test_memory_retrieve_schema_examples():
    ok = {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "session_id": "eb984c67-00b6-4794-b848-6d72f20c034b",
        "tags": ["test"],
        "query_vector": [0.1] * 4096,
        "limit": 5
    }
    Draft7Validator(MEMORY_RETRIEVE_SCHEMA).validate(ok)


def test_memory_pack_schema_examples():
    ok = {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "session_id": "eb984c67-00b6-4794-b848-6d72f20c034b",
        "memories": [
            {
                "content": "Junie likes tea.",
                "tags": ["test"],
                "score": 0.95,
                "created_at": "2026-03-25T11:00:00Z"
            }
        ]
    }
    Draft7Validator(MEMORY_PACK_SCHEMA).validate(ok)
