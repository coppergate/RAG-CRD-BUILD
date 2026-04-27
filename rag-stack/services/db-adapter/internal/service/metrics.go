package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/memoryevent"
	"app-builds/common/ent/modelexecutionmetric"
	"app-builds/common/ent/retrievallog"
	"github.com/google/uuid"
)

type MetricsService struct {
	client *ent.Client
}

func NewMetricsService(client *ent.Client) *MetricsService {
	return &MetricsService{client: client}
}

func (s *MetricsService) GetHealth(w http.ResponseWriter, r *http.Request, sessionIDStr string) {
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		http.Error(w, "Invalid session ID", http.StatusBadRequest)
		return
	}

	metrics, err := s.client.ModelExecutionMetric.Query().
		Where(modelexecutionmetric.SessionID(sessionID)).
		All(r.Context())
	if err != nil {
		http.Error(w, "Failed to query metrics: "+err.Error(), http.StatusInternalServerError)
		return
	}

	total := len(metrics)
	successful := total
	var sumLatency int64
	var sumTokens int
	for _, m := range metrics {
		sumLatency += m.TotalDurationUsec
		sumTokens += m.TotalTokens
	}

	successRate := 0.0
	avgLatency := 0.0
	if total > 0 {
		successRate = float64(successful) / float64(total)
		avgLatency = float64(sumLatency) / float64(total) / 1000.0
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"session_id":          sessionID,
		"total_requests":      total,
		"successful_requests": successful,
		"success_rate":        successRate,
		"avg_latency_ms":      avgLatency,
		"total_tokens":        sumTokens,
		"status":              s.calculateStatus(successRate),
	})
}

func (s *MetricsService) calculateStatus(successRate float64) string {
	if successRate >= 0.95 {
		return "HEALTHY"
	} else if successRate >= 0.75 {
		return "DEGRADED"
	}
	return "UNHEALTHY"
}

func (s *MetricsService) GetAudit(w http.ResponseWriter, r *http.Request, sessionIDStr string) {
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		http.Error(w, "Invalid session ID", http.StatusBadRequest)
		return
	}

	retrievals, err := s.client.RetrievalLog.Query().
		Where(retrievallog.SessionID(sessionID)).
		Order(ent.Desc(retrievallog.FieldCreatedAt)).
		Limit(50).
		All(r.Context())
	if err != nil {
		http.Error(w, "Failed to query retrieval logs: "+err.Error(), http.StatusInternalServerError)
		return
	}

	memEvents, err := s.client.MemoryEvent.Query().
		Where(memoryevent.SessionID(sessionID)).
		Order(ent.Desc(memoryevent.FieldCreatedAt)).
		Limit(50).
		All(r.Context())
	if err != nil {
		http.Error(w, "Failed to query memory events: "+err.Error(), http.StatusInternalServerError)
		return
	}

	var logs []map[string]interface{}
	for _, rl := range retrievals {
		logs = append(logs, map[string]interface{}{
			"type":       "RETRIEVAL",
			"detail":     rl.Query,
			"created_at": rl.CreatedAt,
		})
	}
	for _, me := range memEvents {
		logs = append(logs, map[string]interface{}{
			"type":       "MEMORY",
			"detail":     fmt.Sprintf("%s: %v", me.EventType, me.EventData),
			"created_at": me.CreatedAt,
		})
	}

	sort.Slice(logs, func(i, j int) bool {
		return logs[i]["created_at"].(time.Time).After(logs[j]["created_at"].(time.Time))
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(logs)
}

func (s *MetricsService) GetStats(w http.ResponseWriter, r *http.Request) {
	sessionCount, _ := s.client.Session.Query().Count(r.Context())
	promptCount, _ := s.client.Prompt.Query().Count(r.Context())
	responseCount, _ := s.client.Response.Query().Count(r.Context())
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]int{
		"sessions":  sessionCount,
		"prompts":   promptCount,
		"responses": responseCount,
	})
}

func (s *MetricsService) GetMetricsSummary(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	metrics, err := s.client.ModelExecutionMetric.Query().
		WithModel().
		WithNode().
		All(ctx)
	if err != nil {
		http.Error(w, "Failed to fetch metrics: "+err.Error(), http.StatusInternalServerError)
		return
	}

	type Key struct {
		Model string
		Node  string
	}
	type Stats struct {
		SumTPS float64
		SumLat float64
		Count  int
	}
	agg := make(map[Key]*Stats)

	for _, m := range metrics {
		modelName := "unknown"
		if m.Edges.Model != nil {
			modelName = m.Edges.Model.ModelName
		}
		nodeName := "unknown"
		if m.Edges.Node != nil {
			nodeName = m.Edges.Node.Hostname
		}

		key := Key{Model: modelName, Node: nodeName}
		if _, ok := agg[key]; !ok {
			agg[key] = &Stats{}
		}
		agg[key].SumTPS += float64(m.TokensPerSecond)
		agg[key].SumLat += float64(m.TotalDurationUsec) / 1000.0
		agg[key].Count++
	}

	var results []map[string]interface{}
	for k, st := range agg {
		results = append(results, map[string]interface{}{
			"model_name":         k.Model,
			"node":               k.Node,
			"avg_tokens_per_sec": st.SumTPS / float64(st.Count),
			"avg_latency_ms":     st.SumLat / float64(st.Count),
			"total_executions":   st.Count,
		})
	}

	sort.Slice(results, func(i, j int) bool {
		if results[i]["model_name"].(string) != results[j]["model_name"].(string) {
			return results[i]["model_name"].(string) < results[j]["model_name"].(string)
		}
		return results[i]["node"].(string) < results[j]["node"].(string)
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(results)
}
