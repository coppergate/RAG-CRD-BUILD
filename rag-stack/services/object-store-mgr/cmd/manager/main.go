package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"

	"app-builds/common/telemetry"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
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

	mux := http.NewServeMux()

	mux.HandleFunc("/api/s3/buckets", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		resp, err := client.ListBuckets(r.Context(), &s3.ListBucketsInput{})
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(resp.Buckets)
	})

	mux.HandleFunc("/api/s3/buckets/", func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/s3/buckets/"), "/")
		if len(parts) < 1 {
			http.Error(w, "Bucket name required", http.StatusBadRequest)
			return
		}
		bucketName := parts[0]

		if len(parts) == 1 { // List objects
			resp, err := client.ListObjectsV2(r.Context(), &s3.ListObjectsV2Input{
				Bucket: aws.String(bucketName),
			})
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			json.NewEncoder(w).Encode(resp.Contents)
			return
		}

		// Object operations
		objectKey := strings.Join(parts[1:], "/")
		switch r.Method {
		case http.MethodGet:
			resp, err := client.GetObject(r.Context(), &s3.GetObjectInput{
				Bucket: aws.String(bucketName),
				Key:    aws.String(objectKey),
			})
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			defer resp.Body.Close()
			io.Copy(w, resp.Body)
		case http.MethodDelete:
			_, err := client.DeleteObject(r.Context(), &s3.DeleteObjectInput{
				Bucket: aws.String(bucketName),
				Key:    aws.String(objectKey),
			})
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.WriteHeader(http.StatusNoContent)
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "OK")
	})

	otelHandler := otelhttp.NewHandler(mux, "object-store-mgr")

	fmt.Println("Server starting on :8080")
	if err := http.ListenAndServe(":8080", otelHandler); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

