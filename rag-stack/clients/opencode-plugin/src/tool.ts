import { tool, type ToolDefinition } from "@opencode-ai/plugin"
import type { RagClient, RagChunk } from "./client.js"
import type { RagConfig } from "./config.js"

/**
 * The string returned when the corpus had no match.
 *
 * Spec §10.4: a model reads an empty string as "nothing exists". Saying so
 * explicitly is a different and more accurate claim, and it keeps an
 * un-ingested corpus from looking like a broken tool.
 */
export const NO_MATCH = "no matching context in corpus"

/** Cite a chunk in a form the model can act on. */
function cite(c: RagChunk): string {
  if (!c.path) return "unknown"
  if (typeof c.start_line === "number" && typeof c.end_line === "number") {
    return `${c.path}:${c.start_line}-${c.end_line}`
  }
  // Do not imply a line number we do not have.
  return `${c.path}#chunk${c.chunk ?? 0}`
}

function render(chunks: RagChunk[]): string {
  return chunks
    .map((c) => {
      const tags = c.tag_names?.length ? ` [${c.tag_names.join(", ")}]` : ""
      return `### ${cite(c)} (score ${c.score.toFixed(3)})${tags}\n${(c.text ?? "").trim()}`
    })
    .join("\n\n")
}

/**
 * rag_search — model-driven retrieval.
 *
 * Preferred over blind injection: the model asks only when it needs to, and the
 * result lands at the END of the conversation as a tool message, which
 * preserves llama.cpp's KV prefix cache. Injection mutates the prefix and
 * re-prefills every turn (spec §4 A.3).
 */
export function ragSearchTool(client: RagClient, cfg: RagConfig): ToolDefinition {
  return tool({
    description:
      "Search the RAG corpus for design docs, prior decisions, and code context outside the current repo. " +
      "Use it when the answer likely lives in project documentation or in another service's source, " +
      "rather than in a file you can read directly.",
    args: {
      query: tool.schema.string().describe("What to look for, phrased as a question or a description"),
      tags: tool.schema
        .array(tool.schema.string())
        .optional()
        .describe("Optional tag names to scope the search, e.g. stack-docs, stack-go, opencode-src"),
      top_k: tool.schema.number().int().optional().describe("How many chunks to return (default 6)"),
    },
    async execute(args, context) {
      const res = await client.retrieve({
        query: args.query,
        session: context.sessionID,
        agent: context.agent,
        tags: args.tags,
        topK: args.top_k ?? cfg.topK,
        format: "chunks",
      })

      // Unreachable service: say so, rather than implying the corpus is empty.
      if (!res) {
        return {
          title: "rag_search unavailable",
          output:
            "The RAG retrieval service could not be reached, so no corpus context is available for this query. " +
            "Proceed using the files in the repo.",
          metadata: { available: false },
        }
      }

      if (res.chunks.length === 0) {
        const detail = res.collection_missing
          ? `${NO_MATCH} (the corpus has not been ingested yet)`
          : NO_MATCH
        return {
          title: "rag_search: no results",
          output: detail,
          metadata: {
            available: true,
            chunks: 0,
            collection_missing: res.collection_missing ?? false,
            correlation_id: res.correlation_id,
          },
        }
      }

      return {
        title: `rag_search: ${res.chunks.length} chunk${res.chunks.length === 1 ? "" : "s"}`,
        output: render(res.chunks),
        metadata: {
          available: true,
          chunks: res.chunks.length,
          profile: res.profile,
          collection: res.collection,
          correlation_id: res.correlation_id,
          sources: res.chunks.map(cite),
        },
      }
    },
  })
}
