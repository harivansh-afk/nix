// Helpers that wrap Forgejo's /markup endpoint for rendering Markdown.
//
// Used by the comment composer's preview tab and by edit-in-place to refresh
// the rendered HTML of a comment after the user changes it.

function csrfToken() {
  return window.config?.csrfToken || "";
}

const previewCache = new Map();

export async function renderMarkup({ markupUrl, repoLink, text, mode = "comment" }) {
  if (!markupUrl) throw new Error("missing markup URL");
  const trimmed = (text || "").trim();
  if (!trimmed) return "";
  const cacheKey = `${markupUrl}:${repoLink || ""}:${mode}:${trimmed}`;
  if (previewCache.has(cacheKey)) return previewCache.get(cacheKey);

  const form = new FormData();
  form.set("_csrf", csrfToken());
  form.set("mode", mode);
  form.set("context", repoLink || "");
  form.set("text", text);
  form.set("wiki", "false");

  const response = await fetch(markupUrl, {
    method: "POST",
    credentials: "same-origin",
    headers: { "X-Csrf-Token": csrfToken() },
    body: form,
  });
  if (!response.ok) {
    throw new Error(`markup ${response.status}`);
  }
  const html = await response.text();
  previewCache.set(cacheKey, html);
  return html;
}
