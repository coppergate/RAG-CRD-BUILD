package models

import (
	"fmt"
	"sync"
)

type ModelSpec struct {
	ID         string // model-id used in requests
	Name       string // actual name on server
	Endpoint   string // URL to server
	Backend    string // "ollama", "openai", etc.
	PromptType string // "llama3", "granite31", etc.
}

type ModelRegistry struct {
	mu     sync.RWMutex
	specs  map[string]ModelSpec
	clients map[string]ChatClient
	
	// Factories for prompt types
	plannerFactories  map[string]func(ChatClient) Planner
	executorFactories map[string]func(ChatClient) Executor
	
	// Backend factories
	backendFactories map[string]func(endpoint, name string) ChatClient
}

func NewModelRegistry() *ModelRegistry {
	return &ModelRegistry{
		specs:             make(map[string]ModelSpec),
		clients:           make(map[string]ChatClient),
		plannerFactories:  make(map[string]func(ChatClient) Planner),
		executorFactories: make(map[string]func(ChatClient) Executor),
		backendFactories:  make(map[string]func(string, string) ChatClient),
	}
}

func (r *ModelRegistry) RegisterModel(spec ModelSpec) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.specs[spec.ID] = spec
}

func (r *ModelRegistry) RegisterPromptType(name string, pf func(ChatClient) Planner, ef func(ChatClient) Executor) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.plannerFactories[name] = pf
	r.executorFactories[name] = ef
}

func (r *ModelRegistry) RegisterBackend(name string, f func(endpoint, modelName string) ChatClient) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.backendFactories[name] = f
}

func (r *ModelRegistry) GetPlanner(modelID string) (Planner, error) {
	r.mu.RLock()
	spec, ok := r.specs[modelID]
	r.mu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("model %s not found in registry", modelID)
	}

	client, err := r.getOrCreateClient(spec)
	if err != nil {
		return nil, err
	}

	r.mu.RLock()
	factory, ok := r.plannerFactories[spec.PromptType]
	r.mu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("unsupported prompt type %s for model %s", spec.PromptType, modelID)
	}

	return factory(client), nil
}

func (r *ModelRegistry) GetExecutor(modelID string) (Executor, error) {
	r.mu.RLock()
	spec, ok := r.specs[modelID]
	r.mu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("model %s not found in registry", modelID)
	}

	client, err := r.getOrCreateClient(spec)
	if err != nil {
		return nil, err
	}

	r.mu.RLock()
	factory, ok := r.executorFactories[spec.PromptType]
	r.mu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("unsupported prompt type %s for model %s", spec.PromptType, modelID)
	}

	return factory(client), nil
}

func (r *ModelRegistry) getOrCreateClient(spec ModelSpec) (ChatClient, error) {
	key := fmt.Sprintf("%s|%s|%s", spec.Backend, spec.Endpoint, spec.Name)
	
	r.mu.RLock()
	client, ok := r.clients[key]
	r.mu.RUnlock()
	
	if ok {
		return client, nil
	}
	
	r.mu.Lock()
	defer r.mu.Unlock()
	
	// Double check
	if client, ok := r.clients[key]; ok {
		return client, nil
	}
	
	factory, ok := r.backendFactories[spec.Backend]
	if !ok {
		return nil, fmt.Errorf("unsupported backend %s", spec.Backend)
	}
	
	client = factory(spec.Endpoint, spec.Name)
	r.clients[key] = client
	return client, nil
}
