# Step-by-Step Implementation Guide
## GPU 0: The "Planning, Embedding & Filtering" Node
### The biggest bottleneck in RAG isn't usually the final answer—it is bad retrieval, messy user prompts, and long context windows slowing down processing.
#### Dedicated GPU 0 entirely to prepping the data.
- Task A: Query Rewriting / Planning: Raw user queries are often terrible for vector search.
  Use a fast, highly-instructed model on GPU 0 to turn "Hey, look up that thing about the q3 budget from last year" into an optimized search payload: "XYZ Corp Q3 2025 financial budget revenue projections".
- Task B: Embedding Generation: Host your embedding model (like bge-m3 or nomic-embed-text) on GPU 0 to instantly vectorize the rewritten query.
  Ta-sk C: Reranking: After pulling documents from your Vector DB (which happens mostly in your system RAM/CPU), pass them through a cross-encoder reranker model loaded on GPU 0. This discards the garbage chunks and only passes the top 3–5 highly relevant snippets to GPU 1.2.

## GPU 1: The "Execution & Generation" Node
### Because GPU 0 did all the heavy lifting filtering out the noise, GPU 1 receives a beautifully clean, condensed prompt.
- The Benefit: Since GPU 1 is only running the generation LLM, it has access to its full 32GB VRAM allocation and isolated compute. You can run a much larger, smarter model (like a 32B or 70B quantized model) completely uninterrupted by the background embeddings or query rewrites.Because it doesn't have to process hundreds of irrelevant context tokens, its Time to First Token (TTFT) will be incredibly fast.

## How to Coordinate This in Python
In your custom RAG pipeline code, you just need to explicitly route your API requests to the respective Ollama ports.
Assuming GPU 0 is on port 11434 and GPU 1 is on port 11435:
```
python

import requests

# Define your independent Ollama endpoints
GPU_0_PLANNER = "http://localhost:11434/api"
GPU_1_EXECUTOR = "http://localhost:11435/api"

def run_rag_pipeline(user_query):
    # STEP 1: Plan and Rewrite Query on GPU 0
    rewrite_prompt = f"Rewrite this search query for a vector database: {user_query}"
    planner_res = requests.post(f"{GPU_0_PLANNER}/generate", json={
        "model": "llama3:8b", "prompt": rewrite_prompt, "stream": False
    }).json()
    optimized_query = planner_res['response']
    
    # STEP 2: Retrieve from Vector DB & Rerank (CPU/RAM + GPU 0)
    # [Your Vector DB Lookup logic here using optimized_query]
    retrieved_chunks = ["chunk1 text...", "chunk2 text..."] 
    
    # STEP 3: Execute Final Answer Generation on GPU 1
    final_prompt = f"Context: {retrieved_chunks}\n\nQuestion: {user_query}\n\nAnswer:"
    
    # We stream this back to the user instantly
    executor_res = requests.post(f"{GPU_1_EXECUTOR}/generate", json={
        "model": "qwen2.5:32b", "prompt": final_prompt, "stream": True
    }, stream=True)
    
    return executor_res
```

### Why this bypasses the lack of NVLinkIn a traditional setup where a model is split across two non-NVLink cards, the GPUs have to talk to each other hundreds of times per second (layer by layer) over the slow PCIe bus.

### With this pipeline approach, GPU 0 talks to GPU 1 exactly once per request—passing a simple text string of clean context over the PCIe bus, which takes fractions of a millisecond.