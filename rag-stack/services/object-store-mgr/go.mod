module app-builds/rag-s3-mgr-go

go 1.25.0

require (
	app-builds/common v0.0.0
	github.com/aws/aws-sdk-go-v2 v1.30.1
	github.com/aws/aws-sdk-go-v2/config v1.27.0
	github.com/aws/aws-sdk-go-v2/service/s3 v1.58.0
	go.opentelemetry.io/otel v1.42.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.42.0
	go.opentelemetry.io/otel/sdk v1.42.0
)

replace app-builds/common => ../common
