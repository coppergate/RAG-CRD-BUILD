package pulsar

import (
	"context"
)

type Client interface {
	SendRequest(ctx context.Context, id string, payload interface{}) (string, error)
	SendPromptEvent(ctx context.Context, id, sessionID, content string) error
	SubscribeStream(id string, ch chan StreamChunk)
	UnsubscribeStream(id string)
	SendRawRequest(ctx context.Context, payload interface{}) error
	Close()
	Ping() error
}
