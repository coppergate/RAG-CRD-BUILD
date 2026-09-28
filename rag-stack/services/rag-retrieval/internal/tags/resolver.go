// Package tags resolves between tag names and the int64 tag ids stored in
// Qdrant payloads.
//
// This indirection is unavoidable: rag-ingestion writes `tags` as an array of
// int64 ids (service.py:583), while every human-facing surface — opencode
// config, the §10.5 convention, the X-RAG-Tags header — speaks names. Names
// live in Postgres (tag.tag_name) behind db-adapter's /tags route.
package tags

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"app-builds/common/logging"
	"app-builds/common/tlsutil"
)

type Tag struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

type Resolver struct {
	baseURL string
	http    *http.Client
	ttl     time.Duration

	mu        sync.RWMutex
	byName    map[string]int64
	byID      map[int64]string
	all       []Tag
	refreshed time.Time
}

func NewResolver(baseURL string, ttl, timeout time.Duration) (*Resolver, error) {
	useTLS := strings.HasPrefix(baseURL, "https://")
	httpClient, err := tlsutil.NewHTTPClient(useTLS, timeout)
	if err != nil {
		return nil, fmt.Errorf("tags: http client: %w", err)
	}
	return &Resolver{
		baseURL: strings.TrimSuffix(baseURL, "/"),
		http:    httpClient,
		ttl:     ttl,
		byName:  make(map[string]int64),
		byID:    make(map[int64]string),
	}, nil
}

// All returns the cached tag list, refreshing it if stale.
func (r *Resolver) All(ctx context.Context) ([]Tag, error) {
	if err := r.ensureFresh(ctx); err != nil {
		return nil, err
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]Tag, len(r.all))
	copy(out, r.all)
	return out, nil
}

// Resolve maps a mixed list of tag names and numeric ids onto ids. Unknown
// names are reported separately rather than dropped silently: a typo'd tag
// would otherwise widen retrieval to the whole corpus with no signal.
func (r *Resolver) Resolve(ctx context.Context, wanted []string) (ids []int64, unknown []string) {
	if len(wanted) == 0 {
		return nil, nil
	}

	// A numeric-only list needs no lookup at all.
	allNumeric := true
	for _, w := range wanted {
		if _, err := strconv.ParseInt(strings.TrimSpace(w), 10, 64); err != nil {
			allNumeric = false
			break
		}
	}
	if !allNumeric {
		if err := r.ensureFresh(ctx); err != nil {
			// Degrade to numeric-only rather than failing the whole retrieval.
			logging.Printf("[retrieval/tags] refresh failed, names unresolvable: %v", err)
		}
	}

	r.mu.RLock()
	defer r.mu.RUnlock()
	seen := make(map[int64]struct{}, len(wanted))
	for _, w := range wanted {
		w = strings.TrimSpace(w)
		if w == "" {
			continue
		}
		if id, err := strconv.ParseInt(w, 10, 64); err == nil {
			if _, dup := seen[id]; !dup {
				seen[id] = struct{}{}
				ids = append(ids, id)
			}
			continue
		}
		if id, ok := r.byName[strings.ToLower(w)]; ok {
			if _, dup := seen[id]; !dup {
				seen[id] = struct{}{}
				ids = append(ids, id)
			}
			continue
		}
		unknown = append(unknown, w)
	}
	return ids, unknown
}

// Names maps ids back to names for the response payload, skipping unknowns.
func (r *Resolver) Names(ids []int64) []string {
	if len(ids) == 0 {
		return nil
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if n, ok := r.byID[id]; ok {
			out = append(out, n)
		}
	}
	return out
}

func (r *Resolver) ensureFresh(ctx context.Context) error {
	r.mu.RLock()
	fresh := !r.refreshed.IsZero() && time.Since(r.refreshed) < r.ttl
	r.mu.RUnlock()
	if fresh {
		return nil
	}
	return r.Refresh(ctx)
}

func (r *Resolver) Refresh(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, r.baseURL+"/tags", nil)
	if err != nil {
		return err
	}
	resp, err := r.http.Do(req)
	if err != nil {
		return fmt.Errorf("tags: fetch: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("tags: db-adapter /tags returned %d", resp.StatusCode)
	}

	var fetched []Tag
	if err := json.NewDecoder(resp.Body).Decode(&fetched); err != nil {
		return fmt.Errorf("tags: decode: %w", err)
	}

	byName := make(map[string]int64, len(fetched))
	byID := make(map[int64]string, len(fetched))
	for _, t := range fetched {
		byName[strings.ToLower(t.Name)] = t.ID
		byID[t.ID] = t.Name
	}

	r.mu.Lock()
	r.all, r.byName, r.byID, r.refreshed = fetched, byName, byID, time.Now()
	r.mu.Unlock()
	return nil
}
