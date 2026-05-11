package logging

import (
	"context"
	"fmt"
	"log/slog"
	"os"

	"go.opentelemetry.io/otel/trace"
)

// Logger wraps slog.Logger to add convenience methods.
type Logger struct {
	*slog.Logger
}

// WithTrace returns a logger that includes trace context from the given context.
func (l *Logger) WithTrace(ctx context.Context) *slog.Logger {
	span := trace.SpanFromContext(ctx)
	if !span.SpanContext().IsValid() {
		return l.Logger
	}

	return l.Logger.With(
		slog.String("trace_id", span.SpanContext().TraceID().String()),
		slog.String("span_id", span.SpanContext().SpanID().String()),
	)
}

var L *Logger

func init() {
	// Initialize a default JSON logger that writes to stdout.
	// We use a custom handler to inject tracing information.
	handler := &traceHandler{
		Handler: slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
			Level: slog.LevelInfo,
		}),
	}
	L = &Logger{Logger: slog.New(handler)}
	slog.SetDefault(L.Logger)
}

// traceHandler is a slog.Handler that extracts tracing information from the context.
type traceHandler struct {
	slog.Handler
}

func (h *traceHandler) Handle(ctx context.Context, r slog.Record) error {
	span := trace.SpanFromContext(ctx)
	if span.SpanContext().IsValid() {
		r.AddAttrs(
			slog.String("trace_id", span.SpanContext().TraceID().String()),
			slog.String("span_id", span.SpanContext().SpanID().String()),
		)
	}
	return h.Handler.Handle(ctx, r)
}

// With returns a new logger with the given attributes.
func With(args ...any) *slog.Logger {
	return L.Logger.With(args...)
}

// Info logs at LevelInfo.
func Info(msg string, args ...any) {
	L.Logger.Info(msg, args...)
}

// Error logs at LevelError.
func Error(msg string, args ...any) {
	L.Logger.Error(msg, args...)
}

// Warn logs at LevelWarn.
func Warn(msg string, args ...any) {
	L.Logger.Warn(msg, args...)
}

// Debug logs at LevelDebug.
func Debug(msg string, args ...any) {
	L.Logger.Debug(msg, args...)
}

// WithTrace returns a logger that includes trace context from the given context.
func WithTrace(ctx context.Context) *slog.Logger {
	return L.WithTrace(ctx)
}

// InfoContext logs at LevelInfo with context.
func InfoContext(ctx context.Context, msg string, args ...any) {
	L.Logger.InfoContext(ctx, msg, args...)
}

// ErrorContext logs at LevelError with context.
func ErrorContext(ctx context.Context, msg string, args ...any) {
	L.Logger.ErrorContext(ctx, msg, args...)
}

// Fatal logs at LevelError and exits.
func Fatal(msg string, args ...any) {
	L.Logger.Error(msg, args...)
	os.Exit(1)
}

// Fatalf logs at LevelError and exits (compatibility).
func Fatalf(format string, v ...any) {
	L.Logger.Error(fmt.Sprintf(format, v...))
	os.Exit(1)
}

// Printf logs at LevelInfo (compatibility).
func Printf(format string, v ...any) {
	L.Logger.Info(fmt.Sprintf(format, v...))
}

// Println logs at LevelInfo (compatibility).
func Println(v ...any) {
	L.Logger.Info(fmt.Sprint(v...))
}
