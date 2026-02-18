package ollama

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
	"app-builds/rag-worker/internal/config"
)

type OllamaClient struct {
	cfg *config.Config
	httpClient *http.Client
}

func NewClient(cfg *config.Config) *OllamaClient {
	return &OllamaClient{
		cfg: cfg,
		httpClient: &http.Client{Timeout: 60 * time.Second},
	}
}

func (o *OllamaClient) Chat(messages []map[string]string) (string, error) {
	url := fmt.Sprintf("%s/v1/chat/completions", o.cfg.OllamaURL)
	
	payload := map[string]interface{}{
		"model":    o.cfg.OllamaModel,
		"messages": messages,
		"stream":   false,
	}
	
	body, _ := json.Marshal(payload)
	resp, err := o.httpClient.Post(url, "application/json", bytes.NewBuffer(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("ollama returned status %d", resp.StatusCode)
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}

	if len(result.Choices) > 0 {
		return result.Choices[0].Message.Content, nil
	}

	return "", fmt.Errorf("no response from ollama")
}

func (o *OllamaClient) GetEmbeddings(text string) ([]float32, error) {
    url := fmt.Sprintf("%s/api/embeddings", o.cfg.OllamaURL)
    
    payload := map[string]interface{}{
        "model":  o.cfg.OllamaModel,
        "prompt": text,
    }
    
    body, _ := json.Marshal(payload)
    resp, err := o.httpClient.Post(url, "application/json", bytes.NewBuffer(body))
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    var result struct {
        Embedding []float32 `json:"embedding"`
    }

    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        return nil, err
    }

    return result.Embedding, nil
}
