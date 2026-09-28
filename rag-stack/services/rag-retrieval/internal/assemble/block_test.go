package assemble

import (
	"strings"
	"testing"

	"app-builds/rag-retrieval/internal/memory"
	"app-builds/rag-retrieval/internal/qdrant"
)

func chunk(path, text string, score float32, start, end *int) qdrant.Chunk {
	return qdrant.Chunk{Path: path, Text: text, Score: score, StartLine: start, EndLine: end}
}

func TestEmptyInputProducesNoBlock(t *testing.T) {
	// Callers substitute EmptyMessage; Build must not emit a bare wrapper that
	// the model has to interpret as either "empty" or "broken".
	got := Build(Input{})
	if got.Block != "" {
		t.Errorf("expected empty block, got %q", got.Block)
	}
	if got.Used != 0 || got.Truncated {
		t.Errorf("unexpected result %+v", got)
	}
}

func TestLineRangeCitationWhenPresent(t *testing.T) {
	s, e := 612, 664
	got := Build(Input{
		Chunks:    []qdrant.Chunk{chunk("pkg/pipeline/pipeline.go", "func Run() {}", 0.83, &s, &e)},
		MaxTokens: 4096,
	})
	if !strings.Contains(got.Block, `source="pkg/pipeline/pipeline.go:612-664"`) {
		t.Errorf("expected a line-range citation, got:\n%s", got.Block)
	}
}

func TestChunkCitationWhenLineRangeAbsent(t *testing.T) {
	// Pre-line-range chunks must not imply a line number we do not have.
	c := chunk("docs/PLAN.md", "some prose", 0.5, nil, nil)
	c.ChunkIdx = 3
	got := Build(Input{Chunks: []qdrant.Chunk{c}, MaxTokens: 4096})
	if !strings.Contains(got.Block, `source="docs/PLAN.md#chunk3"`) {
		t.Errorf("expected a chunk citation, got:\n%s", got.Block)
	}
	if strings.Contains(got.Block, ":0-0") {
		t.Error("must not fabricate a 0-0 line range")
	}
}

func TestBudgetTruncatesAndReportsIt(t *testing.T) {
	big := strings.Repeat("x", 4000) // ~1000 tokens each
	in := Input{
		Chunks: []qdrant.Chunk{
			chunk("a.go", big, 0.9, nil, nil),
			chunk("b.go", big, 0.8, nil, nil),
			chunk("c.go", big, 0.7, nil, nil),
		},
		MaxTokens: 1200, // room for roughly one
	}
	got := Build(in)
	if !got.Truncated {
		t.Error("expected Truncated=true when the budget binds")
	}
	if got.Used == 0 {
		t.Fatal("expected at least one chunk to fit")
	}
	if got.Used == len(in.Chunks) {
		t.Error("expected fewer chunks than supplied")
	}
	if got.Tokens > in.MaxTokens {
		t.Errorf("block of %d tokens exceeds budget %d", got.Tokens, in.MaxTokens)
	}
	// Highest-scoring chunk must be the one kept.
	if !strings.Contains(got.Block, `source="a.go`) {
		t.Error("expected the highest-scoring chunk to survive truncation")
	}
}

func TestBudgetTooSmallForAnythingYieldsEmpty(t *testing.T) {
	got := Build(Input{
		Chunks:    []qdrant.Chunk{chunk("a.go", strings.Repeat("x", 40000), 0.9, nil, nil)},
		MaxTokens: 10,
	})
	if got.Block != "" {
		t.Errorf("expected empty block when nothing fits, got %d chars", len(got.Block))
	}
	if !got.Truncated {
		t.Error("expected Truncated=true")
	}
}

func TestMemoryIsRendered(t *testing.T) {
	got := Build(Input{
		Memory:    []memory.Item{{MemoryType: "rule", Content: "always vet before building"}},
		MaxTokens: 4096,
	})
	if !strings.Contains(got.Block, `<memory type="rule">`) {
		t.Errorf("expected memory to render, got:\n%s", got.Block)
	}
}

func TestProfileAndTagsAppearInHeader(t *testing.T) {
	got := Build(Input{
		Chunks:    []qdrant.Chunk{chunk("a.go", "x", 0.9, nil, nil)},
		Tags:      []string{"stack-go", "stack-docs"},
		Profile:   "executor",
		TopK:      4,
		MaxTokens: 4096,
	})
	for _, want := range []string{`profile="executor"`, `tags="stack-go,stack-docs"`} {
		if !strings.Contains(got.Block, want) {
			t.Errorf("expected %s in header, got:\n%s", want, got.Block)
		}
	}
}
