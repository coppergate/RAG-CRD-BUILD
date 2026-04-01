package handlers

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"app-builds/rag-admin-api/internal/config"
	"app-builds/common/tlsutil"
	"time"
)

type AdminHandler struct {
	Cfg *config.Config
}

func (h *AdminHandler) ProxyTo(targetURL string, prefixToStrip string) http.HandlerFunc {
	target, _ := url.Parse(targetURL)
	proxy := httputil.NewSingleHostReverseProxy(target)
	
	// Customize the director to strip prefix if needed
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		if prefixToStrip != "" {
			req.URL.Path = strings.TrimPrefix(req.URL.Path, prefixToStrip)
			if !strings.HasPrefix(req.URL.Path, "/") {
				req.URL.Path = "/" + req.URL.Path
			}
		}
	}

	return func(w http.ResponseWriter, r *http.Request) {
		proxy.ServeHTTP(w, r)
	}
}

func (h *AdminHandler) HandleHealthAggregation(w http.ResponseWriter, r *http.Request) {
	services := map[string]string{
		"db-adapter":        h.Cfg.DBAdapterURL,
		"object-store-mgr":  h.Cfg.S3ManagerURL,
		"qdrant-adapter":    h.Cfg.QdrantAdapterURL,
		"llm-gateway":       h.Cfg.LLMGatewayURL,
		"memory-controller": h.Cfg.MemoryControllerURL,
	}

	client, err := tlsutil.NewHTTPClient(true, 5*time.Second)
	if err != nil {
		// Fallback to default if TLS fails to load (might be in dev)
		client = &http.Client{Timeout: 5 * time.Second}
	}

	results := make(map[string]interface{})
	for name, baseURL := range services {
		var resp *http.Response
		var lastErr error

		for _, endpoint := range []string{"/readyz", "/healthz", "/health"} {
			healthURL := baseURL + endpoint
			resp, lastErr = client.Get(healthURL)
			if lastErr == nil {
				if resp.StatusCode == http.StatusNotFound {
					resp.Body.Close()
					resp = nil
					continue
				}
				break
			}
			resp = nil
		}

		if lastErr != nil {
			results[name] = map[string]string{"status": "DOWN", "error": lastErr.Error()}
			continue
		}
		if resp == nil {
			results[name] = map[string]string{"status": "DOWN", "error": "No health endpoint found"}
			continue
		}
		defer resp.Body.Close()
		
		body, _ := io.ReadAll(resp.Body)
		var healthInfo interface{}
		if err := json.Unmarshal(body, &healthInfo); err == nil {
			results[name] = healthInfo
		} else {
			results[name] = string(body)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(results)
}
