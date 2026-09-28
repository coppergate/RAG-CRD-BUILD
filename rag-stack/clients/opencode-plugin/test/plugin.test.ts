/**
 * Run with:  node --experimental-strip-types --test test/plugin.test.ts
 *
 * Covers the two properties the plugin must never violate: the client does not
 * throw, and an empty corpus is reported as empty rather than as silence.
 * index.ts and tool.ts are not imported here because they pull in
 * @opencode-ai/plugin, which is only resolvable inside an opencode install.
 */
import { test } from "node:test"
import assert from "node:assert/strict"
import { createServer, type Server } from "node:http"

import { resolveConfig } from "../src/config.ts"
import { RagClient } from "../src/client.ts"
import { InjectionCache } from "../src/inject.ts"

function serve(handler: (req: any, res: any) => void): Promise<{ url: string; close: () => Promise<void>; hits: () => number }> {
  let hits = 0
  return new Promise((resolve) => {
    const srv: Server = createServer((req, res) => {
      hits++
      handler(req, res)
    })
    srv.listen(0, "127.0.0.1", () => {
      const addr = srv.address() as any
      resolve({
        url: `http://127.0.0.1:${addr.port}`,
        close: () =>
          new Promise((r) => {
            // Drop held sockets: the timeout test deliberately never responds,
            // and close() would otherwise wait on that connection.
            srv.closeAllConnections()
            srv.close(() => r())
          }),
        hits: () => hits,
      })
    })
  })
}

const quiet = () => {}

function cfgFor(url: string, over: Record<string, unknown> = {}) {
  return resolveConfig({ baseUrl: url, timeoutMs: 500, ...over }, {})
}

function json(res: any, code: number, body: unknown) {
  res.writeHead(code, { "content-type": "application/json" })
  res.end(JSON.stringify(body))
}

test("config: options beat environment", () => {
  const c = resolveConfig({ topK: 12, injectEnabled: true }, { RAG_TOP_K: "3", RAG_INJECT_ENABLED: "false" })
  assert.equal(c.topK, 12)
  assert.equal(c.injectEnabled, true)
})

test("config: environment used when options absent", () => {
  const c = resolveConfig(undefined, { RAG_TOP_K: "9", RAG_TOOL_ENABLED: "off", RAG_TAGS: "a, b ,c" })
  assert.equal(c.topK, 9)
  assert.equal(c.toolEnabled, false)
  assert.deepEqual(c.tags, ["a", "b", "c"])
})

test("config: nonsense values fall back rather than crashing", () => {
  const c = resolveConfig({ topK: "banana", timeoutMs: -5 }, {})
  assert.equal(c.topK, 6)
  assert.equal(c.timeoutMs, 3000)
})

test("config: trailing slashes stripped from baseUrl", () => {
  assert.equal(resolveConfig({ baseUrl: "https://x.example///" }, {}).baseUrl, "https://x.example")
})

test("client: happy path returns the parsed body", async () => {
  const srv = await serve((_req, res) =>
    json(res, 200, { correlation_id: "c1", profile: "planner", chunks: [{ id: "p1", score: 0.9 }], tokens: 10, truncated: false }),
  )
  const client = new RagClient(cfgFor(srv.url), quiet)
  const got = await client.retrieve({ query: "q" })
  assert.equal(got?.correlation_id, "c1")
  assert.equal(got?.chunks.length, 1)
  await srv.close()
})

test("client: 5xx returns null and does not throw", async () => {
  const srv = await serve((_req, res) => json(res, 500, { error: { message: "boom" } }))
  const client = new RagClient(cfgFor(srv.url), quiet)
  assert.equal(await client.retrieve({ query: "q" }), null)
  // Retried once: two attempts total.
  assert.equal(srv.hits(), 2)
  await srv.close()
})

test("client: 4xx returns null without retrying", async () => {
  const srv = await serve((_req, res) => json(res, 400, { error: { message: "bad" } }))
  const client = new RagClient(cfgFor(srv.url), quiet)
  assert.equal(await client.retrieve({ query: "q" }), null)
  assert.equal(srv.hits(), 1, "a 4xx is our bug; retrying cannot help")
  await srv.close()
})

test("client: timeout returns null and does not throw", async () => {
  const srv = await serve(() => {
    /* never respond */
  })
  const client = new RagClient(cfgFor(srv.url, { timeoutMs: 120 }), quiet)
  const started = Date.now()
  assert.equal(await client.retrieve({ query: "q" }), null)
  assert.ok(Date.now() - started < 2000, "must abort rather than hang the turn")
  await srv.close()
})

test("client: unreachable host returns null and does not throw", async () => {
  // Port 1 is reliably closed.
  const client = new RagClient(resolveConfig({ baseUrl: "http://127.0.0.1:1", timeoutMs: 200 }, {}), quiet)
  assert.equal(await client.retrieve({ query: "q" }), null)
})

test("client: malformed JSON returns null and does not throw", async () => {
  const srv = await serve((_req, res) => {
    res.writeHead(200, { "content-type": "application/json" })
    res.end("{not json")
  })
  const client = new RagClient(cfgFor(srv.url), quiet)
  assert.equal(await client.retrieve({ query: "q" }), null)
  await srv.close()
})

test("client: control headers are sent", async () => {
  let headers: Record<string, string> = {}
  const srv = await serve((req, res) => {
    headers = req.headers
    json(res, 200, { correlation_id: "c", profile: "planner", chunks: [], tokens: 0, truncated: false })
  })
  const client = new RagClient(cfgFor(srv.url, { project: "complete-build", apiKey: "k" }), quiet)
  await client.retrieve({ query: "q", session: "ses_1", agent: "build" })
  assert.equal(headers["x-rag-session"], "ses_1")
  assert.equal(headers["x-rag-agent"], "build")
  assert.equal(headers["x-rag-project"], "complete-build")
  assert.equal(headers["authorization"], "Bearer k")
  await srv.close()
})

test("client: ingest is a no-op when disabled", async () => {
  const srv = await serve((_req, res) => json(res, 202, { accepted: true }))
  const client = new RagClient(cfgFor(srv.url, { ingestEnabled: false }), quiet)
  await client.ingestTurn({ kind: "user_turn", text: "hello" })
  assert.equal(srv.hits(), 0, "disabled ingest must not reach the network")
  await srv.close()
})

test("client: ingest posts when enabled", async () => {
  const srv = await serve((_req, res) => json(res, 202, { accepted: true }))
  const client = new RagClient(cfgFor(srv.url, { ingestEnabled: true }), quiet)
  await client.ingestTurn({ kind: "user_turn", text: "hello" })
  assert.equal(srv.hits(), 1)
  await srv.close()
})

test("injection: block is cached byte-identically across turns", async () => {
  // The KV-prefix-cache invariant (spec §4 A.3): a second turn in the same
  // session must reuse the exact same bytes and must NOT re-retrieve.
  let n = 0
  const srv = await serve((_req, res) => {
    n++
    json(res, 200, {
      correlation_id: `c${n}`,
      profile: "planner",
      block: `<rag-context k="6">call ${n}</rag-context>`,
      chunks: [{ id: "p", score: 1 }],
      tokens: 5,
      truncated: false,
    })
  })
  const cfg = cfgFor(srv.url)
  const cache = new InjectionCache(new RagClient(cfg, quiet), cfg, quiet)

  const first = await cache.blockFor({ sessionID: "ses_1", query: "q" })
  const second = await cache.blockFor({ sessionID: "ses_1", query: "different query" })
  assert.equal(first, second, "block must be byte-identical across turns")
  assert.equal(srv.hits(), 1, "must not re-retrieve within a session")
  await srv.close()
})

test("injection: distinct sessions get distinct blocks", async () => {
  let n = 0
  const srv = await serve((_req, res) => {
    n++
    json(res, 200, { correlation_id: "c", profile: "planner", block: `block${n}`, chunks: [], tokens: 1, truncated: false })
  })
  const cfg = cfgFor(srv.url)
  const cache = new InjectionCache(new RagClient(cfg, quiet), cfg, quiet)
  const a = await cache.blockFor({ sessionID: "ses_a", query: "q" })
  const b = await cache.blockFor({ sessionID: "ses_b", query: "q" })
  assert.notEqual(a, b)
  await srv.close()
})

test("injection: empty corpus injects nothing", async () => {
  const srv = await serve((_req, res) =>
    json(res, 200, { correlation_id: "c", profile: "planner", chunks: [], tokens: 0, truncated: false, collection_missing: true }),
  )
  const cfg = cfgFor(srv.url)
  const cache = new InjectionCache(new RagClient(cfg, quiet), cfg, quiet)
  assert.equal(await cache.blockFor({ sessionID: "s", query: "q" }), "", "an empty wrapper costs prefix cache and says nothing")
  await srv.close()
})

test("injection: retrieval failure injects nothing", async () => {
  const cfg = resolveConfig({ baseUrl: "http://127.0.0.1:1", timeoutMs: 150 }, {})
  const cache = new InjectionCache(new RagClient(cfg, quiet), cfg, quiet)
  assert.equal(await cache.blockFor({ sessionID: "s", query: "q" }), "")
})
