/**
 * Plugin configuration.
 *
 * Resolution order is plugin options (from opencode.json) first, then
 * environment, then a default. Options win because they are versioned with the
 * project; env exists so a single session can be flipped without editing config.
 */
export type RagConfig = {
  baseUrl: string
  /** Register the rag_search tool. Default ON (spec §10.1). */
  toolEnabled: boolean
  /**
   * Append a <rag-context> system block on every turn. Default OFF.
   *
   * This is the expensive path: a mutating system prefix invalidates
   * llama.cpp's KV prefix cache every turn, forcing a full re-prefill of
   * 20-60k tokens (spec §4 A.3, measurement M9). Leave it off until M9 says
   * otherwise.
   */
  injectEnabled: boolean
  /** Send user turns and tool results to the corpus. Default OFF. */
  ingestEnabled: boolean
  topK: number
  maxTokens: number
  /** Tags to scope retrieval to. Empty means let the server pick per profile. */
  tags: string[]
  includeGlobal: boolean
  project: string
  /** Per-request timeout. Retrieval must never stall a coding turn. */
  timeoutMs: number
  apiKey: string
  debug: boolean
}

function bool(value: unknown, fallback: boolean): boolean {
  if (value === undefined || value === null || value === "") return fallback
  if (typeof value === "boolean") return value
  const s = String(value).toLowerCase()
  if (["1", "true", "yes", "on"].includes(s)) return true
  if (["0", "false", "no", "off"].includes(s)) return false
  return fallback
}

function num(value: unknown, fallback: number): number {
  if (value === undefined || value === null || value === "") return fallback
  const n = Number(value)
  return Number.isFinite(n) && n > 0 ? n : fallback
}

function list(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(String).filter(Boolean)
  if (typeof value === "string") {
    return value
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
  }
  return []
}

export function resolveConfig(options: Record<string, unknown> | undefined, env: Record<string, string | undefined>): RagConfig {
  const o = options ?? {}
  return {
    baseUrl: String(o.baseUrl ?? env.RAG_BASE_URL ?? "https://rag-retrieval.rag.hierocracy.home").replace(/\/+$/, ""),
    toolEnabled: bool(o.toolEnabled ?? env.RAG_TOOL_ENABLED, true),
    injectEnabled: bool(o.injectEnabled ?? env.RAG_INJECT_ENABLED, false),
    ingestEnabled: bool(o.ingestEnabled ?? env.RAG_INGEST_ENABLED, false),
    topK: num(o.topK ?? env.RAG_TOP_K, 6),
    maxTokens: num(o.maxTokens ?? env.RAG_INJECT_MAX_TOKENS, 4096),
    tags: list(o.tags ?? env.RAG_TAGS),
    includeGlobal: bool(o.includeGlobal ?? env.RAG_INCLUDE_GLOBAL, true),
    project: String(o.project ?? env.RAG_PROJECT ?? ""),
    timeoutMs: num(o.timeoutMs ?? env.RAG_TIMEOUT_MS, 3000),
    apiKey: String(o.apiKey ?? env.RAG_API_KEY ?? ""),
    debug: bool(o.debug ?? env.RAG_DEBUG, false),
  }
}
