package contracts

import (
	"fmt"
	"strings"
	"unicode"
)

func NormalizeEmbeddingModelName(model string) string {
	model = strings.ToLower(strings.TrimSpace(model))
	if model == "" {
		return ""
	}

	var b strings.Builder
	lastDash := false
	for _, r := range model {
		switch {
		case unicode.IsLetter(r), unicode.IsDigit(r):
			b.WriteRune(r)
			lastDash = false
		default:
			if !lastDash {
				b.WriteByte('-')
				lastDash = true
			}
		}
	}

	return strings.Trim(b.String(), "-")
}

func BuildEmbeddingCollection(prefix, embeddingModel string, vectorSize int) string {
	base := strings.TrimSpace(prefix)
	if base == "" {
		base = "vectors"
	}

	normalized := NormalizeEmbeddingModelName(embeddingModel)
	switch {
	case normalized != "" && vectorSize > 0:
		return fmt.Sprintf("%s-%s-%d", base, normalized, vectorSize)
	case normalized != "":
		return fmt.Sprintf("%s-%s", base, normalized)
	case vectorSize > 0:
		return fmt.Sprintf("%s-%d", base, vectorSize)
	default:
		return base
	}
}
