package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"app-builds/common/health"

	s3svc "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// mockS3 implements S3Client for tests.
type mockS3 struct {
	listBuckets   func(ctx context.Context, params *s3svc.ListBucketsInput, optFns ...func(*s3svc.Options)) (*s3svc.ListBucketsOutput, error)
	listObjectsV2 func(ctx context.Context, params *s3svc.ListObjectsV2Input, optFns ...func(*s3svc.Options)) (*s3svc.ListObjectsV2Output, error)
	getObject     func(ctx context.Context, params *s3svc.GetObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.GetObjectOutput, error)
	putObject     func(ctx context.Context, params *s3svc.PutObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.PutObjectOutput, error)
	deleteObject  func(ctx context.Context, params *s3svc.DeleteObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.DeleteObjectOutput, error)
}

func (m *mockS3) ListBuckets(ctx context.Context, params *s3svc.ListBucketsInput, optFns ...func(*s3svc.Options)) (*s3svc.ListBucketsOutput, error) {
	return m.listBuckets(ctx, params, optFns...)
}
func (m *mockS3) ListObjectsV2(ctx context.Context, params *s3svc.ListObjectsV2Input, optFns ...func(*s3svc.Options)) (*s3svc.ListObjectsV2Output, error) {
	return m.listObjectsV2(ctx, params, optFns...)
}
func (m *mockS3) GetObject(ctx context.Context, params *s3svc.GetObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.GetObjectOutput, error) {
	return m.getObject(ctx, params, optFns...)
}
func (m *mockS3) PutObject(ctx context.Context, params *s3svc.PutObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.PutObjectOutput, error) {
	return m.putObject(ctx, params, optFns...)
}
func (m *mockS3) DeleteObject(ctx context.Context, params *s3svc.DeleteObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.DeleteObjectOutput, error) {
	return m.deleteObject(ctx, params, optFns...)
}

func newTestMux(client S3Client, maxBytes int64) *http.ServeMux {
	healthSrv := health.NewServer()
	return buildMux(client, healthSrv, maxBytes)
}

func TestUploadSuccess(t *testing.T) {
	mock := &mockS3{
		putObject: func(ctx context.Context, params *s3svc.PutObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.PutObjectOutput, error) {
			// Drain the body so MaxBytesReader does not interfere.
			io.ReadAll(params.Body)
			return &s3svc.PutObjectOutput{}, nil
		},
	}
	mux := newTestMux(mock, 100<<20)

	req := httptest.NewRequest(http.MethodPut, "/buckets/mybucket/mykey.txt", strings.NewReader("hello"))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Errorf("expected 201, got %d", rec.Code)
	}
}

func TestUploadExceedsSizeLimit(t *testing.T) {
	mock := &mockS3{
		putObject: func(ctx context.Context, params *s3svc.PutObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.PutObjectOutput, error) {
			// Actually read the body — this triggers MaxBytesReader's limit.
			_, err := io.ReadAll(params.Body)
			if err != nil {
				return nil, err
			}
			return &s3svc.PutObjectOutput{}, nil
		},
	}
	// Allow only 5 bytes.
	mux := newTestMux(mock, 5)

	body := strings.NewReader("this body is definitely longer than five bytes")
	req := httptest.NewRequest(http.MethodPut, "/buckets/mybucket/mykey.txt", body)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Errorf("expected 413, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUploadS3Error(t *testing.T) {
	mock := &mockS3{
		putObject: func(ctx context.Context, params *s3svc.PutObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.PutObjectOutput, error) {
			io.ReadAll(params.Body)
			return nil, errors.New("bucket not found")
		},
	}
	mux := newTestMux(mock, 100<<20)

	req := httptest.NewRequest(http.MethodPut, "/buckets/missing/key.txt", strings.NewReader("data"))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", rec.Code)
	}
}

func TestListObjectsSuccess(t *testing.T) {
	name := "file.txt"
	sz := int64(42)
	mod := time.Now()
	mock := &mockS3{
		listObjectsV2: func(ctx context.Context, params *s3svc.ListObjectsV2Input, optFns ...func(*s3svc.Options)) (*s3svc.ListObjectsV2Output, error) {
			return &s3svc.ListObjectsV2Output{
				Contents: []types.Object{
					{Key: &name, Size: &sz, LastModified: &mod},
				},
			}, nil
		},
	}
	mux := newTestMux(mock, 100<<20)

	req := httptest.NewRequest(http.MethodGet, "/buckets/mybucket", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var objs []map[string]interface{}
	if err := json.NewDecoder(rec.Body).Decode(&objs); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(objs) != 1 {
		t.Errorf("expected 1 object, got %d", len(objs))
	}
}

func TestDeleteObjectSuccess(t *testing.T) {
	mock := &mockS3{
		deleteObject: func(ctx context.Context, params *s3svc.DeleteObjectInput, optFns ...func(*s3svc.Options)) (*s3svc.DeleteObjectOutput, error) {
			return &s3svc.DeleteObjectOutput{}, nil
		},
	}
	mux := newTestMux(mock, 100<<20)

	req := httptest.NewRequest(http.MethodDelete, "/buckets/mybucket/mykey.txt", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Errorf("expected 204, got %d", rec.Code)
	}
}

func TestListBucketsSuccess(t *testing.T) {
	name := "bucket-a"
	mock := &mockS3{
		listBuckets: func(ctx context.Context, params *s3svc.ListBucketsInput, optFns ...func(*s3svc.Options)) (*s3svc.ListBucketsOutput, error) {
			return &s3svc.ListBucketsOutput{
				Buckets: []types.Bucket{{Name: &name}},
			}, nil
		},
	}
	mux := newTestMux(mock, 100<<20)

	req := httptest.NewRequest(http.MethodGet, "/buckets", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var buckets []map[string]interface{}
	if err := json.NewDecoder(bytes.NewReader(rec.Body.Bytes())).Decode(&buckets); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(buckets) != 1 {
		t.Errorf("expected 1 bucket, got %d", len(buckets))
	}
}
