package service

import (
	"encoding/json"
	"net/http"
	"sort"
	"strconv"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/codeembedding"
	"app-builds/common/ent/session"
	"app-builds/common/ent/tag"
	"entgo.io/ent/dialect/sql"
	"entgo.io/ent/dialect/sql/sqljson"
)

type StorageService struct {
	client *ent.Client
}

func NewStorageService(client *ent.Client) *StorageService {
	return &StorageService{client: client}
}

type FileInfo struct {
	Path           string    `json:"path"`
	Bucket         string    `json:"bucket"`
	CreatedAt      time.Time `json:"created_at"`
	Tags           []string  `json:"tags"`
	Status         string    `json:"status"`
	EmbeddingModel string    `json:"embedding_model"`
	VectorSize     int       `json:"vector_size"`
	IngestionID    int64     `json:"ingestion_id"`
	SourceHash     string    `json:"source_hash,omitempty"`
}

func (s *StorageService) GetFiles(w http.ResponseWriter, r *http.Request) {
	sessionIDStr := r.URL.Query().Get("session_id")
	tagIDs := r.URL.Query()["tag_id"]
	embeddingModel := r.URL.Query().Get("embedding_model")

	ctx := r.Context()
	query := s.client.CodeEmbedding.Query()

	if sessionIDStr != "" {
		if sessID, err := strconv.ParseInt(sessionIDStr, 10, 64); err == nil {
			query = query.Where(codeembedding.HasTagsWith(tag.HasSessionsWith(session.ID(sessID))))
		}
	}
	for _, tidStr := range tagIDs {
		if tidStr != "" {
			if tID, err := strconv.ParseInt(tidStr, 10, 64); err == nil {
				query = query.Where(codeembedding.HasTagsWith(tag.ID(tID)))
			}
		}
	}
	if embeddingModel != "" {
		query = query.Where(func(sq *sql.Selector) {
			sq.Where(sqljson.ValueEQ(codeembedding.FieldMetadata, embeddingModel, sqljson.Path("embedding_model")))
		})
	}

	embeddings, err := query.
		Select(
			codeembedding.FieldID,
			codeembedding.FieldMetadata,
			codeembedding.FieldCreatedAt,
			codeembedding.FieldIngestionID,
		).
		WithIngestion().
		WithTags().
		All(ctx)

	if err != nil {
		http.Error(w, "Failed to query embeddings: "+err.Error(), http.StatusInternalServerError)
		return
	}

	fileMap := make(map[string]*FileInfo)

	for _, ce := range embeddings {
		if ce.Metadata == nil {
			continue
		}
		path, _ := ce.Metadata["path"].(string)
		if path == "" {
			continue
		}
		model, _ := ce.Metadata["embedding_model"].(string)
		vectorSize := 0
		if rawVS, ok := ce.Metadata["vector_size"]; ok {
			switch t := rawVS.(type) {
			case float64:
				vectorSize = int(t)
			case int:
				vectorSize = t
			}
		}
		sourceHash, _ := ce.Metadata["source_hash"].(string)
		key := path + "|" + model + "|" + strconv.Itoa(vectorSize)

		if _, ok := fileMap[key]; !ok {
			bucket := ""
			createdAt := ce.CreatedAt
			if ce.Edges.Ingestion != nil {
				bucket = ce.Edges.Ingestion.S3BucketID
				createdAt = ce.Edges.Ingestion.CreatedAt
			}
			fileMap[key] = &FileInfo{
				Path:           path,
				Bucket:         bucket,
				CreatedAt:      createdAt,
				Tags:           []string{},
				Status:         "SYNCED",
				EmbeddingModel: model,
				VectorSize:     vectorSize,
				IngestionID:    ce.IngestionID,
				SourceHash:     sourceHash,
			}
		}

		tagSet := make(map[string]bool)
		for _, t := range fileMap[key].Tags {
			tagSet[t] = true
		}
		for _, t := range ce.Edges.Tags {
			if !tagSet[t.Name] {
				fileMap[key].Tags = append(fileMap[key].Tags, t.Name)
				tagSet[t.Name] = true
			}
		}
	}

	files := []*FileInfo{}
	for _, f := range fileMap {
		files = append(files, f)
	}
	sort.Slice(files, func(i, j int) bool {
		if files[i].Path == files[j].Path {
			return files[i].EmbeddingModel < files[j].EmbeddingModel
		}
		return files[i].Path < files[j].Path
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(files)
}

func (s *StorageService) GetFileVectors(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	embeddingModel := r.URL.Query().Get("embedding_model")
	if path == "" {
		http.Error(w, "Path is required", http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	// Query embeddings where metadata->'path' matches the given path
	embeddings, err := s.client.CodeEmbedding.Query().
		Where(func(sq *sql.Selector) {
			sq.Where(sqljson.ValueEQ(codeembedding.FieldMetadata, path, sqljson.Path("path")))
			if embeddingModel != "" {
				sq.Where(sqljson.ValueEQ(codeembedding.FieldMetadata, embeddingModel, sqljson.Path("embedding_model")))
			}
		}).
		WithIngestion().
		WithTags().
		Order(ent.Asc(codeembedding.FieldID)).
		All(ctx)

	if err != nil {
		http.Error(w, "Failed to query vectors: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(embeddings)
}
