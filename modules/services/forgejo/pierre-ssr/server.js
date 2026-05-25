import { createHash } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, join } from "node:path";
import { registerCustomTheme } from "@pierre/diffs";
import { preloadPatchDiff } from "@pierre/diffs/ssr";
import { createHighlighter, createJavaScriptRegexEngine } from "shiki";
import cozyboxDark from "./themes/cozybox-dark.json" with { type: "json" };
import cozyboxLight from "./themes/cozybox-light.json" with { type: "json" };

const socketPath = process.env.PIERRE_SSR_SOCKET ?? "/run/pierre-ssr/pierre.sock";
const cacheDir = process.env.PIERRE_SSR_CACHE_DIR ?? "/var/cache/pierre-ssr";
const maxBodyBytes = Number(process.env.PIERRE_SSR_MAX_BODY_BYTES ?? 16 * 1024 * 1024);

registerCustomTheme("cozybox-dark", () => Promise.resolve(cozyboxDark));
registerCustomTheme("cozybox-light", () => Promise.resolve(cozyboxLight));

const themes = { dark: "cozybox-dark", light: "cozybox-light" };
const highlighter = await createHighlighter({
  themes: [cozyboxDark, cozyboxLight],
  langs: ["text"],
  engine: createJavaScriptRegexEngine(),
});

function sendJson(response, status, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  response.end(body);
}

function requestBody(request) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > maxBodyBytes) {
        reject(Object.assign(new Error("request body too large"), { statusCode: 413 }));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

async function ensureLanguage(language, fileName) {
  const candidates = [language, fileName?.split(".").pop(), "text"].filter(Boolean);
  for (const candidate of candidates) {
    try {
      await highlighter.loadLanguage(candidate);
      return candidate;
    } catch {
    }
  }
  return "text";
}

function cachePath(key) {
  return join(cacheDir, key.slice(0, 2), key + ".json");
}

function forgejoThemeType(theme) {
  if (typeof theme !== "string") return "system";
  if (theme.endsWith("-dark") || theme === "dark") return "dark";
  if (theme.endsWith("-light") || theme === "light") return "light";
  return "system";
}

function diffOptions(payload) {
  return {
    disableFileHeader: true,
    diffStyle: payload.split ? "split" : "unified",
    lineDiffType: payload.lineDiffType === "char" ? "char" : "word-alt",
    theme: themes,
    themeType: forgejoThemeType(payload.theme),
  };
}

function forceRenderedColorScheme(html, themeType) {
  if (themeType !== "dark" && themeType !== "light") return html;
  return html.replaceAll("color-scheme:light dark", "color-scheme:" + themeType);
}

function innerCodeHtml(rendered) {
  const open = rendered.indexOf("<code>");
  const close = rendered.lastIndexOf("</code>");
  if (open === -1 || close === -1 || close < open) return rendered;
  return rendered.slice(open + "<code>".length, close);
}

function splitRenderedLines(html) {
  const marker = '<span class="line">';
  const parts = html.split(marker).slice(1);
  if (parts.length === 0) return html.length > 0 ? [html] : [];
  return parts.map((part) => part.replace(/<\/span>\n?$/, ""));
}

async function tokenize(payload) {
  const code = typeof payload.code === "string" ? payload.code : "";
  const language = typeof payload.language === "string" ? payload.language : "";
  const fileName = typeof payload.fileName === "string" ? payload.fileName : "";
  const theme = typeof payload.theme === "string" ? payload.theme : "system";
  const key = createHash("sha256")
    .update(JSON.stringify({ fileName, language, code, theme, version: 3 }))
    .digest("hex");
  const path = cachePath(key);

  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch {
  }

  const lang = await ensureLanguage(language, fileName);
  const rendered = highlighter.codeToHtml(code, {
    lang,
    themes,
    defaultColor: false,
  });
  const html = innerCodeHtml(rendered);
  const result = { html, lines: splitRenderedLines(html) };
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, JSON.stringify(result));
  return result;
}

async function render(payload) {
  const patch = typeof payload.patch === "string" ? payload.patch : "";
  if (patch === "") return { html: "" };

  const themeType = forgejoThemeType(payload.theme);
  const options = diffOptions(payload);
  const key = createHash("sha256")
    .update(JSON.stringify({ patch, options, themeType, version: 3 }))
    .digest("hex");
  const path = cachePath(key);

  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch {
  }

  const result = await preloadPatchDiff({
    patch,
    options,
    annotations: [],
  });
  const out = { html: forceRenderedColorScheme(result.prerenderedHTML ?? "", themeType) };
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, JSON.stringify(out));
  return out;
}

const server = createServer(async (request, response) => {
  if (request.method !== "POST" || !["/tokenize", "/render"].includes(request.url)) {
    sendJson(response, 404, { error: "not found" });
    return;
  }

  try {
    const payload = JSON.parse(await requestBody(request));
    sendJson(response, 200, request.url === "/render" ? await render(payload) : await tokenize(payload));
  } catch (error) {
    sendJson(response, error.statusCode ?? 500, { error: error.message });
  }
});

await mkdir(dirname(socketPath), { recursive: true });
await mkdir(cacheDir, { recursive: true });
await rm(socketPath, { force: true });
server.listen(socketPath, () => {
  process.stdout.write("pierre-ssr listening on " + socketPath + "\n");
});
