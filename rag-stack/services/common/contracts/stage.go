package contracts

import (
	"context"
)

// PipelineStage defines the interface for a single stage in the RAG pipeline.
// This interface enables decoupling and independent scaling of pipeline stages.
type PipelineStage interface {
	// Name returns the identifier for this stage (e.g., "ingress", "plan").
	Name() string
	
	// InputTopic returns the Pulsar topic this stage consumes from.
	InputTopic() string
	
	// OutputTopic returns the Pulsar topic this stage produces to.
	OutputTopic() string
	
	// Process executes the business logic for this stage.
	// It takes an InternalRequest and returns a modified request (or error).
	Process(ctx context.Context, msg *InternalRequest) (*InternalRequest, error)
}
