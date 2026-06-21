package pipeline

import (
	"regexp"
	"strings"
)

var literalAnswerFallbackPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)\b(?:secret code|code|answer|token)\s*(?:is|:)\s*([A-Z0-9][A-Z0-9-]{2,})\b`),
}

func extractLiteralAnswerFallback(prompt string, chunks [][]interface{}) (string, bool) {
	promptLower := strings.ToLower(prompt)
	interested := strings.Contains(promptLower, "code") || strings.Contains(promptLower, "answer") || strings.Contains(promptLower, "token")
	if !interested {
		return "", false
	}

	for _, chunk := range chunks {
		for _, item := range chunk {
			text := rawResultContextText(item)
			if text == "" {
				continue
			}
			for _, re := range literalAnswerFallbackPatterns {
				match := re.FindStringSubmatch(text)
				if len(match) > 1 {
					return strings.TrimSpace(match[1]), true
				}
			}
		}
	}

	return "", false
}
