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

	"app-builds/common/contracts"
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

type ChatResponse struct {
	Model      string `json:"model"`
	CreatedAt  string `json:"created_at"`
	Message    struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	} `json:"message"`
	Done               bool  `json:"done"`
	TotalDuration      int64 `json:"total_duration"`
	LoadDuration       int64 `json:"load_duration"`
	PromptEvalCount    int   `json:"prompt_eval_count"`
	PromptEvalDuration int64 `json:"prompt_eval_duration"`
	EvalCount          int   `json:"eval_count"`
	EvalDuration       int64 `json:"eval_duration"`
}

func (o *OllamaClient) Chat(messages []map[string]string) (string, interface{}, error) {
	url := fmt.Sprintf("%s/api/chat", o.url)

	payload := map[string]interface{}{
		"model":    o.model,
		"messages": messages,
		"stream":   false,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", nil, fmt.Errorf("failed to marshal chat payload: %w", err)
	}
	resp, err := o.httpClient.Post(url, "application/json", bytes.NewBuffer(body))
	if err != nil {
		return "", nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", nil, fmt.Errorf("ollama returned status %d", resp.StatusCode)
	}

	var result ChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", nil, err
	}

	return result.Message.Content, &result, nil
}

func (o *OllamaClient) ChatStream(messages []map[string]string) (<-chan string, <-chan interface{}, <-chan error) {
	out := make(chan string)
	resCh := make(chan interface{}, 1)
	errCh := make(chan error, 1)

	go func() {
		defer close(out)
		defer close(errCh)
		defer close(resCh)

		url := fmt.Sprintf("%s/api/chat", o.url)
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

			var chunk ChatResponse
			if err := json.Unmarshal([]byte(line), &chunk); err != nil {
				errCh <- fmt.Errorf("failed to unmarshal chunk: %w (data: %s)", err, line)
				return
			}
			if chunk.Message.Content != "" {
				out <- chunk.Message.Content
			}
			if chunk.Done {
				resCh <- &chunk
				break
			}
		}
		if err := scanner.Err(); err != nil {
			errCh <- err
		}
	}()

	return out, resCh, errCh
}

func (o *OllamaClient) GetMetrics() *contracts.ExecutionMetrics {
	return nil // This is a receiver on the client, but we need it on the response
}

func (r *ChatResponse) GetMetrics() *contracts.ExecutionMetrics {
	if r == nil {
		return nil
	}

	// Calculate tokens per second
	var tps float64
	if r.EvalDuration > 0 {
		tps = float64(r.EvalCount) / (float64(r.EvalDuration) / 1e9)
	}

	return &contracts.ExecutionMetrics{
		PromptTokens:          r.PromptEvalCount,
		CompletionTokens:      r.EvalCount,
		TotalDurationUsec:     r.TotalDuration / 1000,
		LoadDurationUsec:      r.LoadDuration / 1000,
		PromptEvalDurationUsec: r.PromptEvalDuration / 1000,
		EvalDurationUsec:       r.EvalDuration / 1000,
		TokensPerSecond:       tps,
	}
}

func (o *OllamaClient) GetEmbeddings(text string) ([]float32, error) {

	payload := map[string]interface{}{
		"model":  o.model,
		"prompt": text,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal embeddings payload: %w", err)
	}
	embeddingUrl := fmt.Sprintf("%s/api/embeddings", o.url)
	resp, err := o.httpClient.Post(embeddingUrl, "application/json", bytes.NewBuffer(body))
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
