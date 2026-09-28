package handlers

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func postIngest(t *testing.T, h *Handler, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/rag/ingest/turn", bytes.NewBufferString(body))
	rec := httptest.NewRecorder()
	h.HandleIngestTurn(rec, req)
	return rec
}

func TestIngestTurnAcceptsAndPublishes(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)

	rec := postIngest(t, hr.h, `{"session":"ses_1","kind":"tool_result","tool":"read","text":"package main"}`)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d: %s", rec.Code, rec.Body.String())
	}
	if len(hr.published) != 1 {
		t.Fatalf("expected one published message, got %d", len(hr.published))
	}

	msg := hr.published[0].(map[string]any)
	if msg["kind"] != "tool_result" || msg["tool"] != "read" {
		t.Errorf("unexpected payload: %v", msg)
	}
	// The consumer should not have to re-resolve the session.
	if msg["session_id"].(int64) != 1421 {
		t.Errorf("expected the resolved session id, got %v", msg["session_id"])
	}
	if msg["external_session"] != "ses_1" {
		t.Errorf("external id should be carried through, got %v", msg["external_session"])
	}
}

func TestIngestTurnDefaultsKind(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	if rec := postIngest(t, hr.h, `{"text":"hello"}`); rec.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d", rec.Code)
	}
	if hr.published[0].(map[string]any)["kind"] != "user_turn" {
		t.Error("expected kind to default to user_turn")
	}
}

func TestIngestTurnRejectsBadKind(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	rec := postIngest(t, hr.h, `{"text":"x","kind":"nonsense"}`)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", rec.Code)
	}
	if len(hr.published) != 0 {
		t.Error("nothing should be published for an invalid kind")
	}
}

func TestIngestTurnRequiresText(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	if rec := postIngest(t, hr.h, `{"session":"ses_1","text":"  "}`); rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", rec.Code)
	}
}

// Publishing a turn must still work when the session cannot be resolved —
// losing the turn is worse than losing its int64 id.
func TestIngestTurnPublishesWithoutSessionMapping(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/tags" {
			_, _ = w.Write([]byte(`[]`))
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	}, noMemory)

	if rec := postIngest(t, hr.h, `{"session":"ses_x","text":"hello"}`); rec.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d", rec.Code)
	}
	if len(hr.published) != 1 {
		t.Fatal("expected the turn to be published anyway")
	}
	if hr.published[0].(map[string]any)["session_id"].(int64) != 0 {
		t.Error("expected session_id 0 when mapping failed")
	}
}

// Disabled ingest says so rather than pretending to have stored the turn.
func TestIngestDisabledIsHonest(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	hr.h.Cfg.IngestEnabled = false

	rec := postIngest(t, hr.h, `{"text":"hello"}`)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d", rec.Code)
	}
	var out map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out["accepted"] != false {
		t.Errorf("expected accepted=false when ingest is disabled, got %v", out["accepted"])
	}
}

func TestIngestPublishFailureIsReported(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	hr.h.Publisher = stubPublisher{got: &hr.published, err: errors.New("broker down")}

	if rec := postIngest(t, hr.h, `{"text":"hello"}`); rec.Code != http.StatusServiceUnavailable {
		t.Errorf("expected 503, got %d", rec.Code)
	}
}

func TestTagsEndpoint(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), tagsDB, noMemory)
	req := httptest.NewRequest(http.MethodGet, "/v1/rag/tags", nil)
	rec := httptest.NewRecorder()
	hr.h.HandleTags(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var out struct {
		Tags            []map[string]any `json:"tags"`
		Count           int              `json:"count"`
		ProfileDefaults map[string][]string `json:"profile_defaults"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out.Count != 2 {
		t.Errorf("expected 2 tags, got %d", out.Count)
	}
	// The §10.5 convention should be visible so a client can check its config.
	if out.ProfileDefaults["executor"][0] != "stack-go" {
		t.Errorf("expected executor defaults echoed, got %v", out.ProfileDefaults)
	}
}

func TestTagsEndpointUpstreamFailure(t *testing.T) {
	hr := newHarness(t, okQdrant(`{"result":[]}`), func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}, noMemory)

	rec := httptest.NewRecorder()
	hr.h.HandleTags(rec, httptest.NewRequest(http.MethodGet, "/v1/rag/tags", nil))
	if rec.Code != http.StatusBadGateway {
		t.Errorf("expected 502, got %d", rec.Code)
	}
}
