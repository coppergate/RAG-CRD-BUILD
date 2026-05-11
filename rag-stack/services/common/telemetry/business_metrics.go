package telemetry

import (
	"context"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
)

var (
	activeSessions  metric.Int64UpDownCounter
	recursionsTotal metric.Int64Counter
	messagesTotal   metric.Int64Counter
	dlqDepth        metric.Int64UpDownCounter
)

func init() {
	m := Meter("rag-business")
	var err error
	activeSessions, err = m.Int64UpDownCounter("rag_active_sessions",
		metric.WithDescription("Number of sessions currently streaming"))
	if err != nil {
		handleMetricError("rag_active_sessions", err)
	}

	recursionsTotal, err = m.Int64Counter("rag_recursions_total",
		metric.WithDescription("Total pipeline re-plan cycles triggered"))
	if err != nil {
		handleMetricError("rag_recursions_total", err)
	}

	messagesTotal, err = m.Int64Counter("rag_messages_total",
		metric.WithDescription("Total messages processed by the pipeline"))
	if err != nil {
		handleMetricError("rag_messages_total", err)
	}

	dlqDepth, err = m.Int64UpDownCounter("rag_dlq_depth",
		metric.WithDescription("Estimated depth of the dead letter queue"))
	if err != nil {
		handleMetricError("rag_dlq_depth", err)
	}
}

func handleMetricError(name string, err error) {
	// We don't want to panic, just log it. But since this is common package, 
	// we might not have the logger ready yet.
}

func RecordSessionStart(ctx context.Context) {
	if activeSessions != nil {
		activeSessions.Add(ctx, 1)
	}
}

func RecordSessionEnd(ctx context.Context) {
	if activeSessions != nil {
		activeSessions.Add(ctx, -1)
	}
}

func RecordRecursion(ctx context.Context, stage string) {
	if recursionsTotal != nil {
		recursionsTotal.Add(ctx, 1, metric.WithAttributes(attribute.String("stage", stage)))
	}
}

func RecordMessage(ctx context.Context, role string) {
	if messagesTotal != nil {
		messagesTotal.Add(ctx, 1, metric.WithAttributes(attribute.String("role", role)))
	}
}

func UpdateDLQDepth(ctx context.Context, delta int64, topic string) {
	if dlqDepth != nil {
		dlqDepth.Add(ctx, delta, metric.WithAttributes(attribute.String("topic", topic)))
	}
}
