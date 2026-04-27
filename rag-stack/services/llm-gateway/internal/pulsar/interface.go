package pulsar

import (
	"context"
	"app-builds/common/contracts"
	"google.golang.org/protobuf/proto"
)

type Client interface {
	SendRequest(ctx context.Context, id string, payload proto.Message) (string, error)
	SendPromptEvent(ctx context.Context, id, sessionID, content string) error
	SubscribeStream(id string, ch chan contracts.StreamChunk)
	UnsubscribeStream(id string)
	SendRawRequest(ctx context.Context, payload proto.Message) error
	Close()
	Ping() error
}
