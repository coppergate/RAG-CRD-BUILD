package pipeline

import (
	"encoding/json"
	"fmt"
	"strings"

	"app-builds/common/contracts"
)

func buildPlannerMetrics(req *contracts.InternalRequest, plan *contracts.PlannerTaskPlan, metrics interface{}, historyPack *contracts.MemoryPack, detectedActionType, finalActionType string) map[string]interface{} {
	metricMap := make(map[string]interface{})
	metricMap["prompt_char_count"] = len(req.Prompt)
	metricMap["detected_action_type"] = detectedActionType
	metricMap["final_action_type"] = finalActionType
	metricMap["context_budget"] = plan.ContextBudget
	metricMap["step_count"] = len(plan.Steps)
	metricMap["sub_query_count"] = len(plan.SearchQueries)
	metricMap["history_item_count"] = 0
	metricMap["behavioral_rule_count"] = 0
	metricMap["task_context_count"] = 0
	metricMap["episodic_history_count"] = 0

	if historyPack != nil {
		metricMap["history_item_count"] = len(historyPack.Items)
		for _, item := range historyPack.Items {
			if item == nil {
				continue
			}
			meta := map[string]interface{}{}
			if item.Metadata != nil {
				meta = contracts.FromStruct(item.Metadata)
			}
			bucket, _ := meta["context_bucket"].(string)
			bucket = normalizeContextBucket(bucket)
			if bucket == "" {
				bucket = normalizeContextBucket(item.MemoryType)
			}
			switch bucket {
			case "behavioral_rules", "action_scoped_behavior", "global_fallback_policy":
				metricMap["behavioral_rule_count"] = metricMap["behavioral_rule_count"].(int) + 1
			case "task_local_retrieval":
				metricMap["task_context_count"] = metricMap["task_context_count"].(int) + 1
			case "episodic_history":
				metricMap["episodic_history_count"] = metricMap["episodic_history_count"].(int) + 1
			}
		}
	}

	if normalized := normalizeAny(metrics); normalized != nil {
		metricMap["planner_model_metrics"] = normalized
	}
	return metricMap
}

func normalizeAny(v interface{}) interface{} {
	if v == nil {
		return nil
	}
	raw, err := json.Marshal(v)
	if err != nil {
		return fmt.Sprintf("%v", v)
	}
	var out interface{}
	if err := json.Unmarshal(raw, &out); err != nil {
		return fmt.Sprintf("%v", v)
	}
	return out
}

func formatMetricValue(v interface{}) string {
	switch t := v.(type) {
	case nil:
		return ""
	case string:
		return t
	case fmt.Stringer:
		return t.String()
	default:
		return fmt.Sprintf("%v", v)
	}
}

func mergeNestedMetricMap(existing interface{}, update map[string]interface{}) map[string]interface{} {
	merged := map[string]interface{}{}
	if existing != nil {
		if existingMap, ok := normalizeAny(existing).(map[string]interface{}); ok {
			for k, v := range existingMap {
				merged[k] = v
			}
		}
	}
	for k, v := range update {
		if existingVal, ok := merged[k].(map[string]interface{}); ok {
			if updateVal, ok := v.(map[string]interface{}); ok {
				merged[k] = mergeNestedMetricMap(existingVal, updateVal)
				continue
			}
		}
		merged[k] = v
	}
	return merged
}

func normalizeContextBucket(bucket string) string {
	switch strings.ToLower(strings.TrimSpace(bucket)) {
	case "behavioral_rule":
		return "behavioral_rules"
	case "chat_history":
		return "episodic_history"
	default:
		return strings.TrimSpace(bucket)
	}
}

func contextBucketSummary(items []*contracts.MemoryWriteItem) []string {
	seen := make(map[string]bool)
	order := make([]string, 0)
	for _, item := range items {
		if item == nil {
			continue
		}
		bucket := ""
		if item.Metadata != nil {
			meta := contracts.FromStruct(item.Metadata)
			bucket, _ = meta["context_bucket"].(string)
		}
		if bucket == "" {
			bucket = normalizeContextBucket(item.MemoryType)
		} else {
			bucket = normalizeContextBucket(bucket)
		}
		if bucket == "" {
			continue
		}
		if !seen[bucket] {
			seen[bucket] = true
			order = append(order, bucket)
		}
	}
	return order
}

func (h *Handler) mapMetrics(raw interface{}, modelID string) *contracts.ExecutionMetrics {
	if raw == nil {
		return nil
	}

	var m *contracts.ExecutionMetrics
	if or, ok := raw.(interface {
		GetMetrics() *contracts.ExecutionMetrics
	}); ok {
		m = or.GetMetrics()
	}

	if m != nil && m.ModelFamily == "" {
		if strings.Contains(strings.ToLower(modelID), "llama") {
			m.ModelFamily = "llama"
		} else if strings.Contains(strings.ToLower(modelID), "granite") {
			m.ModelFamily = "granite"
		}
	}

	return m
}
