import type { Plugin } from "@opencode-ai/plugin"
import { resolveConfig } from "./src/config.js"
import { RagClient } from "./src/client.js"
import { ragSearchTool } from "./src/tool.js"
import { InjectionCache } from "./src/inject.js"

/**
 * RAG Stack plugin for opencode.
 *
 * Two independent retrieval paths, per spec §10.1:
 *
 *   rag_search tool   (RAG_TOOL_ENABLED,   default ON)  — the model asks.
 *   system injection  (RAG_INJECT_ENABLED, default OFF) — every turn gets a block.
 *
 * They ship together and are flag-independent so M9 can compare them on real
 * traffic. The tool is the default because a tool result appends to the END of
 * the conversation and preserves llama.cpp's KV prefix cache, while injection
 * mutates the prefix and re-prefills 20-60k tokens per turn (§4 A.3).
 *
 * Nothing in here is allowed to throw. Every hook swallows its errors: a
 * retrieval problem must degrade to "no context", never break a coding session.
 */
export const RagStackPlugin: Plugin = async ({ directory, worktree }, options) => {
  const cfg = resolveConfig(options as Record<string, unknown> | undefined, process.env)

  const log = (msg: string, extra?: unknown) => {
    if (!cfg.debug) return
    if (extra !== undefined) console.error(`[rag-stack] ${msg}`, extra)
    else console.error(`[rag-stack] ${msg}`)
  }

  // Default the project to the worktree basename so per-repo corpus
  // partitioning works without per-repo config (spec §10.5 open question).
  if (!cfg.project) {
    const root = worktree || directory || ""
    cfg.project = root.split("/").filter(Boolean).pop() ?? ""
  }

  const client = new RagClient(cfg, log)
  const injection = new InjectionCache(client, cfg, log)

  /**
   * Agent name by session.
   *
   * experimental.chat.system.transform receives only { sessionID, model } —
   * the agent is not passed (plugin/src/index.ts:291 vs :248). chat.params does
   * get it, and runs first, so we stash it here for the injection hook to read.
   * Spec §5.5 Option B.
   */
  const agentBySession = new Map<string, string>()
  const lastQueryBySession = new Map<string, string>()

  log(
    `initialised baseUrl=${cfg.baseUrl} project=${cfg.project || "(none)"} ` +
      `tool=${cfg.toolEnabled} inject=${cfg.injectEnabled} ingest=${cfg.ingestEnabled}`,
  )

  return {
    ...(cfg.toolEnabled ? { tool: { rag_search: ragSearchTool(client, cfg) } } : {}),

    "chat.params": async (input) => {
      try {
        if (input.sessionID && input.agent) agentBySession.set(input.sessionID, input.agent)
      } catch (err) {
        log("chat.params failed", err)
      }
    },

    /**
     * Stamp the control headers. Harmless today (the plugin calls the retrieval
     * API itself), and it is what makes an Option A gateway work later without
     * touching this plugin.
     */
    "chat.headers": async (input, output) => {
      try {
        if (input.sessionID) output.headers["X-RAG-Session"] = input.sessionID
        if (input.agent) output.headers["X-RAG-Agent"] = input.agent
        if (cfg.project) output.headers["X-RAG-Project"] = cfg.project
        output.headers["X-RAG-Include-Global"] = String(cfg.includeGlobal)
        output.headers["X-RAG-Top-K"] = String(cfg.topK)
      } catch (err) {
        log("chat.headers failed", err)
      }
    },

    "chat.message": async (input, output) => {
      try {
        // Remember the user's text so the injection hook, which sees no
        // message, has something to retrieve against.
        const text = output.parts
          .filter((p) => p.type === "text")
          .map((p) => p.text)
          .join("\n")
          .trim()

        if (text && input.sessionID) lastQueryBySession.set(input.sessionID, text)

        if (text) {
          // Deliberately not awaited: this must not add latency to the turn.
          void client.ingestTurn({
            session: input.sessionID,
            kind: "user_turn",
            text,
            metadata: { agent: input.agent, model: input.model?.modelID, project: cfg.project },
          })
        }
      } catch (err) {
        log("chat.message failed", err)
      }
    },

    "experimental.chat.system.transform": async (input, output) => {
      if (!cfg.injectEnabled) return
      try {
        const query = (input.sessionID && lastQueryBySession.get(input.sessionID)) || ""
        if (!query) return // nothing to retrieve against yet

        const block = await injection.blockFor({
          sessionID: input.sessionID,
          query,
          agent: input.sessionID ? agentBySession.get(input.sessionID) : undefined,
          // NB: an SDK Model here, whose field is `id`. chat.message below gets
          // an inline { providerID, modelID } instead -- do not unify these.
          model: input.model?.id,
        })
        // Append only when non-empty: an empty wrapper costs prefix cache and
        // tells the model nothing.
        if (block) output.system.push(block)
      } catch (err) {
        log("system.transform failed", err)
      }
    },

    "tool.execute.after": async (input, output) => {
      if (!cfg.ingestEnabled) return
      try {
        // rag_search results are already corpus content; re-ingesting them
        // would feed the corpus its own output.
        if (input.tool === "rag_search") return
        if (!output.output) return

        void client.ingestTurn({
          session: input.sessionID,
          kind: "tool_result",
          tool: input.tool,
          text: output.output,
          metadata: { title: output.title, args: input.args },
        })
      } catch (err) {
        log("tool.execute.after failed", err)
      }
    },
  }
}

export default RagStackPlugin
