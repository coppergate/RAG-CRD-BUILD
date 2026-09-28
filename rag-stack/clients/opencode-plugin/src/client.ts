import type { RagConfig } from "./config.js"

export type RagChunk = {
  id: string
  score: number
  path?: string
  chunk?: number
  text?: string
  tags?: number[]
  tag_names?: string[]
  /** Present only for chunks ingested after line-range support landed. */
  start_line?: number
  end_line?: number
}

export type RagMemory = { memory_type?: string; summary?: string; content?: string }

export type RetrieveResponse = {
  correlation_id: string
  session_id?: number
  profile: string
  block?: string
  chunks: RagChunk[]
  memory?: RagMemory[]
  tokens: number
  truncated: boolean
  collection?: string
  collection_missing?: boolean
  unknown_tags?: string[]
  degraded?: string[]
}

export type RetrieveArgs = {
  query: string
  session?: string
  agent?: string
  model?: string
  tags?: string[]
  topK?: number
  maxTokens?: number
  format?: "block" | "chunks"
  profile?: string
}

/**
 * HTTP client for the retrieval API.
 *
 * Central invariant: nothing here throws. Retrieval is an enhancement, and a
 * dead retrieval service, a TLS problem or a slow response must never break a
 * coding session (spec §4 B.2). Every failure path returns null and the caller
 * proceeds with no context.
 */
export class RagClient {
  // Explicit fields rather than TS parameter properties: those need
  // type-directed emit, which rules out `node --experimental-strip-types` and
  // therefore the test suite in test/.
  readonly cfg: RagConfig
  private readonly log: (msg: string, extra?: unknown) => void

  constructor(cfg: RagConfig, log: (msg: string, extra?: unknown) => void) {
    this.cfg = cfg
    this.log = log
  }

  async retrieve(args: RetrieveArgs): Promise<RetrieveResponse | null> {
    const body = {
      query: args.query,
      session: args.session,
      project: this.cfg.project || undefined,
      tags: args.tags && args.tags.length > 0 ? args.tags : this.cfg.tags.length > 0 ? this.cfg.tags : undefined,
      include_global: this.cfg.includeGlobal,
      top_k: args.topK ?? this.cfg.topK,
      max_tokens: args.maxTokens ?? this.cfg.maxTokens,
      include_memory: undefined,
      format: args.format ?? "block",
      profile: args.profile,
      agent: args.agent,
      model: args.model,
    }

    const headers: Record<string, string> = { "Content-Type": "application/json" }
    if (this.cfg.apiKey) headers["Authorization"] = `Bearer ${this.cfg.apiKey}`
    if (args.session) headers["X-RAG-Session"] = args.session
    if (args.agent) headers["X-RAG-Agent"] = args.agent
    if (this.cfg.project) headers["X-RAG-Project"] = this.cfg.project

    const res = await this.post<RetrieveResponse>("/v1/rag/retrieve", body, headers)
    if (!res) return null

    if (res.degraded?.length) this.log(`retrieval degraded: ${res.degraded.join("; ")}`)
    if (res.collection_missing) {
      this.log("corpus not ingested for this embedding model -- retrieval will return nothing until it is")
    }
    if (res.unknown_tags?.length) {
      this.log(`unknown tags ignored: ${res.unknown_tags.join(", ")} -- check them against GET /v1/rag/tags`)
    }
    return res
  }

  /** Fire-and-forget. Never awaited by a hook on the critical path. */
  async ingestTurn(input: {
    session?: string
    kind: "user_turn" | "tool_result" | "assistant_turn"
    tool?: string
    text: string
    metadata?: Record<string, unknown>
  }): Promise<void> {
    if (!this.cfg.ingestEnabled) return
    const headers: Record<string, string> = { "Content-Type": "application/json" }
    if (this.cfg.apiKey) headers["Authorization"] = `Bearer ${this.cfg.apiKey}`
    if (input.session) headers["X-RAG-Session"] = input.session

    await this.post("/v1/rag/ingest/turn", { ...input, project: this.cfg.project || undefined }, headers)
  }

  private async post<T>(path: string, body: unknown, headers: Record<string, string>): Promise<T | null> {
    // One retry, because a single dropped connection is common and cheap to
    // absorb; more than that and we are making the turn wait for nothing.
    for (let attempt = 0; attempt < 2; attempt++) {
      const controller = new AbortController()
      const timer = setTimeout(() => controller.abort(), this.cfg.timeoutMs)
      try {
        const res = await fetch(`${this.cfg.baseUrl}${path}`, {
          method: "POST",
          headers,
          body: JSON.stringify(body),
          signal: controller.signal,
        })
        if (!res.ok) {
          const text = await res.text().catch(() => "")
          this.log(`${path} returned ${res.status}${text ? `: ${text.slice(0, 200)}` : ""}`)
          // 4xx is our own bug or a bad request; retrying will not help.
          if (res.status < 500) return null
          continue
        }
        return (await res.json()) as T
      } catch (err) {
        const reason = err instanceof Error ? err.message : String(err)
        this.log(`${path} attempt ${attempt + 1} failed: ${reason}`)
      } finally {
        clearTimeout(timer)
      }
    }
    return null
  }
}
