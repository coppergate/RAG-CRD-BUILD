# RAG Stack plugin for opencode

Gives opencode retrieval against the hierophant RAG corpus. Implements
**Option B** of `documentation/OPENCODE-RAG-INTEGRATION-SPEC.md`: opencode keeps
ownership of the tool loop, streaming, caching and retries, and this plugin adds
context through the hooks it already exposes.

## The two paths, and why the default is what it is

| Path | Flag | Default | What it does |
|---|---|---|---|
| `rag_search` tool | `toolEnabled` / `RAG_TOOL_ENABLED` | **on** | Registers a tool; the model asks when it needs context |
| System injection | `injectEnabled` / `RAG_INJECT_ENABLED` | **off** | Appends a `<rag-context>` block to the system prompt every turn |
| Turn ingest | `ingestEnabled` / `RAG_INGEST_ENABLED` | **off** | Sends user turns and tool results back into the corpus |

**The tool is the default because injection is the expensive path on this
hardware.** A coding agent resends the whole conversation each turn, and
llama.cpp reuses its KV prefix cache only while the *front* of the prompt is
byte-identical. A system block that changes between turns invalidates that
prefix every turn, forcing a full re-prefill of 20-60k tokens on a V100. A tool
result appends at the *end* of the conversation and leaves the prefix intact.

When injection is on, the block is retrieved **once per session and cached
byte-identically** for exactly this reason. Do not "improve" it to refresh per
turn without reading spec §4 A.3 and running measurement M9 first.

## Install

Reference it by path — nothing is written into the opencode checkout:

```json
{
  "plugin": [
    ["/mnt/hegemon-share/share/code/complete-build/rag-stack/clients/opencode-plugin",
     { "baseUrl": "https://rag-retrieval.rag.hierocracy.home" }]
  ]
}
```

See `opencode.json.example` for a complete file including the provider and agent
wiring. Options in `opencode.json` take precedence over environment variables.

## TLS and proxies

The retrieval service sits behind Traefik with the internal CA, so Node needs to
be told about it:

```bash
export NODE_EXTRA_CA_CERTS=/mnt/hegemon-share/share/code/complete-build/root-ca.crt
```

If `HTTPS_PROXY` is set, opencode's own local server **must** be in `NO_PROXY`
or its requests loop:

```bash
export NO_PROXY="localhost,127.0.0.1,.hierocracy.home"
```

## Three things in the config that are load-bearing

These correct the spec's §5.7 example with what was actually verified in §10.2:

1. **`"temperature": true`** must be explicit. It defaults to `false` for
   config-declared models, so opencode will not send temperature otherwise.
2. **`"interleaved": "reasoning"`** — Ollama's field is `reasoning`, not
   `reasoning_content`. Add `"reasoning_effort": "none"` under model options to
   switch Qwen3 thinking off entirely; it cut output tokens 8× on a trivial turn.
3. **`limit.context` must not exceed the pod's real `OLLAMA_CONTEXT_LENGTH`.**
   opencode drives compaction off this number, so a value that is too high
   produces silent overflow instead of compaction. The planner is deployed at
   **16384**; the `32768` in spec §5.7 is aspirational and must not be shipped
   until measurement M4 says it fits.

Leave subagent models unset. `task.ts:181` makes subagents inherit the parent's
model, and a third distinct model forces an eviction and starts both cards
thrashing.

## Failure behaviour

Retrieval is an enhancement, never a dependency. Every hook swallows its own
errors, the HTTP client never throws, and each request has a 3s timeout with one
retry. Any failure degrades to "no context" and the coding session continues.

Two cases are deliberately distinguished, because they look identical from the
outside and mean very different things:

- **Retrieval unreachable** — the tool says the service could not be reached.
- **Corpus empty or no match** — the tool returns
  `no matching context in corpus`, never an empty string. A model reads silence
  as "nothing exists", which is a different and stronger claim than "I found
  nothing".

## Debugging

```bash
RAG_DEBUG=1 opencode run "why does the ingestion worker drop large chunks"
```

Logs go to stderr prefixed `[rag-stack]`. Server-side, every response carries
`X-RAG-Correlation-Id`, and the JSON body includes `timings_ms` and a `degraded`
array naming anything that silently fell back.
