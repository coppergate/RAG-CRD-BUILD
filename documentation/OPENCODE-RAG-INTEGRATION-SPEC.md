# OpenCode ↔ RAG Stack Integration — API Specification

**Date:** 2026-09-27
**Client examined:** `/mnt/hegemon-share/share/code/opencode` @ `b471c2b449`
**Server side:** `rag-stack/services/llm-gateway`, `rag-stack/services/rag-worker`

> **Start at §10.** It records the decisions taken, the verification gates that
> must pass before code is written, and the open concerns. §1-§5 are the protocol
> and topology findings; §7 is the measurement plan.

---

## 1. How the client actually talks to a model

### 1.1 There is no Ollama provider

OpenCode has **no native Ollama adapter**. The only references to "ollama" in the
tree are a test fixture and a UI icon. Local / self-hosted servers are reached
through a **config-declared custom provider** backed by
`@ai-sdk/openai-compatible` (pinned at `2.0.41`, locally patched —
`packages/opencode/package.json:71`, `patches/@ai-sdk%2Fopenai-compatible@2.0.41.patch`).

When a provider entry omits `npm`, opencode defaults it to
`@ai-sdk/openai-compatible` (`packages/opencode/src/provider/provider.ts:1504`
for config-defined providers, `:1278` for catalog-defined ones). So
**"OpenAI Chat Completions" is the wire protocol we must implement.** Nothing else
is negotiable from the client side.

### 1.2 Two runtimes, one wire format

| Runtime | Entry point | Notes |
|---|---|---|
| **AI SDK** (default) | `streamText()` — `packages/opencode/src/session/llm.ts:280` | Vercel AI SDK v3 language-model spec over `@ai-sdk/openai-compatible` |
| **native** (opt-in) | `@opencode-ai/llm` route `openai-compatible-chat` — `packages/llm/src/protocols/openai-compatible-chat.ts:18` | Hand-rolled Effect-based client, `Endpoint.path("/chat/completions")` + `Framing.sse` |

Both issue `POST {baseURL}/chat/completions`. The native runtime is the stricter
of the two (it validates request *and* response against an explicit schema), so
**conform to the native runtime and the AI SDK path works too**.

### 1.3 Model discovery

`GET /v1/models` is **never called** by opencode — grep for `v1/models` across
`packages/opencode/src` and `packages/llm/src` returns nothing. The model list
comes from the models.dev catalog merged with the config's `models` map
(`provider.ts:1493-1560`). The docs reference `/v1/models` only as a human aid
for finding valid ids (`packages/web/src/content/docs/providers.mdx:403`).

**Implication:** `/v1/models` is *optional* for us. Implement it anyway (cheap,
and it makes `curl`-based debugging and future clients work), but model
capabilities must be declared in the user's `opencode.json`.

### 1.4 Streaming is mandatory

The native protocol hard-codes `stream: Schema.Literal(true)`
(`packages/llm/src/protocols/openai-chat.ts:96`) and always sends
`stream_options: { include_usage: true }` (`:360`). A non-streaming
`application/json` response on the main agent loop **will fail schema
validation**. SSE with `data: [DONE]` termination is required
(`packages/llm/src/protocols/shared.ts:247` drops `[DONE]` as a keep-alive).

### 1.5 Tool calling is the protocol

A coding agent is a tool-call loop. Per assistant turn opencode sends every tool
definition (bash, read, write, edit, glob, grep, webfetch, task, todo, plus MCP
and skill tools) and expects `tool_calls` deltas back. Tool results are replayed
as `role: "tool"` messages on the next request. Any gateway that cannot carry
`tools[]` / `tool_calls` / `tool_call_id` end-to-end **cannot host a coding agent**.

---

## 2. Exact wire contract we must implement

### 2.1 Endpoint

```
POST {baseURL}/chat/completions
Content-Type: application/json
Authorization: Bearer <options.apiKey>     # sent when configured; treat as optional
Accept: text/event-stream
```

`baseURL` is whatever the user puts in `opencode.json`, e.g.
`https://rag-code-gateway.hierocracy.home/v1`. Note opencode appends
`/chat/completions` to `baseURL` verbatim — so `baseURL` must already include
the `/v1` segment if we want one.

### 2.2 Request body — fields opencode emits

Source of truth: `packages/llm/src/protocols/openai-chat.ts:91-106` (schema) and
`:344-369` (assembly).

```jsonc
{
  "model": "qwen2.5-coder:32b",          // REQUIRED — the api.id from config
  "messages": [ /* see 2.3 */ ],          // REQUIRED
  "tools": [ /* see 2.4 */ ],             // omitted when empty
  "tool_choice": "auto" | "none" | "required" | { "type": "function", "function": { "name": "..." } },
  "stream": true,                         // ALWAYS true on the agent loop
  "stream_options": { "include_usage": true },
  "store": false,                         // optional, OpenAI-specific
  "reasoning_effort": "minimal|low|medium|high",  // optional
  "max_tokens": 32000,                    // optional
  "temperature": 0.3,                     // optional
  "top_p": 1,                             // optional
  "frequency_penalty": 0,                 // optional
  "presence_penalty": 0,                  // optional
  "seed": 42,                             // optional
  "stop": ["..."]                         // optional
}
```

Unknown fields must be **ignored, not rejected** — the AI SDK path adds
`providerOptions`-derived keys the native schema does not list.

### 2.3 Message shapes — all four roles required

From `packages/llm/src/protocols/openai-chat.ts:66-80`:

```jsonc
// system — content is a plain string
{ "role": "system", "content": "You are opencode…" }

// user — string OR array of parts (text + inline images as data URLs)
{ "role": "user", "content": "fix the failing test" }
{ "role": "user", "content": [
    { "type": "text", "text": "what does this do?" },
    { "type": "image_url", "image_url": { "url": "data:image/png;base64,iVBOR…" } }
] }

// assistant — content may be null when only tool calls were emitted
{ "role": "assistant",
  "content": null,
  "tool_calls": [
    { "id": "call_abc", "type": "function",
      "function": { "name": "read", "arguments": "{\"filePath\":\"/a/b.go\"}" } }
  ],
  "reasoning_content": "…"                // optional, echoed back for interleaved models
}

// tool — one message per tool result, keyed by tool_call_id
{ "role": "tool", "tool_call_id": "call_abc", "content": "package main\n…" }
```

**Critical:** `content` is `string | array` for `user`, and `string | null` for
`assistant`. Our current gateway types it as a bare `string`
(`services/llm-gateway/internal/handlers/openai.go:91`) and will fail to decode
any multipart user message.

### 2.4 Tool definitions

```jsonc
{
  "type": "function",
  "function": {
    "name": "bash",
    "description": "Executes a bash command…",
    "parameters": { "type": "object", "properties": { … }, "required": [ … ] }
  }
}
```

`parameters` is JSON Schema, already normalized by
`ToolSchemaProjection.openAI()`. Pass it through byte-for-byte; do not rewrite it.

### 2.5 Response — SSE frames we must emit

Parsed shape: `packages/llm/src/protocols/openai-chat.ts:132-158`.

```
data: {"choices":[{"delta":{"content":"Looking"},"finish_reason":null}]}

data: {"choices":[{"delta":{"content":" at the test"},"finish_reason":null}]}

data: {"choices":[{"delta":{"reasoning_content":"…"},"finish_reason":null}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","function":{"name":"read","arguments":""}}]},"finish_reason":null}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"filePath\""}}]},"finish_reason":null}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\"/a/b.go\"}"}}]},"finish_reason":null}]}

data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

data: {"choices":[],"usage":{"prompt_tokens":18422,"completion_tokens":96,"total_tokens":18518,"prompt_tokens_details":{"cached_tokens":16384},"completion_tokens_details":{"reasoning_tokens":0}}}

data: [DONE]
```

> Verified against Ollama 0.15.6 in §10.2, with one deviation: it sends the whole
> tool call in a **single** delta rather than fragmenting `function.arguments`.
> Both shapes are legal; handle fragments, but do not expect them here.

Rules the client enforces:

- `choices` is a **required array** on every non-`[DONE]` frame (may be empty on
  the usage-only frame). `delta` and `finish_reason` are nullable.
- Tool-call fragments are accumulated by `index`. `id` and `function.name` may
  arrive once on the first fragment; `function.arguments` is a **string**
  streamed in pieces and must concatenate to valid JSON.
- `finish_reason` ∈ `stop` | `tool_calls` | `length` | `content_filter` — emit
  `tool_calls` whenever the turn ended with tool calls, or opencode will treat
  the turn as finished and never dispatch them.
- Usage arrives on its own trailing frame because `stream_options.include_usage`
  is set. `cached_tokens` and `reasoning_tokens` are optional; report `0` or omit.
- Terminate with `data: [DONE]`, then close.
- Errors *before* the first frame → HTTP status + JSON body
  (`{"error":{"message":…,"type":…}}`). Errors *mid-stream* → emit an SSE frame
  with an `error` object and close; opencode surfaces it via the `onError` hook
  (`session/llm.ts:283`).

### 2.6 Non-streaming path (secondary, still needed)

`generateObject` / `streamObject` are used for structured side-tasks — agent
config generation (`packages/opencode/src/agent/agent.ts:416-435`) and the
"small model" title/summary work. These go through the AI SDK, which sends
`stream: false` and/or `response_format: { type: "json_schema", … }` and expects
a standard non-streamed completion object:

```jsonc
{
  "id": "chatcmpl-…", "object": "chat.completion", "created": 1759000000,
  "model": "qwen2.5-coder:32b",
  "choices": [ { "index": 0, "message": { "role": "assistant", "content": "{…}" },
                 "finish_reason": "stop" } ],
  "usage": { "prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0 }
}
```

Support both `stream: true` and `stream: false` on the same route. If the model
cannot honour `response_format`, fall back to prompt-level JSON coercion — do not
error.

---

## 3. Gap analysis — current `llm-gateway` vs. requirement

`services/llm-gateway/internal/handlers/openai.go` today:

| # | Current behaviour | Why it breaks opencode |
|---|---|---|
| 1 | `Prompt = messages[len-1].Content` (`:240`) — history and system prompt discarded | Agent loses all context, tool results, and its system prompt |
| 2 | `Content string` (`:91`) | Multipart user content (`[{type:text},{type:image_url}]`) fails to decode |
| 3 | No `tools` / `tool_calls` / `tool_call_id` anywhere | Tool loop impossible — this is the hard blocker |
| 4 | Response is non-streaming JSON only; streaming lives on a **WebSocket** at `/v1/rag/chat/stream` with a proprietary `StreamChunk` shape | Native runtime requires `stream:true` + SSE; it will reject the JSON body |
| 5 | `session_id int64` | opencode session ids are opaque strings (`ses_…`) |
| 6 | `finish_reason` hard-coded `"stop"`; no `usage`; non-standard `planning_response` inside `message` | Tool turns never dispatch; cost/context accounting shows zero |
| 7 | `http.MaxBytesReader(w, r.Body, 1<<20)` (`:187`, `:460`) | A coding-agent request is system prompt + tool schemas + file contents; 1 MiB is routinely exceeded |
| 8 | `rag-worker`'s Ollama client is `Chat(messages []map[string]string)` against `/api/chat` with no `tools` field (`services/rag-worker/internal/ollama/client.go:114`) | Even if the gateway accepted tools, the pipeline cannot forward them |
| 9 | Pipeline is `ingress → plan → search → exec` on a single `prompt` string (`pkg/pipeline/pipeline.go`) | Assumes one-shot Q&A, not an N-turn agent loop |

Conclusion: the existing `/v1/chat/completions` is an *OpenAI-shaped* endpoint,
not an OpenAI-*compatible* one. It cannot be incrementally coaxed into hosting
opencode; the agent surface needs its own route set.

---

## 4. Proposed API

Two integration shapes. **They are complementary — Option B is cheap and
low-risk, Option A is the full proxy.** Recommend shipping B first to prove
retrieval quality, then A for transparent whole-fleet coverage.

### Option A — `rag-code-gateway`: faithful OpenAI proxy with retrieval injection

A new service (or a new handler set in `llm-gateway`) that is a **transparent
OpenAI Chat Completions proxy to Ollama**, with a retrieval step spliced in.

#### A.1 Routes

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/chat/completions` | Full OpenAI Chat Completions. Streaming + non-streaming. Retrieval-augmented. |
| `GET` | `/v1/models` | OpenAI model list, projected from Ollama `/api/tags` + our allowlist. Optional but implement. |
| `GET` | `/healthz`, `/readyz` | Existing `common/health` pattern. |

#### A.2 Turn classification — when to retrieve

The single most important design rule. Injecting retrieval on every turn of a
tool loop would poison the context and destroy prompt-cache hits.

```
last message role == "user"   → AUGMENT   (classify, retrieve, inject)
last message role == "tool"   → PASSTHROUGH (no retrieval; the agent is mid-loop)
last message role == "assistant" → PASSTHROUGH
```

Additionally skip retrieval when:
- the request carries `X-RAG-Mode: off`, or
- estimated prompt tokens already exceed `RAG_INJECT_MAX_PROMPT_FRACTION` of the
  model's context (default `0.6`), or
- the user text is shorter than `RAG_MIN_QUERY_CHARS` (default `12`) — "ok",
  "continue", "yes" are not retrieval queries.

#### A.3 Injection mechanics

Retrieved context goes in as a **dedicated system message appended after the
existing system block(s)**, never merged into the user turn:

```jsonc
{ "role": "system",
  "content": "<rag-context source=\"rag-stack\" tags=\"…\" k=\"6\">\n…chunks…\n</rag-context>" }
```

Rationale: opencode owns the user turn, so a separate trailing system message
can be dropped wholesale without rewriting anything the client authored. Cap the
injected block at `RAG_INJECT_MAX_TOKENS` (default `4096`).

> **Caution — this is the expensive option, not the cheap one.** An earlier
> draft claimed a trailing system message is "stable across the tool loop". That
> is wrong in a way that matters on this hardware. A coding agent resends the
> whole conversation each turn, and llama.cpp reuses the KV prefix within its
> slot only while the *front* of the prompt is unchanged. A mutating system block
> invalidates the prefix on **every turn**, forcing a full re-prefill of
> 20-60k tokens.
>
> Tool results append at the *end* of the conversation and therefore preserve the
> cached prefix. That is an independent argument for the `rag_search` tool
> (§4 B.4) over injection — see §10.2 and measurement **M9**. If injection is
> used anyway, keep the block byte-identical for the life of a turn sequence so
> it can at least be cached once.

#### A.4 Control surface — request headers (preferred) and body extensions

opencode can set arbitrary per-request headers two ways:
`provider.<id>.options.headers` in `opencode.json` (static) and the
`chat.headers` plugin hook (dynamic, has `sessionID`). Headers are therefore the
right control channel — they do not perturb the OpenAI body schema.

| Header | Default | Meaning |
|---|---|---|
| `X-RAG-Session` | derived from body hash | Opaque string session id (opencode `ses_…`) |
| `X-RAG-Tags` | `` | Comma-separated tag names or ids scoping retrieval |
| `X-RAG-Include-Global` | `true` | Include untagged/global corpus |
| `X-RAG-Mode` | `auto` | `auto` \| `off` \| `force` |
| `X-RAG-Top-K` | `6` | Chunks to inject |
| `X-RAG-Embedding-Model` | service default | Override embedding model |
| `X-RAG-Project` | `` | Project/repo identifier for corpus partitioning |
| `X-RAG-Agent` | `` | opencode agent name (`plan`, `build`, `general`, …) — set via the `chat.headers` hook. See §5.5 |
| `X-RAG-Profile` | `auto` | `auto` \| `planner` \| `executor` \| `none` — retrieval profile override. `auto` derives it from `X-RAG-Agent`, then the model id |

Mirror the same knobs as optional body fields (`rag: { session, tags, … }`) for
non-opencode clients, and **strip them before forwarding upstream**.

Response headers for observability (opencode ignores unknown ones):

```
X-RAG-Retrieved: 6
X-RAG-Injected-Tokens: 3180
X-RAG-Correlation-Id: <uuid>
X-RAG-Mode-Applied: auto
```

#### A.5 Session mapping

`X-RAG-Session` is an **opaque string**; the RAG DB keys sessions by `int64`.
Add a lookup table rather than trying to parse the id:

```
agent_session(external_id TEXT PRIMARY KEY, session_id BIGINT, source TEXT, created_at TIMESTAMPTZ)
```

`ensureSession` gains an `ExternalID` path: look up → create-on-miss → return
`int64`. This keeps `contracts.InternalRequest.session_id` untouched.

#### A.6 Upstream call

Forward the **entire** normalized body to Ollama's OpenAI-compatible endpoint —
`POST {OLLAMA_URL}/v1/chat/completions` — not `/api/chat`. Ollama 0.15.6 serves
`/v1` and is the only path that accepts `tools` and returns `tool_calls` in
OpenAI shape. Stream the upstream SSE straight through to the client,
re-emitting frames unmodified except for the usage frame (where we may add our
own counters). Do **not** buffer the whole response; opencode's TUI depends on
incremental deltas.

Set `keep_alive: -1` semantics via the Ollama-native option passthrough, and
honour a `STREAM_IDLE_TIMEOUT` (default `300s`) — note the known Go-driver
timeout issue with slow first tokens.

#### A.7 Limits and hygiene

- Body cap: `RAG_MAX_BODY_BYTES`, default **32 MiB** (not 1 MiB).
- No `MaxBytesReader` on the streaming response path.
- Preserve `Authorization` handling: accept and ignore, or validate against a
  static token. Do not forward opencode's key to Ollama.
- `X-Accel-Buffering: no` + `Cache-Control: no-cache` on SSE responses so any
  ingress in front does not buffer.

#### A.8 opencode client config

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "rag-stack": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "RAG Stack (hierophant)",
      "options": {
        "baseURL": "https://rag-code-gateway.hierocracy.home/v1",
        "apiKey": "unused",
        "headers": {
          "X-RAG-Include-Global": "true",
          "X-RAG-Top-K": "6"
        }
      },
      "models": {
        "qwen2.5-coder:32b": {
          "name": "Qwen2.5 Coder 32B (RAG)",
          "tool_call": true,
          "limit": { "context": 65536, "output": 16384 }
        }
      }
    }
  }
}
```

`tool_call` defaults to `true` and `temperature` defaults to `false`
(`provider.ts:1521-1524`) — set `"temperature": true` explicitly if we want
opencode to send it.

---

### Option B — retrieval API + opencode plugin (no proxy)

opencode exposes first-class injection seams (`packages/plugin/src/index.ts:222-340`).
A ~150-line plugin plus a small read-only HTTP API gives us RAG without
reimplementing the OpenAI protocol at all, and **opencode keeps ownership of the
tool loop, streaming, caching and retries**.

Hooks worth using:

| Hook | Use |
|---|---|
| `experimental.chat.system.transform` (`:291`) | Append the `<rag-context>` block to `output.system[]` — exactly the Option A injection, client-side |
| `experimental.chat.messages.transform` (`:282`) | Alternative: rewrite the message array |
| `chat.message` (`:234`) | Fire-and-forget ingest of the user turn into the RAG corpus |
| `tool.execute.after` (`:274`) | Ingest tool output (file reads, test failures) as session memory |
| `tool` (`:227`) | Register a first-class `rag_search` tool so the **model decides** when to retrieve |
| `chat.headers` (`:257`) | Attach `X-RAG-Session` when running Option A |

#### B.1 Routes to add (server side)

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/rag/retrieve` | Synchronous retrieval. The core primitive. |
| `POST` | `/v1/rag/ingest/turn` | Async: record a user turn / tool result as session memory |
| `GET` | `/v1/rag/tags` | Enumerate tags for UI/config |
| `GET` | `/healthz` | Health |

#### B.2 `POST /v1/rag/retrieve`

Must be **fast and synchronous** — it sits on the critical path of every user
turn.

**Latency budget is a requirement, not a measurement.** See §7 (M1-M3): no p95 exists
today for either the Pulsar path or a direct path, and the stack is not deployed,
so neither can be measured yet. Set the budget at **p95 < 800 ms** and treat
beating it as an acceptance criterion.

The reason this endpoint should not reuse the existing Pulsar request path is
**shape, not latency**: `ingress → plan → search → exec` produces a finished
*answer* via two LLM calls (planner + executor). There is no way to ask it for
chunks. A retrieval primitive needs query-embed + vector-search and nothing else.

That direct path is largely already reachable:

- **Vector search** — Qdrant's own HTTP API is already proxied, no broker
  involved (`services/rag-admin-api/cmd/admin-api/main.go:61` →
  `QDRANT_DIRECT_URL`, default `https://qdrant.rag-system.svc.cluster.local:6333`).
- **Query embedding** — `embed-gateway` is **Pulsar-only** (it subscribes to a
  jobs topic and exposes no HTTP routes; `services/embed-gateway/cmd/gateway/main.go:86`).
  So either add a synchronous HTTP route to it, or call Ollama's embed endpoint
  directly the way `rag-worker` already does
  (`services/rag-worker/internal/ollama/client.go:255`, `GetEmbeddings`).

Whichever of those two we pick should be decided by M2/M3 in §7, not
assumed.

Request:

```jsonc
{
  "query": "why does the ingestion worker drop chunks over 8k tokens",
  "session": "ses_7f3a…",            // opaque string, optional
  "project": "complete-build",        // optional
  "tags": ["rag-stack", "go"],        // names or ids, optional
  "include_global": true,
  "top_k": 6,
  "max_tokens": 4096,                 // budget for the returned block
  "embedding_model": "nomic-embed-text",
  "include_memory": true,             // fold in memory-controller results
  "format": "block"                   // "block" | "chunks"
}
```

Response:

```jsonc
{
  "correlation_id": "0f1c…",
  "session_id": 1421,
  "block": "<rag-context …>…</rag-context>",   // present when format=block
  "chunks": [
    { "id": "…", "score": 0.83, "source": "rag-stack/services/rag-worker/pkg/pipeline/pipeline.go",
      "tag": "rag-stack", "start_line": 612, "end_line": 664, "text": "…" }
  ],
  "memory": [ { "memory_type": "rule", "summary": "…", "content": "…" } ],
  "tokens": 3180,
  "truncated": false,
  "timings_ms": { "embed": 61, "search": 142, "assemble": 4, "total": 211 }
}
```

Errors: standard HTTP status + `{"error":{"message":…,"code":…}}`. The plugin
must treat **any** failure as "inject nothing and continue" — retrieval is never
allowed to break the coding session.

#### B.3 `POST /v1/rag/ingest/turn`

Fire-and-forget (`202 Accepted`), publishes to Pulsar, returns immediately.

```jsonc
{
  "session": "ses_7f3a…",
  "project": "complete-build",
  "kind": "user_turn" | "tool_result" | "assistant_turn",
  "tool": "read",                     // when kind=tool_result
  "text": "…",
  "metadata": { "path": "…", "agent": "build", "model": "qwen2.5-coder:32b" }
}
```

#### B.4 `rag_search` as a model-driven tool

Registering a tool is strictly better than blind injection for a coding agent:
the model asks only when it needs to, and the result lands as a `role:"tool"`
message that opencode already renders and caches.

```jsonc
{ "name": "rag_search",
  "description": "Search the RAG corpus for design docs, prior decisions and code context outside the current repo.",
  "parameters": { "type": "object",
    "properties": {
      "query":  { "type": "string" },
      "tags":   { "type": "array", "items": { "type": "string" } },
      "top_k":  { "type": "integer", "default": 6 }
    },
    "required": ["query"] } }
```

Backed by the same `POST /v1/rag/retrieve`.

---

## 5. Dual-model planner/executor across the two V100s

### 5.1 opencode is already a planner/executor architecture

This requirement is mostly **already satisfied by the client**, and the discovery
changes the plan more than anything else in this document.

- **`plan` agent** — `mode: "primary"`, all edit tools denied, may write plan
  `.md` files, holds `plan_exit` (`packages/opencode/src/agent/agent.ts:157-179`)
- **`build` agent** — `mode: "primary"`, full tool permissions (`:142-155`)
- **Every agent takes its own model** — `model: { providerID, modelID }`,
  optional per agent (`:45-50`)
- **`general` / `explore` subagents** — inherit the parent's model unless their
  own config overrides it (`packages/opencode/src/tool/task.ts:181-184`)
- **`small_model`** — a third role, used for conversation titles and summaries
  (`provider.ts:1938-1946`, consumed at `session/prompt.ts:219-230`)

So the planner/executor split is a **client configuration concern, not a server
feature**. We expose two model ids; opencode routes between them per agent.
**Do not build model routing into the gateway** — it would fight the client.

### 5.2 The nesting hazard — the one thing that must change

`llm-gateway`'s `HandleChatCompletions` sets `PlannerModel` *and* `ExecutorModel`
both to `req.Model` (`openai.go:259-260`), and `rag-worker` then runs its own
`handlePlan → handleExec` sequence with two separate LLM calls.

If opencode's plan/build split sits on top of that, you get **two nested
planner/executor layers** — up to four distinct model identities for a single
user turn, on two cards.

> **Rule: exactly one layer owns the split, and it is opencode.**
> Coding-agent traffic must be **single-model passthrough** — the model named in
> the request is the only model that runs, with no internal planner hop.

This is a hard requirement on Option A, and it is an independent reason not to
graft the agent route onto the existing Pulsar pipeline (§3, §4 B.2).

### 5.3 Residency budget: exactly two models, both pinned

Known GPU state: two identical V100 32GB, **no NVLink** (SYS interconnect),
currently ~49/64GiB used with one model per card.

| Role | Card | Driven by |
|---|---|---|
| planner | 0 | opencode `plan` agent + its subagents |
| executor | 1 | opencode `build` agent |

Constraints that follow:

1. **No third model.** Any third distinct model id forces an eviction and both
   cards begin thrashing. The budget is two, full stop.
2. **`small_model` must resolve to one of the two.** Default resolution matches
   on model *family* against `["gemini-flash", "gpt-nano", "claude-haiku"]`
   (`provider.ts:2048`). None of our models will match, so `getSmallModel`
   returns `undefined` and opencode falls back to the session's main model
   (`session/prompt.ts:219-221`). **That default is the safe behaviour — do not
   "fix" it** by pointing `small_model` at a third model. If set explicitly, set
   it to the planner.
3. **Leave subagent models unset.** `task.ts:181` inherits the parent's model.
   Overriding `explore`/`general` to a third model breaks the budget.
4. **`keep_alive: -1`** on both models so neither is evicted between turns.
5. **`OLLAMA_SCHED_SPREAD`** to keep one model per card. Note the context var is
   `OLLAMA_CONTEXT_LENGTH`, not `OLLAMA_NUM_CTX`.

### 5.4 Context pressure is the real risk, not routing

A coding-agent prompt is system prompt + every tool schema + file contents +
accumulated tool results. That is qualitatively larger than the current
pipeline's single-prompt workload. With the executor already at 65536 context and
~49/64GiB in use per card, **adding real coding-agent context is the most likely
way to OOM** — well before any routing concern bites.

- Declare honest `limit.context` / `limit.output` per model in `opencode.json`.
  opencode drives compaction off these values; a wrong number produces silent
  overflow instead of compaction.
- Keep `RAG_INJECT_MAX_TOKENS` small (default 4096) and count it against the
  same budget.
- Measure peak resident VRAM per card under a real `opencode run` before
  trusting both models at 65536. This is a prerequisite, not a follow-up.

### 5.5 Role-aware retrieval — a capability this unlocks

Because every request identifies the model — and, via a header or hook, the
agent — retrieval can differ by role. This is a real improvement over role-blind
injection:

| Role | Retrieval profile |
|---|---|
| `plan` / planner | Broad, architectural: higher `top_k`, design docs and summaries, whole-section spans, memory rules and prior decisions |
| `build` / executor | Narrow, precise: low `top_k`, exact code spans with tight line ranges, no prose |
| `small_model` (titles) | **None** — skip retrieval entirely |

Plumbing note: the agent name is available in the `chat.params` and
`chat.headers` hooks (`packages/plugin/src/index.ts:248,258`) but **not** in
`experimental.chat.system.transform` (`:291`, which receives only
`{ sessionID, model }`).

- **Option A:** stamp `X-RAG-Agent: plan|build` from the `chat.headers` hook; the
  gateway keys its profile off that, falling back to the model id.
- **Option B:** read the agent in `chat.params`, cache it by `sessionID`, use it
  in `system.transform` — or simply key off `model`, which is always present.

Add to the §4 A.4 header table: `X-RAG-Agent`, `X-RAG-Profile`.

### 5.6 Net effect on the plan

| Item | Change |
|---|---|
| **Option B** (plugin + `/v1/rag/retrieve`) | **Unchanged, and now more valuable.** It is model- and role-aware for free and never touches model selection. Still ship first. |
| **Option A** (`rag-code-gateway`) | **New hard requirement:** single-model passthrough, no internal planner hop. Add `X-RAG-Agent` / `X-RAG-Profile`. |
| `POST /v1/rag/retrieve` | Add `profile: "planner" \| "executor" \| "auto"` to the request body. |
| Existing `llm-gateway` pipeline | **Unaffected.** Keep its internal planner/executor split for rag-explorer and the Flutter UI. Simply never route coding-agent traffic through it. |
| `rag-worker` tool-capable Ollama client | **Still worth doing, but demoted.** It was a prerequisite for a "retrieval-augmented planner"; since opencode now owns planning, it is only needed if we want the *pipeline itself* to call tools. |
| **New work** | VRAM/residency validation under real coding-agent load; per-agent model config in `opencode.json`; honest `limit.context` values. |

### 5.7 Client config for the split

Concrete, using the models actually seeded on the inference PVC. Rationale in §5.8.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "small_model": "rag-stack-cpu/llama3.2:3b",
  "provider": {
    "rag-stack": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "RAG Stack (hierophant)",
      "options": {
        "baseURL": "https://rag-code-gateway.hierocracy.home/v1",
        "apiKey": "unused"
      },
      "models": {
        "qwen3:32b": {
          "name": "Planner — Qwen3 32B (V100 #0)",
          "tool_call": true,
          "temperature": true,
          "reasoning": true,
          "interleaved": "reasoning",
          "limit": { "context": 32768, "output": 8192 }
        },
        "devstral-small-2:24b": {
          "name": "Executor — Devstral Small 2 24B (V100 #1)",
          "tool_call": true,
          "temperature": true,
          "limit": { "context": 65536, "output": 16384 }
        }
      }
    },
    "rag-stack-cpu": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "RAG Stack (CPU, titles only)",
      "options": { "baseURL": "https://ollama-planner-cpu.hierocracy.home/v1", "apiKey": "unused" },
      "models": {
        "llama3.2:3b": { "name": "Titles (CPU)", "tool_call": false,
                         "limit": { "context": 4096, "output": 512 } }
      }
    }
  },
  "agent": {
    "plan":  { "model": "rag-stack/qwen3:32b" },
    "build": { "model": "rag-stack/devstral-small-2:24b" }
  }
}
```

Three things in that file are load-bearing and easy to get wrong:

1. **`temperature: true`** — defaults to `false` for config-declared models
   (`provider.ts:1521`), so opencode will not send temperature unless asked.
2. **`interleaved: "reasoning"`** on Qwen3 — Ollama's field name, verified in
   §10.2. Add `"reasoning_effort": "none"` under `options` to switch thinking off
   entirely (8× fewer output tokens; see §10.2).
3. **`limit.context`** — opencode drives compaction off this value. It must match
   the pod's real `OLLAMA_CONTEXT_LENGTH`, or you get silent overflow instead of
   compaction. The `32768` above is **aspirational** and does not match the
   deployed 16384; see the §5.8 blocking issue.

Subagent models are deliberately absent so `explore` / `general` inherit the
parent's model (§5.3 rule 3).

---

### 5.8 Model selection, and where CPU inference belongs

#### Deployed state as of 2026-09-27

| Card | Helm release | Model | `OLLAMA_CONTEXT_LENGTH` | Endpoint |
|---|---|---|---|---|
| 0 | `ollama-llama3` | `llama3.1` | **16384** | `ollama` (planner) |
| 1 | `ollama-qwen32b` † | `devstral-small-2:24b` q4_K_M | 65536 | `ollama-code` (executor) |

† Release name is a deliberate misnomer — renaming would create a fresh PVC and
discard every seeded model (`values-devstral.yaml:1-12`).

Seeded on the PVC and therefore one API call away, no download:
`devstral-small-2:24b`, `qwen3:32b`, `qwen2.5:32b`, `granite3.1-dense:8b`,
`llama3.1`, `llama3.2:3b`, `nomic-embed-text`, `mxbai-embed-large`.

#### Executor — keep `devstral-small-2:24b`

No change recommended. 68.0% SWE-bench Verified, Apache 2.0, explicitly trained
for agentic tool use, and it already runs at 65536 context in ~27/32GB. The
selection rationale in `values-devstral.yaml:14-45` (sm_70 has no FP8 path; a
4-bit 123B requant is ~62GB against split non-NVLinked VRAM) still holds on
those two grounds. **Its third argument does not:** the "~30s driver cutoff" is a
test-harness artifact, not an infrastructure limit — `rag-stack/tests/main.go:30`
sets 30s on the *admin* client, while the RAG chat client at `:39` is 1800s. That
comment should be corrected so nobody re-derives an infra constraint from it. The
model choice is unaffected. This is what opencode's `build` agent points at.

#### Planner — move `llama3.1` → `qwen3:32b`

**The `plan` agent is not a text reasoner.** Its permission block denies only
`edit`; `read`, `grep`, `glob`, `list` and `bash` all inherit from defaults and
remain allowed (`agent/agent.ts:157-179`). Plan mode is a read-only *agent* that
hammers tools to survey a codebase. So the planner needs strong tool-calling
just as much as the executor does — which is precisely llama3.1's weak point.

`qwen3:32b` is already seeded, ~20GB at q4_K_M, materially better at tool
calling, and has native thinking mode. `values-devstral.yaml:41-43` already
accepted a ~26/32 envelope for it.

> **Trap:** for config-declared openai-compatible providers, `interleaved`
> defaults to `false` unless the model id contains `"deepseek"`
> (`provider.ts:1545-1547`). Qwen3's thinking tokens will leak into visible
> assistant output unless `opencode.json` sets **both** `"reasoning": true` and
> `"interleaved": "reasoning"` — Ollama's actual field name, confirmed in §10.2.

Safer alternative if the reasoning plumbing proves annoying: **`qwen2.5:32b`**,
also seeded, no thinking mode, nothing to plumb, slightly weaker.

#### Blocking issue: 16384 context is too small for either role

opencode's system prompt plus ~10 tool schemas is roughly **5-10k tokens before
a single file is read**. At 16384 the planner has two or three file reads before
compaction kicks in. Plan mode is the role that synthesizes across many files,
so the current 16384-planner / 65536-executor asymmetry is arguably backwards
for this workload.

**This matters more than which 32B is chosen.** It is also a VRAM question —
raising planner context costs KV on a card that would sit at ~23-24/32 with
qwen3 resident. Treat it as a measurement (§7 M4), not a guess. Do not set
`limit.context` in `opencode.json` above the pod's real
`OLLAMA_CONTEXT_LENGTH`.

#### CPU inference — three yes, two no

| Path | CPU? | Reasoning |
|---|---|---|
| **Query / document embedding** | **Yes — already shipped** | `values-embed.yaml` is already `gpu.enabled: false` at 500m-2Gi. A single prefill-only forward pass on a 137M model. Serves the §4 B.2 retrieval budget at zero VRAM cost, and means that path already has a CPU embed endpoint to call. |
| **`small_model` (titles, summaries)** | **Yes — recommended** | Dissolves the §5.3 three-model problem outright: titles stop competing for VRAM. `llama3.2:3b` is seeded and `values-planner-cpu.yaml` already defines the pod. |
| **Cross-encoder rerank** (top-20 → top-6) | **Maybe** | e.g. `bge-reranker-base` (278M), prefill-only, ~20 short passes. Would sharpen the executor's narrow retrieval profile. Not seeded, and unmeasured — speculative. |
| **Planner or executor** | **No** | See below. |
| **Retrieve / no-retrieve classification** | **No** | The §4 A.2 heuristics (message role, length threshold) are cheaper and more predictable than a model. |

**Why CPU cannot host either agent role.** `values-planner-cpu.yaml:3` documents
`llama3.2:3b` at ~3-6 tok/s on 8 CPUs. But generation throughput is not the
blocker — **prefill is.** A coding-agent prompt is 10-30k tokens, and CPU prefill
puts the *first* token minutes away on every turn. It is dead on arrival
regardless of model size — no client timeout needs to be involved. This holds for any CPU model, not just the 3B.

**Caveat on the CPU `small_model`.** opencode's title generation sends the
**whole conversation**, not just the first message — `session/prompt.ts:219-230`
passes `...msgs` after the "Generate a title" instruction. So prefill grows with
session length. It is a background task that does not block the TUI, so 10-30s
is tolerable; a 20k-token conversation would not be. Either cap the input or
accept late-session slowness. Measure it (§7 M5) before assuming it is free.

#### Placement caution

CPU inference is memory-bandwidth-bound. `values-planner-cpu-worker.yaml:86`
targets `role: storage-node` — the same nodes as Qdrant, Postgres and Pulsar,
where NUMA 0 has no spare threads. Running CPU inference there steals bandwidth
from exactly the services sitting on the retrieval critical path.

- Latency-adjacent CPU work → `values-planner-cpu.yaml` (`role: inference-node`,
  bare-metal inference-0).
- Batch / background only → the `-worker` variant.

---

## 6. Recommendation

> Superseded in part by **§10.1**, which records the decisions actually taken:
> Option B with *both* the tool and injection paths, plugin in
> `rag-stack/clients/opencode-plugin/`, all three corpus scopes. The ordering
> below still holds; the gates in §10.2 come before any of it.

1. **Ship Option B first.** `POST /v1/rag/retrieve` is the only genuinely new
   server-side capability, vector search is already reachable over plain HTTP,
   and it carries zero protocol risk. (Query embedding needs one new synchronous
   call path — see §4 B.2 — because `embed-gateway` is Pulsar-only today.) The plugin registers `rag_search` **and**
   does a conservative `system.transform` injection. This gets real
   retrieval-quality signal from a live coding agent in days, not weeks.
2. **Then build Option A** as `rag-code-gateway` — a separate service, not new
   routes on `llm-gateway`. The existing handler's Pulsar round-trip,
   single-prompt contract, and `int64` session identity are all wrong for a
   streaming tool loop; sharing the process would only couple them.
3. **Let opencode own the planner/executor split** (§5.2). Whatever we build for
   coding-agent traffic is single-model passthrough. Validate the two-model VRAM
   budget under real load before wiring both agents up.
4. **Leave `llm-gateway` alone.** Its `/v1/rag/chat` + WebSocket surface serves
   rag-explorer and the Flutter UI correctly. Only fix the `/v1/chat/completions`
   route's honesty problem: either make it conformant or rename it to
   `/v1/rag/chat/openai-shaped` so nobody points an OpenAI client at it by
   mistake.
5. **`rag-worker` needs a tool-capable client eventually** if the pipeline is
   ever to sit inside an agent loop. `internal/ollama/client.go` must move from
   `[]map[string]string` / `/api/chat` to a typed message struct against
   `/v1/chat/completions`. That is a prerequisite for Option A's
   "retrieval-augmented planner" mode and is worth doing on its own.

---

## 7. Measurement plan — run these as soon as the stack is up

Every number in this document is a **budget, not an observation.** Nothing here
has been measured, and several decisions above are explicitly deferred to the
measurements below. Stating that plainly so no budget gets read as a finding.

### 7.1 What exists today

Instrumentation, and only instrumentation:

| Metric | Emitted by |
|---|---|
| `gateway_request_duration_ms` | `services/llm-gateway/internal/handlers/openai.go:66` |
| `worker_task_duration_ms` | `services/rag-worker/pkg/pipeline/pipeline.go:50` |
| `worker_llm_duration_ms` | `services/rag-worker/pkg/pipeline/pipeline.go:54` |
| `qdrant_op_duration_ms` | `services/qdrant-adapter/cmd/adapter/main.go:51` |
| `db_query_duration_ms` | `services/db-adapter/cmd/adapter/main.go:49` |

**What does not exist:**

- No recorded percentiles anywhere in the repo, for the Pulsar path or any other.
- No load or latency harness under `rag-stack/tests/` — the suite is functional
  (correctness, sad-path, contract, cross-model), with no timing assertions.
- ~~No live data: the `rag-system` namespace is empty and the stack is not
  deployed, so these histograms have never been scraped for this purpose.~~
  **Struck 2026-09-27 — this was already false when written.** The stack *is*
  deployed: 14 pods in `rag-system`, all `1/1 Running`, with uptimes of 4d5h-7d
  that predate this document by four days. Verified via
  `/home/k8s/kube/kubectl get pods -n rag-system` on hierophant. **M0 is
  therefore runnable now**, and whether the histograms are actually scraped is
  an open question to answer, not a known negative.

  What *is* true is that the **corpus** is empty — Qdrant reports
  `{"result":{"collections":[]}}` — because the `ingest-codebase-s3` Job sat in
  `Init:0/1` for four days on a `configmap "ingest-s3-script" not found` that
  exists nowhere in the repo. See §10.4 and OPERATIONS.md §15.3.

  Two traps that made "not deployed" look plausible, recorded so the conclusion
  is not reached again: Traefik's default 404/500 bodies are identical whether a
  route is unwired or a backend is sick, so HTTP probing cannot establish
  deployment state; and Qdrant serves **HTTPS only** on 6333, so a plain `http://`
  probe returns an empty body and reads as a dead service.
- No VRAM or context-headroom figures under agentic load. The VRAM arithmetic in
  `values-devstral.yaml` is a calculation from published weight sizes, not an
  observation of a running pod.

**The two numbers that do exist, and what they are not:**

- `rag-stack/tests/go-e2e-driver.log` — `21.916181254s` to a correct answer.
  That is ingestion-completion polling + planner LLM + search + executor LLM.
  It says nothing about retrieval-only cost and nothing about broker overhead.
- `documentation/REFACTORING_PLAN.md:1228-1229` — alert thresholds of P95
  `worker_task_duration_ms` > 30 s and `gateway_request_duration_ms` > 5 s.
  Chosen alarm points, not observations.

### 7.2 The measurements

Ordered by what unblocks the most downstream decisions. **M0 is a prerequisite
for all of them.**

| # | Measurement | Unblocks | Method |
|---|---|---|---|
| **M0** | Confirm the histograms above are actually being scraped and visible in Grafana | everything | Deploy, then query each metric name. A metric that is registered but never scraped looks identical to a fast one. |
| **M1** | P50/P95 of `gateway_request_duration_ms` on the existing Pulsar path | §4 B.2 transport choice | N≥200 `POST /v1/rag/chat` with a fixed short prompt and pinned model |
| **M2** | Non-inference overhead per request | §4 B.2, §6 rec. 1 | `worker_task_duration_ms` − `worker_llm_duration_ms`. The remainder is the honest upper bound on broker + search + DB cost. |
| **M3** | Floor for a direct retrieval path | §4 B.2 | Bare `curl` against `QDRANT_DIRECT_URL` search, plus a bare Ollama `/api/embed` call. Sum = the floor. |
| **M4** | Peak resident VRAM per card, and real context headroom, under a live `opencode run` | §5.3, §5.4, §5.8 planner-context decision, every `limit.context` value | `nvidia-smi` sampled through a multi-tool task on each agent. Record prompt tokens per turn from the usage frames. |
| **M5** | CPU `small_model` title latency vs. conversation length | §5.8 CPU `small_model` recommendation | Time title generation at ~1k, ~5k, ~20k token conversations on `llama3.2:3b` CPU |
| **M6** | Model-load / eviction behaviour across the two cards | §5.3 residency budget | Drive a plan→build→plan session and watch Ollama logs for loads and evictions. Zero evictions is the pass condition. |
| **M7** | Retrieval quality by role | §5.5 profiles | Once Option B is live: same task with planner-profile vs executor-profile vs no retrieval, scored by hand |
| **M8** | Subagent serialisation under `OLLAMA_NUM_PARALLEL=1` | §10.3 parallelism decision | Drive a turn that spawns 3 `explore` subagents; compare wall-clock against 3 sequential turns. Then repeat at `NUM_PARALLEL=2` and record effective per-slot context. |
| **M9** | KV prefix reuse across turns, with and without injection | §4 A.3, §10.2 — whether injection is affordable at all | Compare `prompt_eval_duration` / `prompt_eval_count` across consecutive turns of one session: (a) tool-only retrieval, (b) mutating injected system block. Flat prefill on (a) and growing prefill on (b) confirms the concern. |

### 7.3 Decisions these measurements settle

- **If M2 lands well inside the 800 ms budget**, a synchronous HTTP route on
  `embed-gateway` over the existing bus is the simpler build, and the
  "bypass Pulsar" framing in §4 B.2 should be dropped entirely.
- **M4 decides the planner context**, and therefore whether `qwen3:32b` at a
  raised `OLLAMA_CONTEXT_LENGTH` fits card 0 at all. Until M4 exists, the
  `32768` in §5.7 is aspirational and must not be deployed as a `limit.context`
  above the pod's actual setting.
- **M5 decides whether the CPU `small_model` is viable**, or whether titles
  should fall back to the planner (the safe default described in §5.3 rule 2).
- **M6 validates the two-model budget.** Any eviction means the residency plan
  is wrong and one of the §5.3 constraints is being violated.

### 7.4 Harness

There is no timing harness today. The cheapest thing that produces M1-M3 is a
small Go or Python driver alongside the existing `rag-stack/tests/` suite that
issues N fixed requests and reports percentiles — not a new framework. M4-M6
need a real `opencode run` against the gateway, so they land after Option A or
at least after a passthrough stub exists.

---

## 8. Conformance checklist

Drive these against the real client, not curl alone.

- [ ] `POST /v1/chat/completions` with `stream:true` returns SSE; every frame has a `choices` array; stream ends `data: [DONE]`
- [ ] Multi-part user content (`text` + `image_url` data URL) decodes
- [ ] `assistant` message with `content:null` + `tool_calls[]` round-trips
- [ ] `role:"tool"` + `tool_call_id` accepted and forwarded
- [ ] Tool-call arguments streamed in fragments concatenate to valid JSON
- [ ] `finish_reason:"tool_calls"` emitted on tool turns; `"stop"` on text turns
- [ ] Trailing usage-only frame present when `stream_options.include_usage` is set
- [ ] `stream:false` + `response_format: json_schema` returns a valid completion object (`generateObject` path)
- [ ] Unknown request fields ignored, not 400'd
- [ ] Request bodies > 1 MiB accepted (target 32 MiB)
- [ ] Retrieval skipped when last message role is `tool` (verify via `X-RAG-Mode-Applied`)
- [ ] Retrieval failure degrades to passthrough, never a 5xx to the client
- [ ] `GET /v1/models` returns ids matching the `opencode.json` `models` map
- [ ] **Single-model passthrough:** the model named in the request is the only model that runs — no internal planner hop (§5.2)
- [ ] Exactly two distinct models resident across the run; no eviction observed in Ollama logs
- [ ] `small_model` resolves to the planner or to the session model — never to a third model
- [ ] Retrieval profile switches with `X-RAG-Agent` (broad for `plan`, narrow for `build`, none for titles)
- [ ] Peak VRAM per card measured under a real `opencode run`, both models at their declared context
- [ ] End-to-end: `opencode run "…"` completes a multi-tool task through the gateway
- [ ] End-to-end: a session that enters plan mode, plans, then exits to build mode keeps both cards warm and switches models without a reload stall
- [ ] `limit.context` in `opencode.json` matches each pod's real `OLLAMA_CONTEXT_LENGTH` (never higher)
- [ ] Qwen3 thinking tokens do not leak into visible output (`reasoning` + `interleaved` both set — §5.8)
- [ ] `go vet ./...` clean; built via Kaniko through `build.sh`

---

## 9. Key source references

**Client**
- `packages/opencode/src/session/llm.ts:280` — `streamText` call, default runtime
- `packages/opencode/src/provider/provider.ts:1504` — `@ai-sdk/openai-compatible` default for config providers
- `packages/opencode/src/provider/provider.ts:362-365` — `options.endpoint`/`options.baseURL` resolution
- `packages/llm/src/protocols/openai-compatible-chat.ts:18-23` — route: `/chat/completions` + SSE
- `packages/llm/src/protocols/openai-chat.ts:91-106` — request body schema
- `packages/llm/src/protocols/openai-chat.ts:66-80` — message union (all four roles)
- `packages/llm/src/protocols/openai-chat.ts:132-158` — stream event schema
- `packages/llm/src/protocols/openai-chat.ts:344-369` — body assembly
- `packages/llm/src/protocols/shared.ts:247` — `[DONE]` handling
- `packages/plugin/src/index.ts:222-340` — plugin hook surface
- `packages/opencode/src/agent/agent.ts:416-435` — `generateObject`/`streamObject` non-streaming path
- `packages/web/src/content/docs/providers.mdx:375-407` — custom local provider config recipe
- `packages/opencode/src/agent/agent.ts:45-50` — per-agent `model: { providerID, modelID }`
- `packages/opencode/src/agent/agent.ts:142-179` — built-in `build` and `plan` agents, both `mode: "primary"`
- `packages/opencode/src/tool/task.ts:181-184` — subagents inherit the parent model unless overridden
- `packages/opencode/src/provider/provider.ts:1938-1946`, `:2048` — `small_model` resolution and family priority
- `packages/opencode/src/session/prompt.ts:219-230` — small-model fallback to the session model, title generation
- `packages/plugin/src/index.ts:248,258` — `agent` name exposed in `chat.params` / `chat.headers` (absent from `system.transform`)

**Server**
- `rag-stack/services/llm-gateway/internal/handlers/openai.go:79-104` — current request structs
- `rag-stack/services/llm-gateway/internal/handlers/openai.go:240` — last-message-only prompt extraction
- `rag-stack/services/llm-gateway/cmd/gateway/main.go:69-71` — route registration
- `rag-stack/services/rag-worker/internal/ollama/client.go:114` — `Chat([]map[string]string)`, `/api/chat`, no tools
- `rag-stack/services/rag-worker/pkg/pipeline/pipeline.go` — `ingress → plan → search → exec` stages
- `rag-stack/contracts/rag_stack.proto:9-36` — `InternalRequest`, `StreamChunk`

**Inference topology**
- `rag-stack/infrastructure/ollama/values-devstral.yaml:1-45` — executor card: model choice, sm_70 constraints, quant and VRAM arithmetic
- `rag-stack/infrastructure/ollama/values-devstral.yaml:111-112` — executor `OLLAMA_CONTEXT_LENGTH=65536`
- `rag-stack/infrastructure/ollama/values.yaml:356-366` — planner card: `OLLAMA_CONTEXT_LENGTH=16384`, `MAX_LOADED_MODELS=2`
- `rag-stack/infrastructure/ollama/values-qwen32b.yaml:96-109` — prior executor values (16384, superseded by devstral)
- `rag-stack/infrastructure/ollama/values-embed.yaml:22-24,64-68` — embeddings already CPU-only
- `rag-stack/infrastructure/ollama/values-planner-cpu.yaml:3` — measured CPU throughput note (~3-6 tok/s, 8 CPUs); `role: inference-node`
- `rag-stack/infrastructure/ollama/values-planner-cpu-worker.yaml:86` — `role: storage-node` variant (batch only — see §5.8 placement)
- `rag-stack/infrastructure/ollama/seed-models.sh` — seeded model inventory

---

## 10. Pre-implementation gates, decisions, and open concerns

### 10.1 Decisions taken (2026-09-27)

| Question | Decision |
|---|---|
| First deliverable | **Option B — both the `rag_search` tool *and* `system.transform` injection.** Ship them together, behind independent flags, so M9 can compare them on real traffic. |
| Plugin location | **New package in this repo: `rag-stack/clients/opencode-plugin/`.** Versioned with the stack, survives upstream opencode updates, referenced from `opencode.json` by path. Nothing is written into the `opencode` checkout. |
| Corpus scope | **All three:** complete-build docs + configs, complete-build Go sources, and the opencode TypeScript sources. |

Consequences of the injection decision: §4 A.3's caution applies in full. Put the
injection path behind `RAG_INJECT_ENABLED` (default **off**) and the tool path
behind `RAG_TOOL_ENABLED` (default **on**), so the expensive mode is opt-in until
M9 says otherwise.

Consequences of the corpus decision: three source kinds with different retrieval
characteristics means a **tag convention is now required, not optional** —
see §10.5.

### 10.2 Verification gates — **RUN AND PASSED 2026-09-27**

All four executed against the live cluster. Ollama is reachable on two
LoadBalancer addresses, not ClusterIP as an earlier draft of this document
assumed:

| Endpoint | Address | Release |
|---|---|---|
| planner | `http://192.168.5.206:11434` | `ollama` |
| executor | `http://192.168.5.207:11434` | `ollama-code` |

Both report `{"version":"0.15.6"}` and both see the identical seeded model set
(shared RWX PVC) — confirming §5.8's "one API call away". Note the Helm charts
all set `service.enabled: false`; the LoadBalancers are defined separately, so
grepping the values files understates what is exposed.

| # | Gate | Result |
|---|---|---|
| **V1** | Ollama streams `tool_calls` as SSE deltas? | ✅ **PASS.** `devstral-small-2:24b` returned `delta.tool_calls[{index, id, type, function:{name, arguments}}]`, then a bare `finish_reason: "tool_calls"` frame, then a usage-only frame with empty `choices`, then `data: [DONE]` — exactly the §2.5 shape. **No shim needed; Option A's design stands.** |
| **V2** | Tool-capable chat templates? | ✅ **PASS** for both `devstral-small-2:24b` and `qwen3:32b`. Each produced a structured call to a one-tool schema, not prose. |
| **V3** | Traefik passes long SSE? | **N/A for Ollama** — the LoadBalancers bypass Traefik entirely (plain HTTP, no TLS). Still open for our own services, which *will* sit behind Traefik. Re-scope to the retrieval API and gateway. |
| **V4** | CA trust from opencode? | **N/A if opencode talks to Ollama directly** (no TLS on the LBs). Still required for `/v1/rag/retrieve` and the gateway behind Traefik — mechanism is `NODE_EXTRA_CA_CERTS`. |

#### What the gates changed

**1. Tool calls arrive whole, not fragmented.** `function.arguments` came back as
a complete JSON string in a single delta. That is fine for opencode — accumulation
is keyed by `index` and a single fragment accumulates trivially — but it means no
incremental tool-argument display. The fragmented example in §2.5 is spec-legal
and must still be *handled*, but it is not what this backend does; do not build a
reassembly shim expecting it.

**2. The reasoning field is `reasoning`, not `reasoning_content`.** Ollama emits
`delta.reasoning`, streamed token by token. This corrects §5.7: the value must be

```json
"interleaved": "reasoning"
```

`ProviderInterleavedField` accepts it (`provider.ts`, union of
`["reasoning", "reasoning_content", "reasoning_text"]`). Note that
`interleaved.field` governs how reasoning is **echoed back on subsequent
requests** (`transform.ts:321-350`), not how the response is parsed.

**3. `reasoning_effort: "none"` disables Qwen3 thinking, and it is a first-class
lever.** Same request, same model:

| | completion_tokens | reasoning frames |
|---|---|---|
| default | 167 | many |
| `reasoning_effort: "none"` | **21** | **0** |

The tool call remained correct with `finish_reason: "tool_calls"`. An 8×
reduction in output tokens on a trivial turn. opencode sends `reasoning_effort`
natively (`openai-chat.ts:99`), so this is controllable from model options in
`opencode.json` — no gateway involvement. Whether the planner *should* think is a
quality/latency tradeoff, now measurable rather than theoretical.

**4. `delta.role: "assistant"` is present on every frame.** The native runtime's
`OpenAIChatDelta` schema lists only `content`, `reasoning_content` and
`tool_calls` (`openai-chat.ts:141-145`). Whether Effect's `Schema.Struct` rejects
the excess key is **unverified**. Low priority — the AI SDK is the default runtime
and the native one is opt-in — but it is the first thing to check if the native
runtime misbehaves.

**5. Nothing was resident despite `OLLAMA_KEEP_ALIVE=-1`.** `/api/ps` returned an
empty model list on both pods. `keep_alive: -1` holds a model *after* it loads; it
does not preload. So the first request of each pod's lifetime pays a cold load.
Observed wall-clock, cold, including inference: devstral **12.2s**, qwen3
**18.3s** (the latter mostly thinking). Consider a post-start warmup call if
first-turn latency matters.

### 10.3 Open concern: `OLLAMA_NUM_PARALLEL=1` vs. parallel subagents

opencode's `task` tool can spawn several subagents in one assistant turn, and
they inherit the parent's model (`tool/task.ts:181`). So N concurrent requests
land on the **same** pod and serialise: three `explore` subagents run one after
another.

Raising `OLLAMA_NUM_PARALLEL` to 2 splits the KV allocation, halving effective
per-slot context (65536 → ~32768 on the executor). There is no obviously correct
answer — it trades subagent latency against usable context. Deferred to **M8**.
Until then, leave both pods at 1 and expect subagent fan-out to be slow rather
than broken.

### 10.4 Open concern: the corpus does not exist yet

Retrieval over an empty corpus returns nothing, and the integration will look
*broken* rather than empty. This is work item #1, ahead of the API:

1. Ingest a single small tag and prove retrieval end-to-end through `rag_search`.
2. Only then ingest the three scopes from §10.1.

Plugin behaviour must make the empty case legible: when `/v1/rag/retrieve`
returns zero chunks, inject nothing and — for the tool path — return an explicit
"no matching context in corpus" rather than an empty string, so the model does
not read silence as "nothing exists".

### 10.5 Required: tag convention

With three source kinds in one corpus, retrieval needs to be scopeable or the
executor will get design docs when it wants a function body. Minimum viable
convention, to be pinned before ingestion:

| Tag | Contents | Typical consumer |
|---|---|---|
| `stack-docs` | `documentation/**`, values files, scripts | planner / `plan` agent |
| `stack-go` | `rag-stack/services/**` | executor / `build` agent |
| `opencode-src` | opencode TypeScript sources | either, only when working on the client |

The planner profile (§5.5) should weight `stack-docs`; the executor profile
should weight `stack-go`. How an opencode *project* (cwd / repo) maps onto these
tags still needs deciding — candidates are `X-RAG-Project` from the cwd basename,
or explicit per-repo config in each `opencode.json`.

### 10.6 Settled, recorded so it is not re-litigated

- **TLS trust:** `NODE_EXTRA_CA_CERTS` (§10.2 V4). opencode also honours
  `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY`, and its docs warn that the TUI's own
  local server must be in `NO_PROXY` or requests loop.
- **Traefik does not buffer responses by default**, so SSE should pass; the risk
  is timeouts, not buffering. Prefer an explicit `IngressRoute` with generous
  timeouts over relying on defaults (V3).
- **The "~30s cutoff" is a harness artifact**, not infrastructure —
  `rag-stack/tests/main.go:30` (admin client, 30s) vs `:39` (RAG client, 1800s).
  `values-devstral.yaml:21-22` cites it as a model-selection ground; that one
  argument should be struck. The Devstral choice stands on the other two.
- **`GET /v1/models` is not called by opencode** (§1.3). Implement it for
  debuggability, but model metadata lives in `opencode.json`.
