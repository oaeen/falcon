// Falcon plugin host: executes @opencode-ai/plugin v1 plugins under Bun
// and communicates with falcon-core over newline-delimited JSON RPC on stdin/stdout.

import { AsyncLocalStorage } from "node:async_hooks"
import dns from "node:dns"
import fs from "node:fs"
import net from "node:net"
import path from "node:path"
import readline from "node:readline"
import { pathToFileURL } from "node:url"

const rpcWrite = process.stdout.write.bind(process.stdout)

// Redirect all plugin console/stdout writes to stderr so stdout stays strictly JSON-RPC.
const toErr = (...xs) => {
  const line = xs.map((x) => (typeof x === "string" ? x : Bun.inspect(x))).join(" ") + "\n"
  process.stderr.write(line)
}
console.log = console.info = console.debug = console.warn = toErr
process.stdout.write = (chunk, enc, cb) => process.stderr.write(chunk, enc, cb)

// Apply FALCON_DNS if provided (critical on Android where /etc/resolv.conf may be absent).
if (process.env.FALCON_DNS) {
  const servers = process.env.FALCON_DNS
    .split(",")
    .map((s) => s.trim())
    .filter((s) => net.isIP(s) !== 0)
  if (servers.length > 0) {
    try {
      dns.setServers(servers)
    } catch (e) {
      toErr("dns.setServers failed:", e?.message ?? e)
    }
  }
}

const outq = []
let pumping = false

function pump() {
  if (pumping) return
  pumping = true
  while (outq.length > 0) {
    const item = outq.shift()
    const ok = rpcWrite(item.line)
    item.resolve()
    if (!ok) {
      process.stdout.once("drain", () => {
        pumping = false
        pump()
      })
      return
    }
  }
  pumping = false
}

function send(msg) {
  const line = typeof msg === "string" ? msg : JSON.stringify(msg) + "\n"
  return new Promise((resolve) => {
    outq.push({ line, resolve })
    pump()
  })
}

const chunkLine = (id, data) => `{"id":${JSON.stringify(id)},"event":"chunk","data":"${data}"}\n`

let authPath = ""
let directory = process.cwd()
let userConfig = {}
let chosenOptions = {}
let config = { provider: {} }

const hooks = [] // { spec, target, hooks }
const loaded = [] // { spec, error?, provides }
const loaders = new Map() // accountKey -> loaderOpts
const sessions = new Map() // sessionId -> { provider, key, a, inputs }
let nextSession = 1

const scopeStorage = new AsyncLocalStorage()

function providerOf(key) {
  const idx = key.indexOf("#")
  return idx >= 0 ? key.slice(0, idx) : key
}

function readJSON(file, fallback = undefined) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"))
  } catch {
    return fallback
  }
}

function writeAtomicJSON(file, data) {
  const dir = path.dirname(file)
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 })
  const tmp = `${file}.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + "\n", { mode: 0o600 })
  fs.renameSync(tmp, file)
}

function readAuth() {
  if (!authPath) return {}
  const data = readJSON(authPath, {})
  return data && typeof data === "object" && !Array.isArray(data) ? data : {}
}

let authWriteChain = Promise.resolve()
function changeAuth(mutator) {
  const run = authWriteChain.then(async () => {
    const all = readAuth()
    const keep = mutator(all)
    if (keep === false) return false
    writeAtomicJSON(authPath, all)
    return true
  })
  authWriteChain = run.catch(() => {})
  return run
}

function accountsOf(all, provider) {
  return Object.keys(all).filter((k) => providerOf(k) === provider)
}

function freshKey(provider) {
  const all = readAuth()
  if (!(provider in all)) return provider
  for (let i = 2; ; i++) {
    const candidate = `${provider}#${i}`
    if (!(candidate in all)) return candidate
  }
}

function accountKey(provider, account) {
  if (account && providerOf(account) === provider) return account
  const keys = accountsOf(readAuth(), provider)
  return keys[0] ?? provider
}

function activeKey(provider) {
  const st = scopeStorage.getStore()
  if (st && st.provider === provider && st.key) return st.key
  return accountKey(provider, undefined)
}

async function setAuth(key, entry) {
  await changeAuth((all) => {
    all[key] = entry
  })
  loaders.delete(key)
  send({ event: "auth", provider: providerOf(key), account: key })
}

async function removeAuth(key) {
  await changeAuth((all) => {
    if (!(key in all)) return false
    delete all[key]
  })
  loaders.delete(key)
  send({ event: "auth", provider: providerOf(key), account: key })
}

function authCopy(key) {
  const v = readAuth()[key]
  return v ? structuredClone(v) : undefined
}

function auths() {
  const map = new Map()
  for (const h of hooks) {
    if (h.hooks?.auth?.provider) {
      map.set(h.hooks.auth.provider, { spec: h.spec, target: h.target, auth: h.hooks.auth })
    }
  }
  return map
}

function authOf(provider) {
  const entry = auths().get(provider)
  if (!entry) throw new Error(`no plugin registers provider ${provider}`)
  return entry.auth
}

function makeClient() {
  const stub = (name) => async () => ({ data: undefined })
  const known = {
    auth: {
      set: async (opts) => {
        const id = opts?.path?.id ?? opts?.id
        const body = opts?.body ?? opts
        if (typeof id === "string" && body && typeof body === "object") {
          const targetKey = activeKey(id)
          await setAuth(targetKey, body)
        }
        return { data: true }
      },
    },
    tui: {
      showToast: async (opts) => {
        const b = opts?.body ?? opts ?? {}
        send({ event: "toast", title: b.title ?? "", message: String(b.message ?? ""), variant: b.variant ?? "info" })
        return { data: true }
      },
    },
    app: {
      log: async (opts) => {
        const b = opts?.body ?? opts ?? {}
        send({ event: "log", level: b.level ?? "info", message: `[${b.service ?? "plugin"}] ${b.message ?? ""}` })
        return { data: true }
      },
    },
    config: {
      get: async () => ({ data: config }),
    },
  }
  const wrap = (obj, prefix) =>
    new Proxy(obj, {
      get(target, key) {
        if (key in target) {
          const v = target[key]
          return v && typeof v === "object" ? wrap(v, `${prefix}.${String(key)}`) : v
        }
        if (key === "then") return undefined
        return stub(`${prefix}.${String(key)}`)
      },
    })
  return wrap(known, "client")
}

const INDEX_FILES = ["index.ts", "index.tsx", "index.js", "index.mjs", "index.cjs"]

function resolveEntries(target) {
  const st = fs.statSync(target, { throwIfNoEntry: false })
  if (!st) throw new Error(`plugin path not found: ${target}`)
  if (!st.isDirectory()) return [target]
  const out = []
  const add = (v) => typeof v === "string" && v.trim() && out.push(path.resolve(target, v.trim()))
  const pick = (x) => (typeof x === "string" ? x : x?.import ?? x?.default)
  const pkg = readJSON(path.join(target, "package.json"))
  if (pkg) {
    const ex = pkg.exports && typeof pkg.exports === "object" && !Array.isArray(pkg.exports) ? pkg.exports : undefined
    if (ex) add(pick(ex["./server"]))
    add(pkg.main)
    if (ex) add(pick(ex["."]))
    if (typeof pkg.exports === "string") add(pkg.exports)
  }
  for (const f of INDEX_FILES) {
    const p = path.join(target, f)
    if (fs.existsSync(p)) out.push(p)
  }
  if (out.length === 0) {
    throw new Error(`${pkg?.name || target} has no loadable entry point`)
  }
  return [...new Set(out)]
}

function extractServers(mod) {
  const d = mod.default
  if (d && typeof d === "object" && ("server" in d || "id" in d || "tui" in d)) {
    return typeof d.server === "function" ? [d.server] : []
  }
  const seen = new Set()
  const out = []
  for (const v of Object.values(mod)) {
    if (seen.has(v)) continue
    seen.add(v)
    if (typeof v === "function") out.push(v)
    else if (v && typeof v === "object" && typeof v.server === "function") out.push(v.server)
  }
  return out
}

async function loadPlugins(list) {
  hooks.length = 0
  loaded.length = 0
  loaders.clear()

  const input = {
    client: makeClient(),
    project: { id: "falcon", worktree: directory, vcs: undefined, time: { created: Date.now() } },
    directory,
    worktree: directory,
    experimental_workspace: { register() {} },
    serverUrl: new URL("http://127.0.0.1:4096"),
    $: typeof Bun !== "undefined" ? Bun.$ : undefined,
    magpie: {
      option: (provider, key) => Boolean(chosenOptions?.[provider]?.[key]),
      options: (provider) => ({ ...(chosenOptions?.[provider] ?? {}) }),
      load: () => 0,
      usage: () => true,
      account: (provider) => activeKey(provider),
    },
  }

  for (const p of list) {
    try {
      let fns = []
      for (const file of resolveEntries(p.target)) {
        const mod = await import(pathToFileURL(file).href)
        fns = extractServers(mod)
        if (fns.length > 0) break
      }
      if (fns.length === 0) {
        throw new Error("no OpenCode plugin function exported")
      }
      const provides = []
      for (const fn of fns) {
        const h = (await fn(input, p.options)) ?? {}
        hooks.push({ spec: p.spec, target: p.target, hooks: h })
        if (h?.auth?.provider) provides.push(h.auth.provider)
      }
      loaded.push({ spec: p.spec, provides })
    } catch (e) {
      loaded.push({ spec: p.spec, error: String(e?.message ?? e), provides: [] })
    }
  }

  config = { provider: {}, ...structuredClone(userConfig ?? {}) }
  for (const h of hooks) {
    if (typeof h.hooks.config === "function") {
      try {
        await h.hooks.config(config)
      } catch (e) {
        toErr(`${h.spec}: config hook:`, e?.message ?? e)
      }
    }
  }
}

function protocolFromNpm(npm) {
  if (npm === "@ai-sdk/anthropic" || npm === "@ai-sdk/google-vertex/anthropic") return "anthropic"
  if (npm === "@ai-sdk/google") return "gemini"
  if (npm === "@ai-sdk/openai") return "responses"
  return "openai"
}

async function buildProviderInfo(id, key) {
  const cfg = config.provider?.[id] ?? {}
  const out = {
    id,
    name: cfg.name ?? id,
    source: "config",
    env: cfg.env ?? [],
    options: { ...(cfg.options ?? {}) },
    npm: cfg.npm ?? "@ai-sdk/openai-compatible",
    api: cfg.api ?? "",
    models: {},
  }
  for (const [mid, m] of Object.entries(cfg.models ?? {})) {
    const npm = m?.provider?.npm ?? cfg.npm ?? "@ai-sdk/openai-compatible"
    out.models[mid] = {
      id: mid,
      providerID: id,
      name: m?.name ?? mid,
      api: { id: m?.id ?? mid, url: m?.provider?.api ?? cfg.api ?? "", npm },
      limit: { context: m?.limit?.context ?? 128000, input: m?.limit?.input ?? 0, output: m?.limit?.output ?? 16384 },
      capabilities: {
        reasoning: Boolean(m?.reasoning),
        input: { text: true, image: Boolean(m?.attachment) },
        output: { text: true },
      },
      free: m?.free === true,
    }
  }
  for (const h of hooks) {
    const ph = h.hooks.provider
    if (ph?.id === id && typeof ph.models === "function") {
      try {
        const given = structuredClone(out)
        const next = await scopeStorage.run({ provider: id, key }, () =>
          ph.models(given, { auth: authCopy(key) }),
        )
        if (next && typeof next === "object") {
          out.models = Object.fromEntries(
            Object.entries(next).map(([k, m]) => [k, { ...m, id: k, providerID: id }]),
          )
        }
      } catch (e) {
        out.listError = String(e?.message ?? e)
      }
    }
  }
  return out
}

async function listProviders() {
  const stored = readAuth()
  const out = []
  for (const [id, entry] of auths().entries()) {
    const keys = accountsOf(stored, id)
    const primaryKey = keys[0] ?? id
    const pInfo = await buildProviderInfo(id, primaryKey)
    const models = Object.values(pInfo.models ?? {})
      .filter((m) => m.status !== "deprecated")
      .map((m) => ({
        id: m.id,
        name: m.name ?? m.id,
        npm: m.api?.npm ?? pInfo.npm ?? "",
        protocol: protocolFromNpm(m.api?.npm ?? pInfo.npm ?? ""),
        url: m.api?.url ?? "",
        apiId: m.api?.id ?? m.id,
        context: m.limit?.context ?? 0,
        output: m.limit?.output ?? 0,
        free: m.free === true,
      }))
    out.push({
      id,
      spec: entry.spec,
      name: pInfo.name,
      npm: pInfo.npm ?? "",
      protocol: protocolFromNpm(pInfo.npm ?? ""),
      api: pInfo.api ?? "",
      methods: (entry.auth.methods ?? []).map((m, index) => ({
        index,
        type: m.type,
        label: m.label ?? m.type,
        keyless: m.type === "api" && m.keyless === true,
        placeholder: typeof m.placeholder === "string" ? m.placeholder : "",
      })),
      supportsUsage: typeof entry.auth.usage === "function",
      supportsCheckin: typeof entry.auth.checkin === "function",
      options: Array.isArray(entry.auth.options) ? entry.auth.options : [],
      accounts: keys.map((k) => ({
        id: k,
        providerId: id,
        type: stored[k]?.type ?? "api",
        label: stored[k]?.email ?? stored[k]?.accountId ?? k,
        status: "active",
      })),
      models,
      listError: pInfo.listError ?? "",
    })
  }
  return out
}

async function getLoaderOptions(provider, key) {
  if (loaders.has(key)) return loaders.get(key)
  const a = auths().get(provider)?.auth
  const stored = readAuth()[key]
  let opts = {}
  if (a?.loader && stored) {
    const pInfo = await buildProviderInfo(provider, key)
    opts = (await scopeStorage.run({ provider, key }, () => a.loader(async () => authCopy(key), structuredClone(pInfo)))) ?? {}
  }
  if (!opts.apiKey && stored?.type === "api") {
    opts = { ...opts, apiKey: stored.key }
  }
  loaders.set(key, opts)
  return opts
}

function sdkHeaders(npm, key) {
  if (!key) return {}
  if (npm === "@ai-sdk/anthropic" || npm === "@ai-sdk/google-vertex/anthropic") return { "x-api-key": key }
  if (npm === "@ai-sdk/google") return { "x-goog-api-key": key }
  return { authorization: `Bearer ${key}` }
}

const FRAME_OVERHEAD = 2048
const MAX_FRAME = 64 << 10
const inflight = new Map()

function makeGate(windowSize) {
  let free = windowSize
  let stopped = false
  let wake = null
  const fit = (want) => Math.min(want, free - FRAME_OVERHEAD)
  return {
    take(want) {
      if (stopped) return Promise.resolve(-1)
      const n = fit(want)
      if (n > 0) return Promise.resolve(n)
      return new Promise((resolve) => {
        wake = (ok) => resolve(ok ? fit(want) : -1)
      })
    },
    spend(cost) {
      free -= cost
    },
    add(n) {
      free += n
      if (wake && free > FRAME_OVERHEAD) {
        const w = wake
        wake = null
        w(true)
      }
    },
    stop() {
      stopped = true
      if (wake) {
        const w = wake
        wake = null
        w(false)
      }
    },
  }
}

async function doFetch(id, record, params) {
  const { provider, account, model, npm, url, method, headers, body } = params
  const key = accountKey(provider, account)
  const ctl = record.controller
  try {
    const opts = await scopeStorage.run({ provider, key }, () => getLoaderOptions(provider, key))
    if (ctl.signal.aborted) throw new DOMException("Aborted", "AbortError")
    const h = new Headers()
    for (const [k, v] of Object.entries(sdkHeaders(npm, opts.apiKey))) h.set(k, v)
    for (const [k, v] of Object.entries(opts.headers ?? {})) h.set(k, String(v))
    for (const [k, v] of Object.entries(headers ?? {})) h.set(k, String(v))

    const base = String(opts.baseURL || "").replace(/\/+$/, "")
    let targetUrl = url
    if (!/^https?:\/\//i.test(targetUrl) && base) {
      const rel = targetUrl.startsWith("/") ? targetUrl : `/${targetUrl}`
      targetUrl = base.endsWith("/v1") && rel.startsWith("/v1/") ? base + rel.slice(3) : base + rel
    }

    let decodedBody = undefined
    if (body) {
      const buf = Buffer.from(body, "base64")
      decodedBody = new TextDecoder("utf-8", { fatal: false }).decode(buf)
    }

    const fetchFn = typeof opts.fetch === "function" ? opts.fetch : fetch
    const res = await scopeStorage.run({ provider, key }, () =>
      fetchFn(targetUrl, {
        method: method || "POST",
        headers: h,
        body: decodedBody,
        signal: ctl.signal,
      }),
    )

    const rh = {}
    res.headers.forEach((v, k) => {
      rh[k] = v
    })
    await send({ id, event: "head", status: res.status, headers: rh })

    if (res.body) {
      for await (const chunk of res.body) {
        if (ctl.signal.aborted) break
        const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)
        for (let off = 0; off < bytes.length; ) {
          const n = await record.gate.take(Math.min(MAX_FRAME, bytes.length - off))
          if (n <= 0 || ctl.signal.aborted) break
          const b64 = bytes.subarray(off, off + n).toString("base64")
          record.gate.spend(n + FRAME_OVERHEAD)
          await send(chunkLine(id, b64))
          off += n
        }
      }
    }
    await send({ id, result: null })
  } catch (e) {
    await send({ id, error: { message: String(e?.message ?? e) } })
  } finally {
    record.gate.stop()
    inflight.delete(id)
  }
}

const handlers = {
  async init(p) {
    authPath = p.authPath
    directory = p.directory ?? directory
    userConfig = p.config ?? {}
    chosenOptions = p.options ?? {}
    await loadPlugins(p.plugins ?? [])
    return { plugins: loaded }
  },
  providers: () => listProviders(),
  async setProviderOptions(p) {
    chosenOptions = p?.options ?? {}
    loaders.clear()
    return null
  },
  async apiKey(p) {
    const a = authOf(p.provider)
    const idx = p.method ?? 0
    const m = a.methods?.[idx]
    if (!m || m.type !== "api") throw new Error("not an API key method")
    const at = p.account || freshKey(p.provider)
    if (typeof m.authorize !== "function") {
      await setAuth(at, { type: "api", key: p.key ?? "", metadata: p.inputs ?? {} })
      return { ok: true, provider: p.provider, account: at }
    }
    const r = await scopeStorage.run({ provider: p.provider, key: at }, () => m.authorize(p.inputs ?? {}))
    if (!r || r.type !== "success") return { ok: false, error: r?.error ?? "authorization failed" }
    const targetProvider = r.provider ?? p.provider
    const keyName = targetProvider !== p.provider ? freshKey(targetProvider) : at
    if ("refresh" in r) {
      await setAuth(keyName, { type: "oauth", refresh: r.refresh, access: r.access, expires: r.expires })
    } else {
      await setAuth(keyName, { type: "api", key: r.key ?? p.key ?? "", metadata: r.metadata })
    }
    return { ok: true, provider: targetProvider, account: keyName }
  },
  async authorize(p) {
    const a = authOf(p.provider)
    const idx = p.method ?? 0
    const m = a.methods?.[idx]
    if (!m || m.type !== "oauth") throw new Error("not an oauth method")
    const key = p.account || freshKey(p.provider)
    const authRes = await scopeStorage.run({ provider: p.provider, key }, () =>
      m.authorize(m.prompts?.length ? p.inputs ?? {} : undefined),
    )
    if (authRes?.type === "failed") return { ok: false, error: authRes.error ?? "failed" }
    if (typeof authRes?.callback !== "function") return { ok: false, error: "missing oauth callback" }
    const sid = String(nextSession++)
    sessions.set(sid, { provider: p.provider, key, a: authRes })
    return {
      ok: true,
      session: sid,
      url: authRes.url ?? "",
      instructions: authRes.instructions ?? "",
      method: authRes.method ?? "auto",
      opened: authRes.opened === true,
    }
  },
  async callback(p) {
    const s = sessions.get(String(p.session))
    if (!s) throw new Error("session not found")
    sessions.delete(String(p.session))
    const r = await scopeStorage.run({ provider: s.provider, key: s.key }, () =>
      s.a.method === "code" ? s.a.callback(p.code ?? "") : s.a.callback(),
    )
    if (!r || r.type !== "success") return { ok: false, error: r?.error ?? "callback failed" }
    const targetProvider = r.provider ?? s.provider
    const keyName = targetProvider !== s.provider ? freshKey(targetProvider) : s.key
    if ("refresh" in r) {
      await setAuth(keyName, { type: "oauth", refresh: r.refresh, access: r.access, expires: r.expires })
    } else {
      await setAuth(keyName, { type: "api", key: r.key ?? "" })
    }
    return { ok: true, provider: targetProvider, account: keyName }
  },
  async load(p) {
    const key = accountKey(p.provider, p.account)
    const opts = await scopeStorage.run({ provider: p.provider, key }, () => getLoaderOptions(p.provider, key))
    return {
      baseURL: typeof opts.baseURL === "string" ? opts.baseURL : "",
      apiKey: typeof opts.apiKey === "string" ? opts.apiKey : "",
      headers: opts.headers ?? {},
      fetch: typeof opts.fetch === "function",
    }
  },
  async usage(p) {
    const a = authOf(p.provider)
    if (typeof a.usage !== "function") throw new Error("usage hook not supported")
    const key = accountKey(p.provider, p.account)
    const pInfo = await buildProviderInfo(p.provider, key)
    const u = (await scopeStorage.run({ provider: p.provider, key }, () => a.usage(async () => authCopy(key), pInfo))) ?? {}
    return u
  },
  async checkin(p) {
    const a = authOf(p.provider)
    if (typeof a.checkin !== "function") throw new Error("checkin hook not supported")
    const key = accountKey(p.provider, p.account)
    const pInfo = await buildProviderInfo(p.provider, key)
    const r = (await scopeStorage.run({ provider: p.provider, key }, () => a.checkin(async () => authCopy(key), pInfo))) ?? {}
    return r
  },
  async signOut(p) {
    const keys = p.account ? [p.account] : accountsOf(readAuth(), p.provider)
    for (const k of keys) await removeAuth(k)
    return null
  },
}

const rl = readline.createInterface({ input: process.stdin, terminal: false })
rl.on("line", (line) => {
  if (!line.trim()) return
  let msg
  try {
    msg = JSON.parse(line)
  } catch {
    return
  }
  if (msg.method === "abort") {
    const rec = inflight.get(msg.params?.id)
    if (rec) {
      rec.controller.abort()
      rec.gate.stop()
      inflight.delete(msg.params?.id)
    }
    return
  }
  if (msg.method === "credit") {
    const rec = inflight.get(msg.params?.id)
    if (rec) rec.gate.add(msg.params?.n ?? 0)
    return
  }
  if (msg.method === "fetch") {
    const rec = {
      controller: new AbortController(),
      gate: makeGate(msg.params?.window > 0 ? msg.params.window : 512 << 10),
    }
    inflight.set(msg.id, rec)
    doFetch(msg.id, rec, msg.params ?? {})
    return
  }
  const fn = handlers[msg.method]
  if (!fn) {
    send({ id: msg.id, error: { message: `unknown method: ${msg.method}` } })
    return
  }
  Promise.resolve()
    .then(() => fn(msg.params ?? {}))
    .then(
      (result) => send({ id: msg.id, result: result ?? null }),
      (e) => send({ id: msg.id, error: { message: String(e?.message ?? e) } }),
    )
})
rl.on("close", () => process.exit(0))
