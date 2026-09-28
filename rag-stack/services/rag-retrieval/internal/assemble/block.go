// Package assemble renders retrieved chunks into the <rag-context> block that
// the plugin injects or the rag_search tool returns.
package assemble

import (
	"fmt"
	"strings"

	"app-builds/rag-retrieval/internal/memory"
	"app-builds/rag-retrieval/internal/qdrant"
)

// EmptyMessage is returned instead of an empty string when nothing matched.
//
// Spec §10.4: a model reads silence as "nothing exists". An explicit statement
// that the corpus had no match is a different claim from an empty response, and
// only one of them is true.
const EmptyMessage = "no matching context in corpus"

// charsPerToken approximates tokens without pulling in a tokenizer.
//
// This is a budget guard, not accounting. 4 chars/token is the usual English
// figure; code runs denser, so the estimate over-counts tokens slightly for
// prose and under-counts for minified content. Deliberately conservative: it
// is better to inject a little less than the budget than to overflow a context
// window whose real size we are still measuring (M4).
const charsPerToken = 4

func estimateTokens(s string) int {
	return (len(s) + charsPerToken - 1) / charsPerToken
}

type Input struct {
	Chunks    []qdrant.Chunk
	Memory    []memory.Item
	Tags      []string
	Profile   string
	TopK      int
	MaxTokens int
}

type Result struct {
	Block     string
	Tokens    int
	Truncated bool
	// Used is the number of chunks that fit inside the budget.
	Used int
}

// Build renders the block, dropping the lowest-scoring chunks first when the
// budget binds. Chunks are assumed to arrive score-descending.
func Build(in Input) Result {
	if len(in.Chunks) == 0 && len(in.Memory) == 0 {
		return Result{Block: "", Tokens: 0, Truncated: false, Used: 0}
	}

	budget := in.MaxTokens
	if budget <= 0 {
		budget = 4096
	}

	var b strings.Builder
	attrs := []string{fmt.Sprintf("k=%q", fmt.Sprint(in.TopK))}
	if in.Profile != "" {
		attrs = append(attrs, fmt.Sprintf("profile=%q", in.Profile))
	}
	if len(in.Tags) > 0 {
		attrs = append(attrs, fmt.Sprintf("tags=%q", strings.Join(in.Tags, ",")))
	}
	header := fmt.Sprintf("<rag-context %s>\n", strings.Join(attrs, " "))
	footer := "</rag-context>"

	b.WriteString(header)
	spent := estimateTokens(header) + estimateTokens(footer)
	truncated := false
	used := 0

	for _, c := range in.Chunks {
		entry := renderChunk(c)
		cost := estimateTokens(entry)
		if spent+cost > budget {
			truncated = true
			// Keep scanning: a later chunk may be small enough to fit. Ordering
			// is preserved, so this only ever adds cheaper context.
			continue
		}
		b.WriteString(entry)
		spent += cost
		used++
	}

	for _, m := range in.Memory {
		entry := renderMemory(m)
		cost := estimateTokens(entry)
		if spent+cost > budget {
			truncated = true
			continue
		}
		b.WriteString(entry)
		spent += cost
	}

	b.WriteString(footer)

	// Everything was squeezed out by the budget — say so rather than emitting a
	// bare wrapper the model has to interpret.
	if used == 0 && len(in.Memory) == 0 {
		return Result{Block: "", Tokens: 0, Truncated: true, Used: 0}
	}

	block := b.String()
	return Result{Block: block, Tokens: estimateTokens(block), Truncated: truncated, Used: used}
}

func renderChunk(c qdrant.Chunk) string {
	var loc string
	switch {
	case c.StartLine != nil && c.EndLine != nil:
		loc = fmt.Sprintf("%s:%d-%d", c.Path, *c.StartLine, *c.EndLine)
	case c.Path != "":
		// Pre-line-range chunks: name the chunk index so the citation is still
		// actionable, and do not imply a line number we do not have.
		loc = fmt.Sprintf("%s#chunk%d", c.Path, c.ChunkIdx)
	default:
		loc = "unknown"
	}

	tagAttr := ""
	if len(c.TagNames) > 0 {
		tagAttr = fmt.Sprintf(" tags=%q", strings.Join(c.TagNames, ","))
	}

	return fmt.Sprintf("<chunk source=%q score=\"%.3f\"%s>\n%s\n</chunk>\n",
		loc, c.Score, tagAttr, strings.TrimRight(c.Text, "\n"))
}

func renderMemory(m memory.Item) string {
	body := m.Content
	if body == "" {
		body = m.Summary
	}
	kind := m.MemoryType
	if kind == "" {
		kind = "note"
	}
	return fmt.Sprintf("<memory type=%q>\n%s\n</memory>\n", kind, strings.TrimRight(body, "\n"))
}

// EstimateTokens is exported for the handler's response accounting.
func EstimateTokens(s string) int { return estimateTokens(s) }
