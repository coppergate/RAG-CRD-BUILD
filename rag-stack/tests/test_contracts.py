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
