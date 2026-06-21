package gateway

// EmbedJob is published by rag-worker to the embed/jobs Pulsar topic.
// The gateway consumes these, calls Ollama, and publishes an EmbedResult.
type EmbedJob struct {
	RequestID        string `json:"request_id"`
	SubQueryIndex    int    `json:"sub_query_index"`
	SubQuery         string `json:"sub_query"`
	EmbeddingModel   string `json:"embedding_model"`
	VectorSize       int    `json:"vector_size"`
	WorkerInstanceID string `json:"worker_instance_id"`
	DeadlineUnix     int64  `json:"deadline_unix"`
}

// EmbedResult is published by embed-gateway to the per-worker result topic
// (persistent://rag-pipeline/embed/results-{WorkerInstanceID}).
type EmbedResult struct {
	RequestID      string    `json:"request_id"`
	SubQueryIndex  int       `json:"sub_query_index"`
	EmbeddingModel string    `json:"embedding_model"`
	Vector         []float32 `json:"vector"`
	Error          string    `json:"error"`
	DurationMs     int64     `json:"duration_ms"`
	GatewayID      string    `json:"gateway_id"`
}
