package handlers

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httputil"
	"net/url"
	"app-builds/rag-admin-api/internal/config"
)

type AdminHandler struct {
	Cfg *config.Config
}

func (h *AdminHandler) ProxyTo(targetURL string) http.HandlerFunc {
	target, _ := url.Parse(targetURL)
	proxy := httputil.NewSingleHostReverseProxy(target)
	return func(w http.ResponseWriter, r *http.Request) {
		proxy.ServeHTTP(w, r)
	}
}

func (h *AdminHandler) HandleHealthAggregation(w http.ResponseWriter, r *http.Request) {
	services := map[string]string{
		"db-adapter":        h.Cfg.DBAdapterURL + "/health",
		"object-store-mgr":  h.Cfg.S3ManagerURL + "/health",
		"qdrant-adapter":    h.Cfg.QdrantAdapterURL + "/health",
		"llm-gateway":       h.Cfg.LLMGatewayURL + "/health",
		"memory-controller": h.Cfg.MemoryControllerURL + "/health",
	}

	results := make(map[string]interface{})
	for name, url := range services {
		resp, err := http.Get(url)
		if err != nil {
			results[name] = map[string]string{"status": "DOWN", "error": err.Error()}
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
