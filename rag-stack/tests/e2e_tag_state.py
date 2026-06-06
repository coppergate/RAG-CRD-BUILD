import json
import os
import time
import uuid

import requests
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


ADMIN_API_URL = os.getenv(
    "RAG_ADMIN_API_URL", "https://rag-admin-api.rag.hierocracy.home"
).rstrip("/")
TAG_PREFIX = os.getenv("RAG_E2E_TAG_PREFIX", "test-tag-")
DEFAULT_STATE_FILE = os.getenv(
    "RAG_E2E_TAG_STATE_FILE", "/tmp/rag-e2e-tag-state.json"
)
VERIFY_TLS = os.getenv("RAG_E2E_VERIFY_TLS", "false").lower() == "true"


def _state_file_path(state_file=None):
    return state_file or DEFAULT_STATE_FILE


def _load_state(state_file=None):
    path = _state_file_path(state_file)
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}


def _save_state(state, state_file=None):
    path = _state_file_path(state_file)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2, sort_keys=True)


def _list_tags():
    resp = requests.get(
        f"{ADMIN_API_URL}/api/db/tags", timeout=10, verify=VERIFY_TLS
    )
    resp.raise_for_status()
    tags = resp.json()
    if not isinstance(tags, list):
        raise ValueError("unexpected tag list response")
    return tags


def _find_tag(tag_name=None, tag_id=None):
    tags = _list_tags()
    for tag in tags:
        if tag_id is not None and int(tag.get("id", -1)) == int(tag_id):
            return tag
        if tag_name is not None and tag.get("name") == tag_name:
            return tag
    return None


def _create_tag(tag_name):
    resp = requests.post(
        f"{ADMIN_API_URL}/api/db/tags",
        json={"name": tag_name},
        timeout=10,
        verify=VERIFY_TLS,
    )
    resp.raise_for_status()

    try:
        payload = resp.json()
    except Exception:
        payload = {}

    tag_id = payload.get("id") or payload.get("tag_id")
    if tag_id is not None:
        return {"tag_name": tag_name, "tag_id": int(tag_id)}

    existing = _find_tag(tag_name=tag_name)
    if not existing:
        raise RuntimeError(f"tag {tag_name!r} was created but could not be resolved")
    return {"tag_name": existing["name"], "tag_id": int(existing["id"])}


def ensure_test_tag(state_file=None, tag_name=None, prefix=None):
    path = _state_file_path(state_file)
    state = _load_state(path)

    if state.get("tag_name") and state.get("tag_id") is not None:
        existing = _find_tag(tag_name=state["tag_name"], tag_id=state["tag_id"])
        if existing:
            return {
                "tag_name": existing["name"],
                "tag_id": int(existing["id"]),
                "state_file": path,
            }

    resolved_name = tag_name
    if not resolved_name:
        resolved_prefix = prefix or TAG_PREFIX
        resolved_name = (
            f"{resolved_prefix}{time.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:6]}"
        )

    created = _create_tag(resolved_name)
    created["state_file"] = path
    _save_state(created, path)
    return created
