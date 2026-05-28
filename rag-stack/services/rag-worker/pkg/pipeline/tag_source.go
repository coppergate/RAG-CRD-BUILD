package pipeline

import (
	"context"
	"sort"

	"app-builds/common/contracts"
	"app-builds/common/ent"
	"app-builds/common/ent/session"
)

// TagSource resolves the authoritative retrieval tags for a session.
type TagSource interface {
	TagsForSession(ctx context.Context, sessionID int64) ([]int64, error)
}

// NewSessionTagSource creates a DB-backed tag source for retrieval.
func NewSessionTagSource(client *ent.Client) TagSource {
	if client == nil {
		return nil
	}
	return &sessionTagSource{client: client}
}

type sessionTagSource struct {
	client *ent.Client
}

func (s *sessionTagSource) TagsForSession(ctx context.Context, sessionID int64) ([]int64, error) {
	if s == nil || s.client == nil {
		return nil, nil
	}
	if sessionID <= 0 {
		return nil, nil
	}

	sess, err := s.client.Session.Query().
		Where(session.ID(sessionID)).
		WithTags().
		Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return nil, nil
		}
		return nil, err
	}

	seen := make(map[int64]struct{})
	tagIDs := make([]int64, 0)
	for _, t := range sess.Edges.Tags {
		if _, ok := seen[t.ID]; ok {
			continue
		}
		seen[t.ID] = struct{}{}
		tagIDs = append(tagIDs, t.ID)
	}

	sort.Slice(tagIDs, func(i, j int) bool { return tagIDs[i] < tagIDs[j] })
	return tagIDs, nil
}

func normalizeTagIDs(tagIDs []int64) []int64 {
	if len(tagIDs) == 0 {
		return nil
	}
	seen := make(map[int64]struct{}, len(tagIDs))
	normalized := make([]int64, 0, len(tagIDs))
	for _, tagID := range tagIDs {
		if tagID <= 0 {
			continue
		}
		if _, ok := seen[tagID]; ok {
			continue
		}
		seen[tagID] = struct{}{}
		normalized = append(normalized, tagID)
	}
	sort.Slice(normalized, func(i, j int) bool { return normalized[i] < normalized[j] })
	return normalized
}

func (h *Handler) resolveSearchTags(ctx context.Context, req *contracts.InternalRequest) ([]int64, error) {
	if h.tagSource == nil {
		return normalizeTagIDs(req.Tags), nil
	}
	tags, err := h.tagSource.TagsForSession(ctx, req.SessionId)
	if err != nil {
		if len(req.Tags) > 0 {
			return normalizeTagIDs(req.Tags), nil
		}
		return nil, err
	}
	if len(tags) == 0 && len(req.Tags) > 0 {
		return normalizeTagIDs(req.Tags), nil
	}
	return tags, nil
}
