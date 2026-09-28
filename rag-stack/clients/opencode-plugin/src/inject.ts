import type { RagClient } from "./client.js"
import type { RagConfig } from "./config.js"

/**
 * Per-session cache of the injected block.
 *
 * This exists for a specific performance reason, not for convenience. A coding
 * agent resends the whole conversation each turn, and llama.cpp reuses its KV
 * prefix only while the FRONT of the prompt is byte-identical. A system block
 * that changes between turns invalidates the prefix every time, forcing a full
 * re-prefill of 20-60k tokens on a V100 (spec §4 A.3, measurement M9).
 *
 * So: retrieve once per session, then reuse the exact same bytes. The block is
 * keyed by session and is deliberately NOT refreshed per turn.
 */
type Entry = { block: string; createdAt: number }

export class InjectionCache {
  private readonly entries = new Map<string, Entry>()
  private readonly client: RagClient
  private readonly cfg: RagConfig
  private readonly log: (msg: string, extra?: unknown) => void
  private readonly ttlMs: number

  constructor(
    client: RagClient,
    cfg: RagConfig,
    log: (msg: string, extra?: unknown) => void,
    ttlMs = 15 * 60 * 1000,
  ) {
    this.client = client
    this.cfg = cfg
    this.log = log
    this.ttlMs = ttlMs
  }

  /** Returns the block for a session, or "" when there is nothing to inject. */
  async blockFor(input: { sessionID?: string; query: string; agent?: string; model?: string }): Promise<string> {
    const key = input.sessionID ?? "__no_session__"
    const hit = this.entries.get(key)
    if (hit && Date.now() - hit.createdAt < this.ttlMs) return hit.block

    const res = await this.client.retrieve({
      query: input.query,
      session: input.sessionID,
      agent: input.agent,
      model: input.model,
      format: "block",
      maxTokens: this.cfg.maxTokens,
    })

    // Inject nothing on failure or on an empty corpus. An empty <rag-context>
    // wrapper is worse than no wrapper: it costs prefix cache and says nothing.
    const block = res?.block ?? ""
    if (!block) {
      this.log(res ? "nothing to inject (empty corpus or no match)" : "nothing to inject (retrieval unavailable)")
    } else {
      this.log(`injecting ${res?.tokens ?? 0} tokens from ${res?.chunks.length ?? 0} chunks`)
    }

    this.entries.set(key, { block, createdAt: Date.now() })
    return block
  }

  forget(sessionID: string) {
    this.entries.delete(sessionID)
  }
}
