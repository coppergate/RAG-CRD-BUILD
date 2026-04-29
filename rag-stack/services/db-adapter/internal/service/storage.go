package service

import (
	"encoding/json"
	"net/http"
	"sort"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/codeembedding"
	"app-builds/common/ent/session"
	"app-builds/common/ent/tag"
	"github.com/google/uuid"
)

type StorageService struct {
	client *ent.Client
}

func NewStorageService(client *ent.Client) *StorageService {
	return &StorageService{client: client}
}

type FileInfo struct {
	Path      string    `json:"path"`
	Bucket    string    `json:"bucket"`
	CreatedAt time.Time `json:"created_at"`
	Tags      []string  `json:"tags"`
	Status    string    `json:"status"`
}

func (s *StorageService) GetFiles(w http.ResponseWriter, r *http.Request) {
	sessionIDStr := r.URL.Query().Get("session_id")
	tagIDStr := r.URL.Query().Get("tag_id")

	ctx := r.Context()
	query := s.client.CodeEmbedding.Query()

	if sessionIDStr != "" {
		if sessID, err := uuid.Parse(sessionIDStr); err == nil {
			query = query.Where(codeembedding.HasTagsWith(tag.HasSessionsWith(session.ID(sessID))))
		}
	}
	if tagIDStr != "" {
		if tID, err := uuid.Parse(tagIDStr); err == nil {
			query = query.Where(codeembedding.HasTagsWith(tag.ID(tID)))
		}
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

		if _, ok := fileMap[path]; !ok {
			bucket := ""
			createdAt := ce.CreatedAt
			if ce.Edges.Ingestion != nil {
				bucket = ce.Edges.Ingestion.S3BucketID
				createdAt = ce.Edges.Ingestion.CreatedAt
			}
			fileMap[path] = &FileInfo{
				Path:      path,
				Bucket:    bucket,
				CreatedAt: createdAt,
				Tags:      []string{},
				Status:    "SYNCED",
			}
		}

		tagSet := make(map[string]bool)
		for _, t := range fileMap[path].Tags {
			tagSet[t] = true
		}
		for _, t := range ce.Edges.Tags {
			if !tagSet[t.Name] {
				fileMap[path].Tags = append(fileMap[path].Tags, t.Name)
				tagSet[t.Name] = true
			}
		}
	}

	var files []*FileInfo
	for _, f := range fileMap {
		files = append(files, f)
	}
	sort.Slice(files, func(i, j int) bool {
		return files[i].Path < files[j].Path
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(files)
}
