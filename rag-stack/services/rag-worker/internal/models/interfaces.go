package models

import (
	"context"
)

type ChatClient interface {
	Chat(messages []map[string]string) (string, error)
	ChatStream(messages []map[string]string) (<-chan string, <-chan error)
	GetEmbeddings(text string) ([]float32, error)
}

type Planner interface {
	Plan(ctx context.Context, prompt string) ([]string, error)
	GetEmbeddings(ctx context.Context, text string) ([]float32, error)
}

type Executor interface {
	Execute(ctx context.Context, prompt string, contexts []interface{}) (string, error)
	ExecuteStream(ctx context.Context, prompt string, contexts []interface{}) (<-chan string, <-chan error)
	IsInsufficientContext(result string) bool
}
