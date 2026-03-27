package telemetry

import (
	"context"
	"fmt"
	"log"
	"os"

	"app-builds/common/tlsutil"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
)

func InitTracer(serviceName string) (func(context.Context) error, error) {
	ctx := context.Background()

	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "otel-collector.monitoring.svc.cluster.local:4318"
	}

	useTLS := os.Getenv("OTEL_USE_TLS") == "true"

	var traceOpts []otlptracehttp.Option
	traceOpts = append(traceOpts, otlptracehttp.WithEndpoint(endpoint))

	var metricOpts []otlpmetrichttp.Option
	metricOpts = append(metricOpts, otlpmetrichttp.WithEndpoint(endpoint))

	if !useTLS {
		traceOpts = append(traceOpts, otlptracehttp.WithInsecure())
		metricOpts = append(metricOpts, otlpmetrichttp.WithInsecure())
	} else {
		tlsConfig, err := tlsutil.NewTLSConfig()
		if err != nil {
			return nil, fmt.Errorf("OTEL TLS initialization failed for %s: %w", serviceName, err)
		}
		log.Printf("OTEL: TLS enabled for %s using CA from SSL_CERT_FILE", serviceName)
		traceOpts = append(traceOpts, otlptracehttp.WithTLSClientConfig(tlsConfig))
		metricOpts = append(metricOpts, otlpmetrichttp.WithTLSClientConfig(tlsConfig))
	}

	traceExp, err := otlptracehttp.New(ctx, traceOpts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create trace exporter: %w", err)
	}

	metricExp, err := otlpmetrichttp.New(ctx, metricOpts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create metric exporter: %w", err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceNameKey.String(serviceName),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExp),
		sdktrace.WithResource(res),
	)
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExp)),
	)

	otel.SetTracerProvider(tp)
	otel.SetMeterProvider(mp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))

	return func(c context.Context) error {
		var retErr error
		if err := tp.Shutdown(c); err != nil {
			retErr = fmt.Errorf("trace shutdown: %w", err)
		}
		if err := mp.Shutdown(c); err != nil {
			if retErr != nil {
				retErr = fmt.Errorf("%v; metric shutdown: %w", retErr, err)
			} else {
				retErr = fmt.Errorf("metric shutdown: %w", err)
			}
		}
		return retErr
	}, nil
}

// Meter returns a global Meter for convenience
func Meter(name string) metric.Meter {
	return otel.GetMeterProvider().Meter(name)
}
