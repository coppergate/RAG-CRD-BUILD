package tags

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func newResolver(t *testing.T, h http.HandlerFunc, ttl time.Duration) (*Resolver, *httptest.Server) {
	t.Helper()
	srv := httptest.NewServer(h)
	r, err := NewResolver(srv.URL, ttl, 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	return r, srv
}

func twoTags(w http.ResponseWriter, r *http.Request) {
	_, _ = w.Write([]byte(`[{"id":1,"name":"stack-docs"},{"id":2,"name":"stack-go"}]`))
}

func TestResolveNamesToIDs(t *testing.T) {
	r, srv := newResolver(t, twoTags, time.Minute)
	defer srv.Close()

	ids, unknown := r.Resolve(context.Background(), []string{"stack-go"})
	if len(ids) != 1 || ids[0] != 2 {
		t.Errorf("expected [2], got %v", ids)
	}
	if len(unknown) != 0 {
		t.Errorf("unexpected unknown: %v", unknown)
	}
}

func TestResolveIsCaseInsensitive(t *testing.T) {
	r, srv := newResolver(t, twoTags, time.Minute)
	defer srv.Close()

	ids, _ := r.Resolve(context.Background(), []string{"STACK-Docs", "  stack-go  "})
	if len(ids) != 2 {
		t.Errorf("expected both resolved, got %v", ids)
	}
}

// A typo'd tag must be reported, not dropped: silently dropping it widens
// retrieval to the whole corpus with no signal to the caller.
func TestResolveReportsUnknownNames(t *testing.T) {
	r, srv := newResolver(t, twoTags, time.Minute)
	defer srv.Close()

	ids, unknown := r.Resolve(context.Background(), []string{"stack-go", "stak-go"})
	if len(ids) != 1 {
		t.Errorf("expected the good tag resolved, got %v", ids)
	}
	if len(unknown) != 1 || unknown[0] != "stak-go" {
		t.Errorf("expected the typo reported, got %v", unknown)
	}
}

// Numeric input is already an id; it must not require a lookup, so retrieval
// still works when db-adapter is down.
func TestNumericIDsNeedNoLookup(t *testing.T) {
	var calls int32
	r, srv := newResolver(t, func(w http.ResponseWriter, req *http.Request) {
		atomic.AddInt32(&calls, 1)
		twoTags(w, req)
	}, time.Minute)
	defer srv.Close()

	ids, unknown := r.Resolve(context.Background(), []string{"7", "9"})
	if len(ids) != 2 || ids[0] != 7 || ids[1] != 9 {
		t.Errorf("expected [7 9], got %v", ids)
	}
	if len(unknown) != 0 {
		t.Errorf("unexpected unknown: %v", unknown)
	}
	if atomic.LoadInt32(&calls) != 0 {
		t.Error("numeric-only input must not hit db-adapter")
	}
}

func TestResolveDeduplicates(t *testing.T) {
	r, srv := newResolver(t, twoTags, time.Minute)
	defer srv.Close()

	// Same tag by name and by id.
	ids, _ := r.Resolve(context.Background(), []string{"stack-go", "2", "stack-go"})
	if len(ids) != 1 {
		t.Errorf("expected deduplication, got %v", ids)
	}
}

// db-adapter being down must degrade to "names unresolvable", not fail.
func TestResolveDegradesWhenUpstreamDown(t *testing.T) {
	r, err := NewResolver("http://127.0.0.1:1", time.Minute, 300*time.Millisecond)
	if err != nil {
		t.Fatal(err)
	}
	ids, unknown := r.Resolve(context.Background(), []string{"stack-go", "5"})
	// The numeric one still works; the name cannot be resolved and is reported.
	if len(ids) != 1 || ids[0] != 5 {
		t.Errorf("expected the numeric id to survive, got %v", ids)
	}
	if len(unknown) != 1 {
		t.Errorf("expected the name reported unknown, got %v", unknown)
	}
}

func TestEmptyInputIsNoop(t *testing.T) {
	r, srv := newResolver(t, twoTags, time.Minute)
	defer srv.Close()

	ids, unknown := r.Resolve(context.Background(), nil)
	if ids != nil || unknown != nil {
		t.Errorf("expected nothing, got %v / %v", ids, unknown)
	}
}

func TestNamesMapsBack(t *testing.T) {
	r, srv := newResolver(t, twoTags, time.Minute)
	defer srv.Close()
	if _, err := r.All(context.Background()); err != nil {
		t.Fatal(err)
	}

	names := r.Names([]int64{2, 1})
	if len(names) != 2 || names[0] != "stack-go" {
		t.Errorf("expected reverse mapping in order, got %v", names)
	}
	// An id with no known name is skipped rather than rendered as a number.
	if got := r.Names([]int64{999}); len(got) != 0 {
		t.Errorf("expected unknown ids skipped, got %v", got)
	}
}

func TestCacheIsUsedWithinTTL(t *testing.T) {
	var calls int32
	r, srv := newResolver(t, func(w http.ResponseWriter, req *http.Request) {
		atomic.AddInt32(&calls, 1)
		twoTags(w, req)
	}, time.Minute)
	defer srv.Close()

	for i := 0; i < 5; i++ {
		if _, err := r.All(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Errorf("expected 1 upstream call within TTL, got %d", got)
	}
}

func TestCacheExpires(t *testing.T) {
	var calls int32
	r, srv := newResolver(t, func(w http.ResponseWriter, req *http.Request) {
		atomic.AddInt32(&calls, 1)
		twoTags(w, req)
	}, 10*time.Millisecond)
	defer srv.Close()

	if _, err := r.All(context.Background()); err != nil {
		t.Fatal(err)
	}
	time.Sleep(30 * time.Millisecond)
	if _, err := r.All(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := atomic.LoadInt32(&calls); got < 2 {
		t.Errorf("expected a refresh after the TTL, got %d calls", got)
	}
}

func TestAllReturnsErrorWhenUpstreamDown(t *testing.T) {
	// /v1/rag/tags is a diagnostic endpoint, so here an error IS the right
	// answer -- unlike Resolve, which must degrade.
	r, err := NewResolver("http://127.0.0.1:1", time.Minute, 300*time.Millisecond)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := r.All(context.Background()); err == nil {
		t.Error("expected an error from All when db-adapter is unreachable")
	}
}

func TestAllCopiesSoCallersCannotMutateCache(t *testing.T) {
	r, srv := newResolver(t, twoTags, time.Minute)
	defer srv.Close()

	first, err := r.All(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	first[0].Name = "clobbered"

	second, err := r.All(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if second[0].Name == "clobbered" {
		t.Error("All must return a copy, not the cached slice")
	}
}
