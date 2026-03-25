package models

type MockChatClient struct {
	ChatFunc          func(messages []map[string]string) (string, error)
	GetEmbeddingsFunc func(text string) ([]float32, error)
}

func (m *MockChatClient) Chat(messages []map[string]string) (string, error) {
	if m.ChatFunc != nil {
		return m.ChatFunc(messages)
	}
	return "", nil
}

func (m *MockChatClient) GetEmbeddings(text string) ([]float32, error) {
	if m.GetEmbeddingsFunc != nil {
		return m.GetEmbeddingsFunc(text)
	}
	return nil, nil
}
