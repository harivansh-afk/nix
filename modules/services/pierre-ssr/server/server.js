// pierre-ssr: server-side Pierre diff renderer.
//
// Listens on a unix socket (PIERRE_SSR_SOCKET) and exposes one route:
//   POST /render  Content-Type: application/json
//     body: { patch: string, options?: object, key?: string }
//     resp: { html: string }
//
// Per-file unified-diff patches go in; per-file Pierre HTML comes out.
// Results are cached by sha256(patch + JSON(options)) in memory (LRU)
// and on disk under PIERRE_SSR_CACHE_DIR. Diffs between two fixed git
// SHAs are immutable, so disk cache entries never need invalidation.
//
// Themes: cozybox-dark and cozybox-light are registered at startup to
// match the in-browser theme set the old client renderer used. Callers
// that do not pass options.theme get the system-resolved cozybox pair.

import http from "node:http";
import fs from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { registerCustomTheme } from "@pierre/diffs";
import { preloadPatchDiff } from "@pierre/diffs/ssr";

const SOCKET =
  process.env.PIERRE_SSR_SOCKET || "/run/pierre-ssr/render.sock";
const CACHE_DIR =
  process.env.PIERRE_SSR_CACHE_DIR || "/var/cache/pierre-ssr";
const LRU_MAX = Number(process.env.PIERRE_SSR_LRU_MAX || 512);

const cozyboxDark = {
  name: "cozybox-dark",
  type: "dark",
  colors: {
    "editor.background": "#141414",
    "editor.foreground": "#ebdbb2",
    foreground: "#ebdbb2",
    focusBorder: "#5b84de",
    "selection.background": "#504945",
    "editor.selectionBackground": "#504945",
    "editor.lineHighlightBackground": "#1e1e1e",
    "editorCursor.foreground": "#ebdbb2",
    "editorLineNumber.foreground": "#928374",
    "editorLineNumber.activeForeground": "#d5c4a1",
    "gitDecoration.addedResourceForeground": "#8ec97c",
    "gitDecoration.modifiedResourceForeground": "#5b84de",
    "gitDecoration.deletedResourceForeground": "#ea6962",
    "terminal.ansiRed": "#ea6962",
    "terminal.ansiGreen": "#8ec97c",
    "terminal.ansiYellow": "#d79921",
    "terminal.ansiBlue": "#5b84de",
    "terminal.ansiMagenta": "#d3869b",
    "terminal.ansiCyan": "#8ec07c",
  },
  tokenColors: [
    { scope: ["comment", "punctuation.definition.comment"], settings: { foreground: "#928374", fontStyle: "italic" } },
    { scope: ["string", "constant.other.symbol"], settings: { foreground: "#8ec97c" } },
    { scope: ["constant.numeric", "constant.language.boolean"], settings: { foreground: "#d3869b" } },
    { scope: ["constant", "variable.language"], settings: { foreground: "#d79921" } },
    { scope: ["keyword", "storage", "storage.type", "storage.modifier"], settings: { foreground: "#ea6962" } },
    { scope: ["variable", "identifier", "meta.definition.variable"], settings: { foreground: "#ebdbb2" } },
    { scope: ["variable.parameter", "variable.parameter.function"], settings: { foreground: "#d5c4a1" } },
    { scope: ["support.function", "entity.name.function", "meta.function-call", "variable.function"], settings: { foreground: "#5b84de" } },
    { scope: ["support.type", "entity.name.type", "entity.name.class", "support.class"], settings: { foreground: "#d3869b" } },
    { scope: ["keyword.operator", "punctuation", "meta.brace"], settings: { foreground: "#a89984" } },
    { scope: ["keyword.operator.logical", "keyword.operator.arithmetic", "keyword.operator.comparison"], settings: { foreground: "#8ec07c" } },
    { scope: ["entity.name.tag", "support.type.property-name", "meta.object-literal.key"], settings: { foreground: "#fabd2f" } },
    { scope: ["invalid", "invalid.illegal"], settings: { foreground: "#ea6962", fontStyle: "bold" } },
  ],
};

const cozyboxLight = {
  name: "cozybox-light",
  type: "light",
  colors: {
    "editor.background": "#dcdcdc",
    "editor.foreground": "#282828",
    foreground: "#282828",
    focusBorder: "#4261a5",
    "selection.background": "#c3c7c9",
    "editor.selectionBackground": "#c3c7c9",
    "editor.lineHighlightBackground": "#d3d3d3",
    "editorCursor.foreground": "#282828",
    "editorLineNumber.foreground": "#7c7c7c",
    "editorLineNumber.activeForeground": "#504945",
    "gitDecoration.addedResourceForeground": "#427b58",
    "gitDecoration.modifiedResourceForeground": "#4261a5",
    "gitDecoration.deletedResourceForeground": "#c5524a",
    "terminal.ansiRed": "#c5524a",
    "terminal.ansiGreen": "#427b58",
    "terminal.ansiYellow": "#b57614",
    "terminal.ansiBlue": "#4261a5",
    "terminal.ansiMagenta": "#8f3f71",
    "terminal.ansiCyan": "#3c7678",
  },
  tokenColors: [
    { scope: ["comment", "punctuation.definition.comment"], settings: { foreground: "#7c7c7c", fontStyle: "italic" } },
    { scope: ["string", "constant.other.symbol"], settings: { foreground: "#427b58" } },
    { scope: ["constant.numeric", "constant.language.boolean"], settings: { foreground: "#8f3f71" } },
    { scope: ["constant", "variable.language"], settings: { foreground: "#b57614" } },
    { scope: ["keyword", "storage", "storage.type", "storage.modifier"], settings: { foreground: "#c5524a" } },
    { scope: ["variable", "identifier", "meta.definition.variable"], settings: { foreground: "#282828" } },
    { scope: ["variable.parameter", "variable.parameter.function"], settings: { foreground: "#504945" } },
    { scope: ["support.function", "entity.name.function", "meta.function-call", "variable.function"], settings: { foreground: "#4261a5" } },
    { scope: ["support.type", "entity.name.type", "entity.name.class", "support.class"], settings: { foreground: "#8f3f71" } },
    { scope: ["keyword.operator", "punctuation", "meta.brace"], settings: { foreground: "#665c54" } },
    { scope: ["keyword.operator.logical", "keyword.operator.arithmetic", "keyword.operator.comparison"], settings: { foreground: "#3c7678" } },
    { scope: ["entity.name.tag", "support.type.property-name", "meta.object-literal.key"], settings: { foreground: "#b57614" } },
    { scope: ["invalid", "invalid.illegal"], settings: { foreground: "#c5524a", fontStyle: "bold" } },
  ],
};

registerCustomTheme("cozybox-dark", () => Promise.resolve(cozyboxDark));
registerCustomTheme("cozybox-light", () => Promise.resolve(cozyboxLight));

const defaultTheme = { dark: "cozybox-dark", light: "cozybox-light" };
const defaultOptions = {
  diffIndicators: "bars",
  diffStyle: "unified",
  lineDiffType: "char",
  maxLineDiffLength: 500,
  disableFileHeader: true,
  theme: defaultTheme,
  themeType: "system",
};

// Tiny LRU. Map preserves insertion order in JS.
class LRU {
  constructor(max) {
    this.max = max;
    this.map = new Map();
  }
  get(key) {
    if (!this.map.has(key)) return undefined;
    const value = this.map.get(key);
    this.map.delete(key);
    this.map.set(key, value);
    return value;
  }
  set(key, value) {
    if (this.map.has(key)) this.map.delete(key);
    this.map.set(key, value);
    if (this.map.size > this.max) {
      const oldest = this.map.keys().next().value;
      this.map.delete(oldest);
    }
  }
}

const memoryCache = new LRU(LRU_MAX);
const inflight = new Map();

function cacheKeyFor(patch, options) {
  const hash = crypto.createHash("sha256");
  hash.update(patch);
  hash.update("\0");
  hash.update(JSON.stringify(options ?? null));
  return hash.digest("hex");
}

function diskPathFor(key) {
  return path.join(CACHE_DIR, key.slice(0, 2), key + ".html");
}

async function readDisk(key) {
  try {
    return await fs.readFile(diskPathFor(key), "utf8");
  } catch (err) {
    if (err.code === "ENOENT") return null;
    throw err;
  }
}

async function writeDisk(key, html) {
  const filePath = diskPathFor(key);
  const dir = path.dirname(filePath);
  await fs.mkdir(dir, { recursive: true });
  const tmp = filePath + "." + process.pid + ".tmp";
  await fs.writeFile(tmp, html, "utf8");
  await fs.rename(tmp, filePath);
}

async function render(patch, options) {
  const mergedOptions = { ...defaultOptions, ...(options || {}) };
  const result = await preloadPatchDiff({ patch, options: mergedOptions });
  return result.prerenderedHTML;
}

async function renderCached(patch, options) {
  const key = cacheKeyFor(patch, options);

  const memHit = memoryCache.get(key);
  if (memHit) return { html: memHit, source: "memory" };

  const diskHit = await readDisk(key);
  if (diskHit) {
    memoryCache.set(key, diskHit);
    return { html: diskHit, source: "disk" };
  }

  let pending = inflight.get(key);
  if (!pending) {
    pending = (async () => {
      const html = await render(patch, options);
      memoryCache.set(key, html);
      // Best-effort disk write. Don't fail the response on disk errors.
      writeDisk(key, html).catch((err) => {
        console.warn("pierre-ssr: disk cache write failed", err.message);
      });
      return html;
    })().finally(() => {
      inflight.delete(key);
    });
    inflight.set(key, pending);
  }
  const html = await pending;
  return { html, source: "render" };
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new Error("body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

const BODY_LIMIT = Number(process.env.PIERRE_SSR_BODY_LIMIT || 8 * 1024 * 1024);

const server = http.createServer(async (req, res) => {
  res.setHeader("Connection", "close");
  if (req.method === "GET" && req.url === "/healthz") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }
  if (req.method !== "POST" || req.url !== "/render") {
    res.writeHead(404);
    res.end();
    return;
  }
  try {
    const raw = await readBody(req, BODY_LIMIT);
    const body = JSON.parse(raw.toString("utf8"));
    if (typeof body.patch !== "string" || body.patch.length === 0) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "patch required" }));
      return;
    }
    const { html, source } = await renderCached(body.patch, body.options);
    res.writeHead(200, {
      "Content-Type": "application/json",
      "X-Pierre-Cache": source,
    });
    res.end(JSON.stringify({ html }));
  } catch (err) {
    console.warn("pierre-ssr: render error", err && err.stack ? err.stack : err);
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: String(err && err.message ? err.message : err) }));
  }
});

async function start() {
  await fs.mkdir(CACHE_DIR, { recursive: true });
  // Unlink stale socket from a previous crash; systemd will set perms.
  if (existsSync(SOCKET)) {
    try {
      await fs.unlink(SOCKET);
    } catch (err) {
      if (err.code !== "ENOENT") throw err;
    }
  }
  await fs.mkdir(path.dirname(SOCKET), { recursive: true }).catch(() => {});
  server.listen(SOCKET, () => {
    // 0660 so the forgejo group can also connect via systemd SocketGroup.
    fs.chmod(SOCKET, 0o660).catch(() => {});
    console.log("pierre-ssr listening on", SOCKET);
  });
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    console.log("pierre-ssr: received", signal, "shutting down");
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 5000).unref();
  });
}

start().catch((err) => {
  console.error("pierre-ssr: startup failed", err);
  process.exit(1);
});
