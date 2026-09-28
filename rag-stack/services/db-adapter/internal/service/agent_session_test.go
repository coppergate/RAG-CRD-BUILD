package service_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/agentsession"
	"app-builds/common/ent/enttest"
	"app-builds/db-adapter/internal/service"
	_ "github.com/mattn/go-sqlite3"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newClient(t *testing.T, name string) *ent.Client {
	t.Helper()
	// Distinct DSN per test so the shared in-memory cache does not leak rows
	// between them.
	c := enttest.Open(t, "sqlite3", "file:"+name+"?mode=memory&cache=shared&_fk=1")
	t.Cleanup(func() { _ = c.Close() })
	return c
}

func TestResolveCreatesSessionAndMapping(t *testing.T) {
	client := newClient(t, "as_create")
	svc := service.NewAgentSessionService(client)

	id, created, err := svc.Resolve(context.Background(), "ses_7f3a", "opencode")
	require.NoError(t, err)
	assert.True(t, created, "first sight should report created")
	assert.NotZero(t, id)

	// The mapping row and the session it points at must both exist.
	row, err := client.AgentSession.Query().
		Where(agentsession.ExternalID("ses_7f3a")).
		WithSession().
		Only(context.Background())
	require.NoError(t, err)
	assert.Equal(t, "opencode", row.Source)
	require.NotNil(t, row.Edges.Session)
	assert.Equal(t, id, row.Edges.Session.ID)
}

// The property the whole table exists for: the same external id must always
// resolve to the same int64, or session memory fragments across turns.
func TestResolveIsIdempotent(t *testing.T) {
	client := newClient(t, "as_idem")
	svc := service.NewAgentSessionService(client)
	ctx := context.Background()

	first, created1, err := svc.Resolve(ctx, "ses_stable", "opencode")
	require.NoError(t, err)
	assert.True(t, created1)

	second, created2, err := svc.Resolve(ctx, "ses_stable", "opencode")
	require.NoError(t, err)
	assert.False(t, created2, "second sight must not report created")
	assert.Equal(t, first, second, "the same external id must map to the same session")

	// Exactly one mapping row, and one session -- not a new pair each call.
	count, err := client.AgentSession.Query().Count(ctx)
	require.NoError(t, err)
	assert.Equal(t, 1, count)
	sessions, err := client.Session.Query().Count(ctx)
	require.NoError(t, err)
	assert.Equal(t, 1, sessions)
}

func TestResolveDistinctIDsGetDistinctSessions(t *testing.T) {
	client := newClient(t, "as_distinct")
	svc := service.NewAgentSessionService(client)
	ctx := context.Background()

	a, _, err := svc.Resolve(ctx, "ses_a", "opencode")
	require.NoError(t, err)
	b, _, err := svc.Resolve(ctx, "ses_b", "opencode")
	require.NoError(t, err)
	assert.NotEqual(t, a, b)
}

func TestResolveBumpsLastSeen(t *testing.T) {
	client := newClient(t, "as_lastseen")
	svc := service.NewAgentSessionService(client)
	ctx := context.Background()

	_, _, err := svc.Resolve(ctx, "ses_bump", "opencode")
	require.NoError(t, err)
	before, err := client.AgentSession.Query().
		Where(agentsession.ExternalID("ses_bump")).Only(ctx)
	require.NoError(t, err)

	_, _, err = svc.Resolve(ctx, "ses_bump", "opencode")
	require.NoError(t, err)
	after, err := client.AgentSession.Query().
		Where(agentsession.ExternalID("ses_bump")).Only(ctx)
	require.NoError(t, err)

	assert.False(t, after.LastSeenAt.Before(before.LastSeenAt),
		"last_seen_at must not move backwards")
}

// True N-way concurrency is deliberately NOT unit-tested here. sqlite in
// shared-cache mode returns SQLITE_LOCKED ("database table is locked") under
// concurrent writers, which is a driver artifact rather than the behaviour
// Postgres exhibits -- there the unique constraint fires and the loser re-reads.
// Testing it against sqlite produces a flaky test that proves nothing about
// production. The two branches that matter are exercised deterministically
// below instead.

// A session already carrying the derived name, with its mapping in place, is
// the post-race state a losing writer observes. It must be reused, not
// duplicated.
func TestResolveReusesExistingSessionAndMapping(t *testing.T) {
	client := newClient(t, "as_postrace")
	svc := service.NewAgentSessionService(client)
	ctx := context.Background()

	// Simulate the winner having completed both steps.
	winner, err := client.Session.Create().
		SetName("agent:ses_post").
		SetLastActiveAt(time.Now()).
		Save(ctx)
	require.NoError(t, err)
	require.NoError(t, client.AgentSession.Create().
		SetExternalID("ses_post").
		SetSource("opencode").
		SetSessionID(winner.ID).
		SetLastSeenAt(time.Now()).
		Exec(ctx))

	id, created, err := svc.Resolve(ctx, "ses_post", "opencode")
	require.NoError(t, err)
	assert.False(t, created)
	assert.Equal(t, winner.ID, id)

	sessions, err := client.Session.Query().Count(ctx)
	require.NoError(t, err)
	assert.Equal(t, 1, sessions, "must not create a second session")
}

// A session whose mapping was deleted leaves the derived name taken but
// unmapped. Creating a new session is impossible (unique name), so it must be
// adopted rather than failing the turn.
func TestResolveAdoptsOrphanedSession(t *testing.T) {
	client := newClient(t, "as_orphan")
	svc := service.NewAgentSessionService(client)
	ctx := context.Background()

	orphan, err := client.Session.Create().
		SetName("agent:ses_orphan").
		SetLastActiveAt(time.Now()).
		Save(ctx)
	require.NoError(t, err)

	id, created, err := svc.Resolve(ctx, "ses_orphan", "opencode")
	require.NoError(t, err, "an orphaned session name must not fail the turn")
	assert.True(t, created, "the mapping is new even though the session is not")
	assert.Equal(t, orphan.ID, id, "must adopt the existing session")

	sessions, err := client.Session.Query().Count(ctx)
	require.NoError(t, err)
	assert.Equal(t, 1, sessions, "must not create a duplicate session")

	// And it is now a normal mapping: a second call is a plain lookup.
	again, created2, err := svc.Resolve(ctx, "ses_orphan", "opencode")
	require.NoError(t, err)
	assert.False(t, created2)
	assert.Equal(t, orphan.ID, again)
}

// The foreign key makes "mapping outlived its session" unreachable: deleting a
// referenced session is rejected outright. Asserting that is more useful than
// asserting how Resolve would cope, because it establishes the invariant the
// defensive nil-session branch in lookup() exists only as belt-and-braces for.
//
// schema.sql declares `session_id BIGINT NOT NULL REFERENCES sessions(session_id)`
// with no ON DELETE clause, so Postgres behaves the same way as sqlite with
// _fk=1 here. If that FK is ever relaxed to ON DELETE CASCADE or SET NULL, this
// test fails and the remap path needs real coverage.
func TestForeignKeyBlocksOrphaningAMapping(t *testing.T) {
	client := newClient(t, "as_fk")
	svc := service.NewAgentSessionService(client)
	ctx := context.Background()

	id, _, err := svc.Resolve(ctx, "ses_fk", "opencode")
	require.NoError(t, err)

	err = client.Session.DeleteOneID(id).Exec(ctx)
	require.Error(t, err, "deleting a mapped session must be refused by the FK")
	assert.Contains(t, err.Error(), "FOREIGN KEY")

	// The mapping still resolves, unchanged.
	again, created, err := svc.Resolve(ctx, "ses_fk", "opencode")
	require.NoError(t, err)
	assert.False(t, created)
	assert.Equal(t, id, again)
}

func TestResolveDefaultsSourceViaHandler(t *testing.T) {
	client := newClient(t, "as_srcdefault")
	svc := service.NewAgentSessionService(client)

	rec := postResolve(t, svc, `{"external_id":"ses_nosource"}`)
	require.Equal(t, http.StatusCreated, rec.Code)

	row, err := client.AgentSession.Query().
		Where(agentsession.ExternalID("ses_nosource")).Only(context.Background())
	require.NoError(t, err)
	assert.Equal(t, "opencode", row.Source, "source should default rather than be empty")
}

func TestResolveEmptyExternalIDIsNoop(t *testing.T) {
	client := newClient(t, "as_empty")
	svc := service.NewAgentSessionService(client)

	// Direct call: an empty id is not an error, it just maps to nothing.
	id, created, err := svc.Resolve(context.Background(), "   ", "opencode")
	assert.NoError(t, err)
	assert.Zero(t, id)
	assert.False(t, created)
}

// ── HTTP surface ─────────────────────────────────────────────────────────────

func postResolve(t *testing.T, svc *service.AgentSessionService, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/sessions/external", bytes.NewBufferString(body))
	rec := httptest.NewRecorder()
	svc.HandleResolve(rec, req)
	return rec
}

func TestHandlerReturns201ThenPlain200(t *testing.T) {
	client := newClient(t, "as_status")
	svc := service.NewAgentSessionService(client)

	first := postResolve(t, svc, `{"external_id":"ses_http","source":"opencode"}`)
	assert.Equal(t, http.StatusCreated, first.Code, "first sight is a creation")

	var body1 struct {
		SessionID int64 `json:"session_id"`
		Created   bool  `json:"created"`
	}
	require.NoError(t, json.Unmarshal(first.Body.Bytes(), &body1))
	assert.True(t, body1.Created)
	assert.NotZero(t, body1.SessionID)

	second := postResolve(t, svc, `{"external_id":"ses_http","source":"opencode"}`)
	assert.Equal(t, http.StatusOK, second.Code, "a repeat lookup is not a creation")

	var body2 struct {
		SessionID int64 `json:"session_id"`
		Created   bool  `json:"created"`
	}
	require.NoError(t, json.Unmarshal(second.Body.Bytes(), &body2))
	assert.False(t, body2.Created)
	assert.Equal(t, body1.SessionID, body2.SessionID)
}

func TestHandlerRejectsMissingExternalID(t *testing.T) {
	svc := service.NewAgentSessionService(newClient(t, "as_missing"))
	for _, body := range []string{`{}`, `{"external_id":""}`, `{"external_id":"   "}`} {
		rec := postResolve(t, svc, body)
		assert.Equal(t, http.StatusBadRequest, rec.Code, "body %s", body)
	}
}

func TestHandlerRejectsBadJSON(t *testing.T) {
	svc := service.NewAgentSessionService(newClient(t, "as_badjson"))
	assert.Equal(t, http.StatusBadRequest, postResolve(t, svc, `{not json`).Code)
}

func TestHandlerRejectsGET(t *testing.T) {
	svc := service.NewAgentSessionService(newClient(t, "as_get"))
	req := httptest.NewRequest(http.MethodGet, "/sessions/external", nil)
	rec := httptest.NewRecorder()
	svc.HandleResolve(rec, req)
	assert.Equal(t, http.StatusMethodNotAllowed, rec.Code)
}
