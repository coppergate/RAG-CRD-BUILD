package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"app-builds/common/telemetry"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

func main() {
	shutdown, err := telemetry.InitTracer("object-store-mgr")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	endpoint := os.Getenv("S3_ENDPOINT")
	if endpoint != "" && !strings.HasPrefix(endpoint, "http") {
		endpoint = "http://" + endpoint
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
		log.Fatalf("unable to load SDK config, %v", err)
	}

	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.UsePathStyle = true
	})

	resp, err := client.ListObjectsV2(context.TODO(), &s3.ListObjectsV2Input{
		Bucket: aws.String(bucket),
	})
	if err != nil {
		log.Printf("Error: unable to list objects in bucket %s: %v", bucket, err)
		// Don't fatal here, maybe it's just an empty bucket or temporary issue
	} else {
		fmt.Printf("Current objects in bucket %s:\n", bucket)
		for _, item := range resp.Contents {
			fmt.Printf("- %s (Size: %d)\n", *item.Key, *item.Size)
		}
	}

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "OK")
	})

	fmt.Println("Health server starting on :8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatalf("Health server failed: %v", err)
	}
}

