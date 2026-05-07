package models

type MockChatClient struct {
	ChatFunc          func(messages []map[string]string) (string, interface{}, error)
	ChatStreamFunc    func(messages []map[string]string) (<-chan string, <-chan interface{}, <-chan error)
	GetEmbeddingsFunc func(text string) ([]float32, error)
}

func (m *MockChatClient) Chat(messages []map[string]string) (string, interface{}, error) {
	if m.ChatFunc != nil {
		return m.ChatFunc(messages)
	}
	return "", nil, nil
}

func (m *MockChatClient) ChatStream(messages []map[string]string) (<-chan string, <-chan interface{}, <-chan error) {
	if m.ChatStreamFunc != nil {
		return m.ChatStreamFunc(messages)
	}
	return nil, nil, nil
}

func (m *MockChatClient) GetEmbeddings(text string) ([]float32, error) {
	if m.GetEmbeddingsFunc != nil {
		return m.GetEmbeddingsFunc(text)
	}
	return nil, nil
}
