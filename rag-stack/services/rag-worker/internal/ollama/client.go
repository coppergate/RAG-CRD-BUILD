package ollama

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"app-builds/common/tlsutil"
)

type OllamaClient struct {
	url        string
	model      string
	httpClient *http.Client
}

func NewClient(url, model string) *OllamaClient {
	useTLS := strings.HasPrefix(url, "https://")
	httpClient, err := tlsutil.NewHTTPClient(useTLS, 60*time.Second)
	if err != nil {
		log.Fatalf("Failed to create Ollama HTTP client with TLS: %v", err)
	}
	return &OllamaClient{
		url:        url,
		model:      model,
		httpClient: httpClient,
	}
}

func (o *OllamaClient) Chat(messages []map[string]string) (string, error) {
	url := fmt.Sprintf("%s/v1/chat/completions", o.url)

	payload := map[string]interface{}{
		"model":    o.model,
		"messages": messages,
		"stream":   false,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("failed to marshal chat payload: %w", err)
	}
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

func (o *OllamaClient) ChatStream(messages []map[string]string) (<-chan string, <-chan error) {
	out := make(chan string)
	errCh := make(chan error, 1)

	go func() {
		defer close(out)
		defer close(errCh)

		url := fmt.Sprintf("%s/v1/chat/completions", o.url)
		payload := map[string]interface{}{
			"model":    o.model,
			"messages": messages,
			"stream":   true,
		}

		body, err := json.Marshal(payload)
		if err != nil {
			errCh <- fmt.Errorf("failed to marshal chat payload: %w", err)
			return
		}

		resp, err := o.httpClient.Post(url, "application/json", bytes.NewBuffer(body))
		if err != nil {
			errCh <- err
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			errCh <- fmt.Errorf("ollama returned status %d", resp.StatusCode)
			return
		}

		scanner := bufio.NewScanner(resp.Body)
		for scanner.Scan() {
			line := scanner.Text()
			if line == "" {
				continue
			}
			if !strings.HasPrefix(line, "data: ") {
				continue
			}
			data := strings.TrimPrefix(line, "data: ")
			if data == "[DONE]" {
				break
			}

			var chunk struct {
				Choices []struct {
					Delta struct {
						Content string `json:"content"`
					} `json:"delta"`
				} `json:"choices"`
			}
			if err := json.Unmarshal([]byte(data), &chunk); err != nil {
				errCh <- fmt.Errorf("failed to unmarshal chunk: %w (data: %s)", err, data)
				return
			}
			if len(chunk.Choices) > 0 {
				out <- chunk.Choices[0].Delta.Content
			}
		}
		if err := scanner.Err(); err != nil {
			errCh <- err
		}
	}()

	return out, errCh
}

func (o *OllamaClient) GetEmbeddings(text string) ([]float32, error) {
	url := fmt.Sprintf("%s/api/embeddings", o.url)

	payload := map[string]interface{}{
		"model":  o.model,
		"prompt": text,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal embeddings payload: %w", err)
	}
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
	
func (o *OllamaClient) Ping() error {
	url := fmt.Sprintf("%s/api/tags", o.url)
	resp, err := o.httpClient.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("ollama returned status %d", resp.StatusCode)
	}
	return nil
}
