// Package session maps opencode's opaque session ids onto the int64 session
// identity the RAG DB uses.
//
// The mapping itself lives in db-adapter (POST /sessions/external) so that this
// service and any later rag-code-gateway resolve identically and share one race
// resolution. See infrastructure/timescaledb/iteration-12-agent-session.sql.
package session

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"app-builds/common/tlsutil"
)

type Mapper struct {
	baseURL string
	http    *http.Client

	mu    sync.RWMutex
	cache map[string]int64
}

func NewMapper(baseURL string, timeout time.Duration) (*Mapper, error) {
	useTLS := strings.HasPrefix(baseURL, "https://")
	httpClient, err := tlsutil.NewHTTPClient(useTLS, timeout)
	if err != nil {
		return nil, fmt.Errorf("session: http client: %w", err)
	}
	return &Mapper{
		baseURL: strings.TrimSuffix(baseURL, "/"),
		http:    httpClient,
		cache:   make(map[string]int64),
	}, nil
}

// Resolve returns the int64 session id for an external id, or 0 when it cannot
// be determined. A zero return is not an error the caller should surface:
// retrieval works fine without a session, so the response simply omits it.
func (m *Mapper) Resolve(ctx context.Context, externalID, source string) (int64, error) {
	externalID = strings.TrimSpace(externalID)
	if externalID == "" {
		return 0, nil
	}

	m.mu.RLock()
	cached, ok := m.cache[externalID]
	m.mu.RUnlock()
	if ok {
		return cached, nil
	}

	if source == "" {
		source = "opencode"
	}
	body, err := json.Marshal(map[string]string{"external_id": externalID, "source": source})
	if err != nil {
		return 0, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, m.baseURL+"/sessions/external", bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := m.http.Do(req)
	if err != nil {
		return 0, fmt.Errorf("session: resolve %q: %w", externalID, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return 0, fmt.Errorf("session: db-adapter /sessions/external returned %d", resp.StatusCode)
	}

	var out struct {
		SessionID int64 `json:"session_id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return 0, fmt.Errorf("session: decode: %w", err)
	}
	if out.SessionID == 0 {
		return 0, fmt.Errorf("session: db-adapter returned session_id 0 for %q", externalID)
	}

	m.mu.Lock()
	m.cache[externalID] = out.SessionID
	m.mu.Unlock()
	return out.SessionID, nil
}
