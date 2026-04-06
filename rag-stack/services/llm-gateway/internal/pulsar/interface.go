package pulsar

import (
	"context"
	"app-builds/common/contracts"
)

type Client interface {
	SendRequest(ctx context.Context, id string, payload interface{}) (string, error)
	SendPromptEvent(ctx context.Context, id, sessionID, content string) error
	SubscribeStream(id string, ch chan contracts.StreamChunk)
	UnsubscribeStream(id string)
	SendRawRequest(ctx context.Context, payload interface{}) error
	Close()
	Ping() error
}
