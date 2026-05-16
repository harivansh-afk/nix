// PR review comment bridge for Pierre.
//
// Reads the pull-context JSON embedded by box.tmpl, fetches existing review
// comments via Forgejo's public API, and exposes the per-line annotations
// plus inline composer / reply / resolve actions used by diff-view.js.
//
// v2 wires up:
//   - existing top-level comments (read-only inline annotation)
//   - new top-level comment via the gutter "+" affordance
//   - reply within an existing thread
//   - resolve / unresolve conversation
//   - outdated marker for comments whose commit_id != original_commit_id

let pullContextCache;
let pullCommentsPromise;
let pullCommentsByPath;
let lastCommentsFetchAt = 0;

function readPullContext() {
  if (pullContextCache !== undefined) return pullContextCache;
  const node = document.getElementById("harivan-pierre-pull-context");
  if (!node) {
    pullContextCache = null;
    return null;
  }
  try {
    pullContextCache = JSON.parse(node.textContent || "{}");
  } catch (error) {
    console.warn("Pierre PR bridge: malformed pull-context JSON", error);
    pullContextCache = null;
  }
  return pullContextCache;
}

export function getPullContext() {
  const value = readPullContext();
  return value
    ? Promise.resolve(value)
    : Promise.reject(new Error("no pull context"));
}

export function hasPullContext() {
  return Boolean(readPullContext());
}

function csrfToken() {
  return window.config?.csrfToken || "";
}

// Map an API comment to {side, lineNumber}. Forgejo's API returns `position`
// for an additions-side comment (line number in the new file) and
// `original_position` for a deletions-side comment (line number in the old
// file). Exactly one of them is non-zero per comment.
function placementForComment(comment) {
  const position = Number(comment.position) || 0;
  const original = Number(comment.original_position) || 0;
  if (position > 0) return { side: "additions", lineNumber: position };
  if (original > 0) return { side: "deletions", lineNumber: original };
  return null;
}

function commentIsOutdated(comment) {
  if (!comment.commit_id || !comment.original_commit_id) return false;
  return comment.commit_id !== comment.original_commit_id;
}

function groupCommentsByPath(comments) {
  const byPath = new Map();
  for (const comment of comments) {
    if (!comment || !comment.path) continue;
    const placement = placementForComment(comment);
    if (!placement) continue;
    const entry = byPath.get(comment.path) || [];
    entry.push({
      id: comment.id,
      side: placement.side,
      lineNumber: placement.lineNumber,
      body: comment.body || "",
      htmlBody: comment.body_html || null,
      user: comment.user || null,
      createdAt: comment.created_at || null,
      htmlUrl: comment.html_url || null,
      resolver: comment.resolver || null,
      outdated: commentIsOutdated(comment),
      commitId: comment.commit_id || null,
      originalCommitId: comment.original_commit_id || null,
      raw: comment,
    });
    byPath.set(comment.path, entry);
  }
  return byPath;
}

export async function loadPullComments({ force = false } = {}) {
  if (pullCommentsPromise && !force && Date.now() - lastCommentsFetchAt < 1000) {
    return pullCommentsPromise;
  }
  pullCommentsPromise = (async () => {
    const ctx = await getPullContext();
    if (!ctx?.apiCommentsUrl) {
      pullCommentsByPath = new Map();
      return pullCommentsByPath;
    }
    const response = await fetch(ctx.apiCommentsUrl, {
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      throw new Error(`comments fetch failed: ${response.status}`);
    }
    const comments = await response.json();
    pullCommentsByPath = groupCommentsByPath(
      Array.isArray(comments) ? comments : [],
    );
    lastCommentsFetchAt = Date.now();
    return pullCommentsByPath;
  })().catch((error) => {
    console.warn("Pierre PR bridge: failed to load comments", error);
    pullCommentsByPath = new Map();
    return pullCommentsByPath;
  });
  return pullCommentsPromise;
}

function threadKey(side, lineNumber) {
  return `${side}:${lineNumber}`;
}

function annotationsFromComments(perPath, path) {
  const comments = perPath.get(path) || [];
  const threads = new Map();
  for (const comment of comments) {
    const key = threadKey(comment.side, comment.lineNumber);
    const existing = threads.get(key);
    if (existing) {
      existing.metadata.comments.push(comment);
      // Thread is resolved iff every comment in it has a resolver. Forgejo
      // marks the whole conversation but we recompute defensively.
      if (!comment.resolver) existing.metadata.resolved = false;
      if (comment.outdated) existing.metadata.outdated = true;
    } else {
      threads.set(key, {
        side: comment.side,
        lineNumber: comment.lineNumber,
        metadata: {
          kind: "pr-thread",
          path,
          line: comment.lineNumber,
          side: comment.side,
          rootCommentId: comment.id,
          resolved: Boolean(comment.resolver),
          outdated: Boolean(comment.outdated),
          comments: [comment],
        },
      });
    }
  }
  return Array.from(threads.values());
}

export async function getAnnotationsForPath(path) {
  const byPath = await loadPullComments();
  return annotationsFromComments(byPath, path);
}

function fmtTimestamp(iso) {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleString();
}

function renderAvatar(user) {
  if (!user) return null;
  const img = document.createElement("img");
  img.className = "harivan-pierre-comment-avatar";
  img.src = user.avatar_url || "";
  img.alt = user.login || "";
  img.width = 20;
  img.height = 20;
  return img;
}

function pierreSideToFormSide(side) {
  return side === "deletions" ? "previous" : "proposed";
}

async function postFormToForgejo(url, fields) {
  const form = new FormData();
  form.set("_csrf", csrfToken());
  for (const [k, v] of Object.entries(fields)) {
    if (v === undefined || v === null) continue;
    form.set(k, typeof v === "boolean" ? (v ? "true" : "false") : String(v));
  }
  const response = await fetch(url, {
    method: "POST",
    credentials: "same-origin",
    headers: { "X-Csrf-Token": csrfToken() },
    body: form,
  });
  if (!response.ok) {
    throw new Error(`POST ${url} failed: ${response.status}`);
  }
  return response;
}

export async function postNewComment({ path, side, line, body }) {
  const ctx = await getPullContext();
  if (!ctx?.createCommentUrl) throw new Error("missing create-comment URL");
  if (!body || !body.trim()) throw new Error("empty comment");
  await postFormToForgejo(ctx.createCommentUrl, {
    origin: "diff",
    before_commit_id: ctx.beforeCommitID || "",
    latest_commit_id: ctx.afterCommitID || "",
    side: pierreSideToFormSide(side),
    line,
    path,
    content: body,
    single_review: true,
  });
  await loadPullComments({ force: true });
  return true;
}

export async function postReplyComment({ path, side, line, body, replyTo }) {
  const ctx = await getPullContext();
  if (!ctx?.createCommentUrl) throw new Error("missing create-comment URL");
  if (!body || !body.trim()) throw new Error("empty comment");
  await postFormToForgejo(ctx.createCommentUrl, {
    origin: "diff",
    before_commit_id: ctx.beforeCommitID || "",
    latest_commit_id: ctx.afterCommitID || "",
    side: pierreSideToFormSide(side),
    line,
    path,
    content: body,
    reply: replyTo,
  });
  await loadPullComments({ force: true });
  return true;
}

export async function toggleResolveConversation({ commentId, resolved }) {
  const ctx = await getPullContext();
  if (!ctx?.resolveConversationUrl) throw new Error("missing resolve URL");
  await postFormToForgejo(ctx.resolveConversationUrl, {
    origin: "diff",
    action: resolved ? "UnResolve" : "Resolve",
    comment_id: commentId,
  });
  await loadPullComments({ force: true });
  return true;
}

function renderCommentItem(comment) {
  const item = document.createElement("article");
  item.className = "harivan-pierre-comment";
  if (comment.id != null) item.dataset.commentId = String(comment.id);

  const header = document.createElement("header");
  header.className = "harivan-pierre-comment-header";
  const avatar = renderAvatar(comment.user);
  if (avatar) header.append(avatar);
  const author = document.createElement("a");
  author.className = "harivan-pierre-comment-author";
  author.textContent =
    comment.user?.login || comment.user?.full_name || "user";
  if (comment.user?.html_url) author.href = comment.user.html_url;
  header.append(author);

  const ts = document.createElement("time");
  ts.className = "harivan-pierre-comment-timestamp";
  ts.dateTime = comment.createdAt || "";
  ts.textContent = fmtTimestamp(comment.createdAt);
  if (comment.htmlUrl) {
    const link = document.createElement("a");
    link.href = comment.htmlUrl;
    link.append(ts);
    header.append(link);
  } else {
    header.append(ts);
  }
  if (comment.outdated) {
    const badge = document.createElement("span");
    badge.className =
      "harivan-pierre-comment-badge harivan-pierre-comment-badge-outdated";
    badge.textContent = "Outdated";
    header.append(badge);
  }
  item.append(header);

  const body = document.createElement("div");
  body.className = "harivan-pierre-comment-body";
  if (comment.htmlBody) {
    body.innerHTML = comment.htmlBody;
  } else {
    body.textContent = comment.body;
  }
  item.append(body);

  return item;
}

function renderThreadActions(meta, refresh) {
  const ctx = readPullContext();
  const canComment = Boolean(ctx?.canComment);
  const wrapper = document.createElement("div");
  wrapper.className = "harivan-pierre-thread-actions";

  if (canComment) {
    const replyBtn = document.createElement("button");
    replyBtn.type = "button";
    replyBtn.className = "ui basic tiny button harivan-pierre-reply-btn";
    replyBtn.textContent = "Reply";
    replyBtn.addEventListener("click", () => {
      const parent = wrapper.parentElement;
      if (!parent) return;
      const existing = parent.querySelector(".harivan-pierre-composer");
      if (existing) {
        existing.remove();
        return;
      }
      const composer = buildComposer({
        path: meta.path,
        side: meta.side,
        lineNumber: meta.line,
        mode: "reply",
        replyTo: meta.rootCommentId,
        onSubmitted: refresh,
      });
      parent.append(composer);
      composer.querySelector("textarea")?.focus();
    });
    wrapper.append(replyBtn);

    const resolveBtn = document.createElement("button");
    resolveBtn.type = "button";
    resolveBtn.className = "ui basic tiny button harivan-pierre-resolve-btn";
    resolveBtn.textContent = meta.resolved ? "Unresolve" : "Resolve";
    resolveBtn.addEventListener("click", async () => {
      resolveBtn.disabled = true;
      try {
        await toggleResolveConversation({
          commentId: meta.rootCommentId,
          resolved: meta.resolved,
        });
        refresh?.();
      } catch (error) {
        console.warn("Pierre PR bridge: resolve toggle failed", error);
        resolveBtn.disabled = false;
      }
    });
    wrapper.append(resolveBtn);
  }

  return wrapper;
}

export function makeRenderCommentAnnotation(refresh) {
  return function renderCommentAnnotation(annotation) {
    const meta = annotation?.metadata;
    if (!meta || meta.kind !== "pr-thread") return undefined;

    const wrapper = document.createElement("div");
    wrapper.className = "harivan-pierre-comment-thread";
    if (meta.resolved)
      wrapper.classList.add("harivan-pierre-comment-thread-resolved");
    if (meta.outdated)
      wrapper.classList.add("harivan-pierre-comment-thread-outdated");
    wrapper.dataset.path = meta.path || "";
    wrapper.dataset.line = String(meta.line || "");
    wrapper.dataset.side = meta.side || "";
    wrapper.dataset.rootCommentId = String(meta.rootCommentId || "");

    if (meta.resolved) {
      const banner = document.createElement("div");
      banner.className = "harivan-pierre-thread-banner";
      banner.textContent = "Conversation resolved";
      wrapper.append(banner);
    }

    for (const comment of meta.comments) {
      wrapper.append(renderCommentItem(comment));
    }

    wrapper.append(renderThreadActions(meta, refresh));
    return wrapper;
  };
}

function buildComposer({
  path,
  side,
  lineNumber,
  mode,
  replyTo,
  onSubmitted,
}) {
  const wrapper = document.createElement("form");
  wrapper.className = "harivan-pierre-composer";
  wrapper.dataset.side = side;
  wrapper.dataset.line = String(lineNumber);
  wrapper.dataset.mode = mode;

  const heading = document.createElement("div");
  heading.className = "harivan-pierre-composer-heading";
  heading.textContent =
    mode === "reply"
      ? `Reply on ${path} ${side === "deletions" ? "L" : "R"}${lineNumber}`
      : `Comment on ${path} ${side === "deletions" ? "L" : "R"}${lineNumber}`;
  wrapper.append(heading);

  const textarea = document.createElement("textarea");
  textarea.className = "harivan-pierre-composer-textarea";
  textarea.placeholder =
    mode === "reply" ? "Leave a reply" : "Leave a comment";
  textarea.rows = 4;
  wrapper.append(textarea);

  const actions = document.createElement("div");
  actions.className = "harivan-pierre-composer-actions";
  const submit = document.createElement("button");
  submit.type = "submit";
  submit.className = "ui primary button";
  submit.textContent = mode === "reply" ? "Reply" : "Comment";
  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "ui basic button";
  cancel.textContent = "Cancel";
  actions.append(submit, cancel);
  wrapper.append(actions);

  cancel.addEventListener("click", () => {
    wrapper.remove();
  });

  wrapper.addEventListener("submit", async (event) => {
    event.preventDefault();
    submit.disabled = true;
    try {
      if (mode === "reply") {
        await postReplyComment({
          path,
          side,
          line: lineNumber,
          body: textarea.value,
          replyTo,
        });
      } else {
        await postNewComment({
          path,
          side,
          line: lineNumber,
          body: textarea.value,
        });
      }
      wrapper.remove();
      onSubmitted?.();
    } catch (error) {
      console.warn("Pierre PR bridge: comment submit failed", error);
      submit.disabled = false;
      const err =
        wrapper.querySelector(".harivan-pierre-composer-error") ||
        document.createElement("div");
      err.className = "harivan-pierre-composer-error";
      err.textContent = String(error.message || error);
      if (!err.isConnected) wrapper.append(err);
    }
  });

  return wrapper;
}

export function mountComposer({ box, side, lineNumber, path, onSubmitted }) {
  const existing = box.querySelector(".harivan-pierre-composer");
  if (existing) existing.remove();
  const composer = buildComposer({
    path,
    side,
    lineNumber,
    mode: "new",
    onSubmitted,
  });
  box.append(composer);
  composer.querySelector("textarea")?.focus();
}
