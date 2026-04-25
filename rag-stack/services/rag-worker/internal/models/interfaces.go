package models

import (
	"context"
)

type ChatClient interface {
	Chat(messages []map[string]string) (string, interface{}, error)
	ChatStream(messages []map[string]string) (<-chan string, <-chan interface{}, <-chan error)
	GetEmbeddings(text string) ([]float32, error)
}

type Planner interface {
	Plan(ctx context.Context, prompt string) ([]string, interface{}, error)
	GetEmbeddings(ctx context.Context, text string) ([]float32, error)
}

type Executor interface {
	Execute(ctx context.Context, prompt string, contexts []interface{}) (string, interface{}, error)
	ExecuteStream(ctx context.Context, prompt string, contexts []interface{}) (<-chan string, <-chan interface{}, <-chan error)
	IsInsufficientContext(result string) bool
}
