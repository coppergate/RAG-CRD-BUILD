package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"app-builds/common/health"
	"app-builds/common/logging"

	"github.com/aws/aws-sdk-go-v2/aws"
	s3svc "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// S3Client covers the subset of the AWS S3 API used by this service.
type S3Client interface {
	ListBuckets(ctx context.Context, params *s3svc.ListBucketsInput, optFns ...func(*s3svc.Options)) (*s3svc.ListBucketsOutput, error)
	ListObjectsV2(ctx context.Context, params *s3svc.ListObjectsV2Input, optFns ...func(*s3svc.Options)) (*s3svc.ListObjectsV2Output, error)
	GetObject(ctx context.Context, params *s3svc.GetObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.GetObjectOutput, error)
	PutObject(ctx context.Context, params *s3svc.PutObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.PutObjectOutput, error)
	DeleteObject(ctx context.Context, params *s3svc.DeleteObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.DeleteObjectOutput, error)
}

// buildMux constructs the HTTP mux for the service. Accepts an S3Client so
// tests can inject a mock without starting the full binary.
func buildMux(client S3Client, healthSrv *health.Server, maxUploadBytes int64) *http.ServeMux {
	mux := http.NewServeMux()

	healthSrv.RegisterRoutes(mux)

	mux.HandleFunc("/buckets", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		resp, err := client.ListBuckets(r.Context(), &s3svc.ListBucketsInput{})
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		buckets := resp.Buckets
		if buckets == nil {
			buckets = []types.Bucket{}
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(buckets)
	})

	mux.HandleFunc("/buckets/", func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/buckets/"), "/")
		if len(parts) < 1 || parts[0] == "" {
			http.Error(w, "Bucket name required", http.StatusBadRequest)
			return
		}
		bucketName := parts[0]

		if len(parts) == 1 { // List objects in bucket
			prefix := r.URL.Query().Get("prefix")
			logging.Printf("[S3] ListObjectsV2: bucket=%s, prefix=%s", bucketName, prefix)
			resp, err := client.ListObjectsV2(r.Context(), &s3svc.ListObjectsV2Input{
				Bucket: aws.String(bucketName),
				Prefix: aws.String(prefix),
			})
			if err != nil {
				logging.Printf("[S3] Error listing objects: %v", err)
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			contents := resp.Contents
			if contents == nil {
				contents = []types.Object{}
			}
			logging.Printf("[S3] Returning %d objects", len(contents))
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(contents)
			return
		}

		// Object operations: /buckets/<bucket>/<key...>
		objectKey := strings.Join(parts[1:], "/")
		switch r.Method {
		case http.MethodGet:
			resp, err := client.GetObject(r.Context(), &s3svc.GetObjectInput{
				Bucket: aws.String(bucketName),
				Key:    aws.String(objectKey),
			})
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			defer resp.Body.Close()
			io.Copy(w, resp.Body)
		case http.MethodPut:
			logging.Printf("[S3] PutObject: bucket=%s, key=%s", bucketName, objectKey)
			r.Body = http.MaxBytesReader(w, r.Body, maxUploadBytes)
			_, err := client.PutObject(r.Context(), &s3svc.PutObjectInput{
				Bucket: aws.String(bucketName),
				Key:    aws.String(objectKey),
				Body:   r.Body,
			})
			if err != nil {
				logging.Printf("[S3] Error putting object: %v", err)
				var maxBytesErr *http.MaxBytesError
				if errors.As(err, &maxBytesErr) {
					http.Error(w, "request body too large", http.StatusRequestEntityTooLarge)
					return
				}
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.WriteHeader(http.StatusCreated)
		case http.MethodDelete:
			_, err := client.DeleteObject(r.Context(), &s3svc.DeleteObjectInput{
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

	return mux
}
