package pipeline

import (
	"context"
	"sort"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/codeembedding"
	"entgo.io/ent/dialect/sql"
	"entgo.io/ent/dialect/sql/sqljson"
)

// TagSource resolves the authoritative embedding tags for a session.
type TagSource interface {
	TagsForSession(ctx context.Context, sessionID int64) ([]int64, error)
}

// NewEmbeddingTagSource creates a DB-backed tag source for retrieval.
func NewEmbeddingTagSource(client *ent.Client) TagSource {
	if client == nil {
		return nil
	}
	return &embeddingTagSource{client: client}
}

type embeddingTagSource struct {
	client *ent.Client
}

func (s *embeddingTagSource) TagsForSession(ctx context.Context, sessionID int64) ([]int64, error) {
	if s == nil || s.client == nil {
		return nil, nil
	}

	embeddings, err := s.client.CodeEmbedding.Query().
		Where(func(sel *sql.Selector) {
			sel.Where(sqljson.ValueEQ(codeembedding.FieldMetadata, sessionID, sqljson.Path("session_id")))
		}).
		WithTags().
		All(ctx)
	if err != nil {
		return nil, err
	}

	seen := make(map[int64]struct{})
	tagIDs := make([]int64, 0)
	for _, embedding := range embeddings {
		for _, t := range embedding.Edges.Tags {
			if _, ok := seen[t.ID]; ok {
				continue
			}
			seen[t.ID] = struct{}{}
			tagIDs = append(tagIDs, t.ID)
		}
	}

	sort.Slice(tagIDs, func(i, j int) bool { return tagIDs[i] < tagIDs[j] })
	return tagIDs, nil
}

func (h *Handler) resolveSearchTags(ctx context.Context, req *contracts.InternalRequest) ([]int64, error) {
	if h.tagSource == nil {
		return req.Tags, nil
	}
	return h.tagSource.TagsForSession(ctx, req.SessionId)
}
