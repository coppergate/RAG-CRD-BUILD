package service

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"sort"
	"strings"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/codeembedding"
	"app-builds/common/ent/session"
	"app-builds/common/ent/tag"
	"app-builds/common/tlsutil"
	"entgo.io/ent/dialect/sql"
	"entgo.io/ent/dialect/sql/sqljson"
	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/google/uuid"
	"google.golang.org/protobuf/encoding/protojson"

	"app-builds/common/contracts"
)

type MaintenanceService struct {
	client         *ent.Client
	qdrantProducer pulsar.Producer
	ingestionURL   string
}

func NewMaintenanceService(client *ent.Client, qdrantProducer pulsar.Producer, ingestionURL string) *MaintenanceService {
	return &MaintenanceService{
		client:         client,
		qdrantProducer: qdrantProducer,
		ingestionURL:   ingestionURL,
	}
}

func (s *MaintenanceService) MergeTags(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var payload struct {
		SourceIDs []string `json:"source_ids"`
		TargetID  string   `json:"target_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	targetUUID, err := uuid.Parse(payload.TargetID)
	if err != nil {
		http.Error(w, "Invalid target ID", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	sourceUUIDs := make([]uuid.UUID, 0, len(payload.SourceIDs))
	for _, idStr := range payload.SourceIDs {
		if uid, err := uuid.Parse(idStr); err == nil {
			sourceUUIDs = append(sourceUUIDs, uid)
		}
	}

	if len(sourceUUIDs) == 0 {
		w.WriteHeader(http.StatusOK)
		return
	}

	allTagIDs := append([]uuid.UUID{targetUUID}, sourceUUIDs...)
	involvedTags, err := s.client.Tag.Query().Where(tag.IDIn(allTagIDs...)).All(ctx)
	if err != nil {
		http.Error(w, "Failed to fetch tags", http.StatusInternalServerError)
		return
	}

	tagMap := make(map[uuid.UUID]string)
	for _, t := range involvedTags {
		tagMap[t.ID] = t.Name
	}

	embeddings, err := s.client.CodeEmbedding.Query().
		Where(codeembedding.HasTagsWith(tag.IDIn(sourceUUIDs...))).
		WithTags().
		All(ctx)
	if err != nil {
		log.Printf("Merge: Failed to find embeddings for source tags: %v", err)
		http.Error(w, "Failed to find files for source tags", http.StatusInternalServerError)
		return
	}

	type Group struct {
		TagIDs   []string
		TagNames []string
		Paths    []string
	}
	groups := make(map[string]*Group)

	pathTags := make(map[string]map[uuid.UUID]bool)
	for _, ce := range embeddings {
		path, _ := ce.Metadata["path"].(string)
		if path == "" {
			continue
		}
		if _, ok := pathTags[path]; !ok {
			pathTags[path] = make(map[uuid.UUID]bool)
		}
		for _, t := range ce.Edges.Tags {
			pathTags[path][t.ID] = true
		}
	}

	for path, currentTags := range pathTags {
		newTagIDsMap := make(map[string]bool)
		newTagIDsMap[payload.TargetID] = true

		for tid := range currentTags {
			isSource := false
			for _, srcID := range sourceUUIDs {
				if tid == srcID {
					isSource = true
					break
				}
			}
			if !isSource {
				newTagIDsMap[tid.String()] = true
			}
		}

		var newTagIDs []string
		var newTagNames []string
		for idStr := range newTagIDsMap {
			newTagIDs = append(newTagIDs, idStr)
			uid, _ := uuid.Parse(idStr)
			if name, ok := tagMap[uid]; ok {
				newTagNames = append(newTagNames, name)
			}
		}
		sort.Strings(newTagIDs)
		key := strings.Join(newTagIDs, ",")

		if _, ok := groups[key]; !ok {
			groups[key] = &Group{
				TagIDs:   newTagIDs,
				TagNames: newTagNames,
				Paths:    []string{},
			}
		}
		groups[key].Paths = append(groups[key].Paths, path)
	}

	httpClient, _ := tlsutil.NewHTTPClient(true, 10*time.Minute)

	for _, group := range groups {
		log.Printf("Merge: Processing group with tags %v and %d files", group.TagNames, len(group.Paths))

		_, err = s.client.CodeEmbedding.Delete().
			Where(func(sel *sql.Selector) {
				sel.Where(sqljson.ValueIn("metadata", s.anySlice(group.Paths), sqljson.Path("path")))
			}).
			Exec(ctx)
		if err != nil {
			log.Printf("Merge: Error deleting from code_embedding: %v", err)
		}

		if s.qdrantProducer != nil {
			delOp := &contracts.QdrantOp{
				Id:         uuid.New().String(),
				Action:     "delete",
				Collection: "vectors",
				Paths:      group.Paths,
			}
			p, _ := protojson.Marshal(delOp)
			s.qdrantProducer.Send(ctx, &pulsar.ProducerMessage{Payload: p})
		}

		ingestReq := struct {
			IngestionID string   `json:"ingestion_id"`
			TagNames    []string `json:"tag_names"`
			TagIDs      []string `json:"tag_ids"`
			FileNames   []string `json:"file_names"`
		}{
			IngestionID: uuid.New().String(),
			TagNames:    group.TagNames,
			TagIDs:      group.TagIDs,
			FileNames:   group.Paths,
		}

		body, _ := json.Marshal(ingestReq)
		ingestEndpoint := s.ingestionURL + "/api/ingest/"
		resp, err := httpClient.Post(ingestEndpoint, "application/json", bytes.NewBuffer(body))
		if err != nil {
			log.Printf("Merge: Failed to trigger ingestion for group: %v", err)
		} else {
			resp.Body.Close()
			log.Printf("Merge: Triggered ingestion for group, status: %s", resp.Status)
		}
	}

	for _, srcUUID := range sourceUUIDs {
		sessions, _ := s.client.Session.Query().
			Where(session.HasTagsWith(tag.ID(srcUUID))).
			All(ctx)
		for _, sess := range sessions {
			sess.Update().
				RemoveTagIDs(srcUUID).
				AddTagIDs(targetUUID).
				Exec(ctx)
		}
		s.client.Tag.DeleteOneID(srcUUID).Exec(ctx)
	}

	w.WriteHeader(http.StatusOK)
}

func (s *MaintenanceService) anySlice(paths []string) []any {
	res := make([]any, len(paths))
	for i, v := range paths {
		res[i] = v
	}
	return res
}
