package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"

	"app-builds/common/health"
	"app-builds/common/logging"
	"app-builds/common/telemetry"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
	healthSrv := health.NewServer()

	shutdown, err := telemetry.InitTracer("object-store-mgr")
	if err != nil {
		logging.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	endpoint := os.Getenv("S3_ENDPOINT")
	if endpoint != "" && !strings.HasPrefix(endpoint, "http") {
		endpoint = "https://" + endpoint
	}
	bucket := os.Getenv("BUCKET_NAME")

	fmt.Printf("S3 Manager (Go) starting...\n")
	fmt.Printf("Endpoint: %s, Bucket: %s\n", endpoint, bucket)

	customResolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
		return aws.Endpoint{
			URL:               endpoint,
			HostnameImmutable: true,
		}, nil
	})

	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithEndpointResolverWithOptions(customResolver),
		config.WithRegion("us-east-1"),
	)
	if err != nil {
		logging.Fatalf("unable to load SDK config, %v", err)
	}

	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.UsePathStyle = true
	})

	maxUploadBytes := int64(100 << 20) // 100 MiB default
	if v := os.Getenv("MAX_UPLOAD_BYTES"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil && n > 0 {
			maxUploadBytes = n
		}
	}

	healthSrv.RegisterCheck("s3", func() error {
		_, err := client.ListBuckets(context.Background(), &s3.ListBucketsInput{})
		return err
	})

	mux := buildMux(client, healthSrv, maxUploadBytes)

	otelHandler := otelhttp.NewHandler(mux, "object-store-mgr")

	tlsCert := os.Getenv("TLS_CERT")
	tlsKey := os.Getenv("TLS_KEY")
	listenAddr := ":8080"

	server := &http.Server{
		Addr:    listenAddr,
		Handler: otelHandler,
	}

	if tlsCert != "" && tlsKey != "" {
		fmt.Printf("Server starting with TLS on %s\n", listenAddr)
		if err := server.ListenAndServeTLS(tlsCert, tlsKey); err != nil {
			logging.Fatalf("Server failed: %v", err)
		}
	} else {
		fmt.Printf("Server starting on %s\n", listenAddr)
		if err := server.ListenAndServe(); err != nil {
			logging.Fatalf("Server failed: %v", err)
		}
	}
}

