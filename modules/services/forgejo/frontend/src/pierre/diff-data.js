import { fetchText } from "../shared/fetch.js";

const diffTextCache = new Map();
const diffParseCache = new Map();

function preloadedDiffPromise(url) {
  const preload = window.__harivanForgejoDiffPreload;
  if (!preload || preload.url !== url) return null;
  return preload.textPromise || null;
}

export function getDiffText(url) {
  const cached = diffTextCache.get(url);
  if (cached) return cached;

  const tracked = (preloadedDiffPromise(url) || fetchText(url)).catch(
    (error) => {
      diffTextCache.delete(url);
      throw error;
    },
  );
  diffTextCache.set(url, tracked);
  return tracked;
}

export function getParsedDiff(url, parsePatchFiles, patchPromise) {
  const cached = diffParseCache.get(url);
  if (cached) return cached;

  const parsed = (patchPromise || getDiffText(url))
    .then((patch) => parsePatchFiles(patch, `harivan:${url}`))
    .catch((error) => {
      diffParseCache.delete(url);
      throw error;
    });
  diffParseCache.set(url, parsed);
  return parsed;
}

export function indexPatchFiles(parsed) {
  const files = parsed.flatMap((patch) => patch.files || []);
  const byName = new Map();
  for (const file of files) {
    if (file.name) byName.set(file.name, file);
    if (file.prevName) byName.set(file.prevName, file);
  }
  return byName;
}
