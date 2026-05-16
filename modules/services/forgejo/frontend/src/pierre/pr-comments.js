// PR review comment bridge for Pierre.
//
// One module owns the full lifecycle of code-review comments rendered on top
// of Pierre's diff: load, group, render thread, compose new, reply, quote
// reply, edit, delete, react, resolve, suggestion blocks, outdated filtering,
// and the pending-review batching state machine.

import { attachAutocomplete } from "./pr-autocomplete.js";
import { renderMarkup } from "./pr-markup.js";

let pullContextCache;
let pullCommentsPromise;
let pullCommentsByPath;
let lastCommentsFetchAt = 0;

const refreshListeners = new Set();

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

export function pullContextSync() {
  return readPullContext();
}

function csrfToken() {
  return window.config?.csrfToken || "";
}

function getShowOutdated() {
  const params = new URLSearchParams(window.location.search);
  const flag = params.get("show-outdated");
  if (flag === "true" || flag === "1") return true;
  if (flag === "false" || flag === "0") return false;
  const ctx = readPullContext();
  return Boolean(ctx?.showOutdatedComments);
}

function placementForComment(comment) {
  const position = Number(comment.position) || 0;
  const original = Number(comment.original_position) || 0;
  if (position > 0) return { side: "additions", lineNumber: position };
  if (original > 0) return { side: "deletions", lineNumber: original };
  // File-level comment (no specific line).
  return { side: "additions", lineNumber: 0 };
}

function commentIsOutdated(comment) {
  if (!comment.commit_id || !comment.original_commit_id) return false;
  return comment.commit_id !== comment.original_commit_id;
}

// --- Fetch + group --------------------------------------------------------

function normalizeComment(comment) {
  const placement = placementForComment(comment);
  return {
    id: comment.id,
    side: placement.side,
    lineNumber: placement.lineNumber,
    isFileLevel: placement.lineNumber === 0,
    body: comment.body || "",
    htmlBody: comment.body_html || null,
    user: comment.user || null,
    createdAt: comment.created_at || null,
    updatedAt: comment.updated_at || null,
    htmlUrl: comment.html_url || null,
    resolver: comment.resolver || null,
    outdated: commentIsOutdated(comment),
    commitId: comment.commit_id || null,
    originalCommitId: comment.original_commit_id || null,
    reviewId: comment.pull_request_review_id || 0,
    reactions: comment.reactions || null,
    isPending: false,
    raw: comment,
  };
}

function groupCommentsByPath(comments, pendingReviewIds) {
  const byPath = new Map();
  for (const comment of comments) {
    if (!comment || !comment.path) continue;
    const normalized = normalizeComment(comment);
    if (pendingReviewIds && pendingReviewIds.has(normalized.reviewId)) {
      normalized.isPending = true;
    }
    const entry = byPath.get(comment.path) || [];
    entry.push(normalized);
    byPath.set(comment.path, entry);
  }
  return byPath;
}

async function fetchPendingReviewIds(ctx) {
  if (!ctx?.apiReviewsUrl || !ctx.signedUserID) return new Set();
  try {
    const response = await fetch(ctx.apiReviewsUrl, {
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    });
    if (!response.ok) return new Set();
    const reviews = await response.json();
    return new Set(
      (Array.isArray(reviews) ? reviews : [])
        .filter(
          (r) =>
            r &&
            r.state === "PENDING" &&
            r.user?.id === ctx.signedUserID,
        )
        .map((r) => r.id),
    );
  } catch {
    return new Set();
  }
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
    const [response, pendingReviewIds] = await Promise.all([
      fetch(ctx.apiCommentsUrl, {
        credentials: "same-origin",
        headers: { Accept: "application/json" },
      }),
      fetchPendingReviewIds(ctx),
    ]);
    if (!response.ok) {
      throw new Error(`comments fetch failed: ${response.status}`);
    }
    const comments = await response.json();
    pullCommentsByPath = groupCommentsByPath(
      Array.isArray(comments) ? comments : [],
      pendingReviewIds,
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

// --- Annotation grouping --------------------------------------------------

function threadKey(side, lineNumber) {
  return `${side}:${lineNumber}`;
}

function buildThreadMetadata(path, side, lineNumber) {
  return {
    kind: "pr-thread",
    path,
    line: lineNumber,
    side,
    rootCommentId: null,
    resolved: true,
    outdated: false,
    hasPending: false,
    comments: [],
  };
}

function annotationsFromComments(perPath, path, { includeOutdated }) {
  const comments = (perPath.get(path) || []).filter(
    (comment) => !comment.isFileLevel,
  );
  const threads = new Map();
  for (const comment of comments) {
    if (!includeOutdated && comment.outdated) continue;
    const key = threadKey(comment.side, comment.lineNumber);
    let thread = threads.get(key);
    if (!thread) {
      thread = {
        side: comment.side,
        lineNumber: comment.lineNumber,
        metadata: buildThreadMetadata(path, comment.side, comment.lineNumber),
      };
      threads.set(key, thread);
      thread.metadata.rootCommentId = comment.id;
    }
    thread.metadata.comments.push(comment);
    if (!comment.resolver) thread.metadata.resolved = false;
    if (comment.outdated) thread.metadata.outdated = true;
    if (comment.isPending) thread.metadata.hasPending = true;
  }
  for (const thread of threads.values()) {
    thread.metadata.comments.sort((a, b) => {
      const ta = a.createdAt ? Date.parse(a.createdAt) : 0;
      const tb = b.createdAt ? Date.parse(b.createdAt) : 0;
      return ta - tb;
    });
  }
  return Array.from(threads.values());
}

export async function getAnnotationsForPath(path) {
  const byPath = await loadPullComments();
  return annotationsFromComments(byPath, path, {
    includeOutdated: getShowOutdated(),
  });
}

export async function getFileLevelComments(path) {
  const byPath = await loadPullComments();
  return (byPath.get(path) || [])
    .filter((c) => c.isFileLevel)
    .sort(
      (a, b) => Date.parse(a.createdAt || 0) - Date.parse(b.createdAt || 0),
    );
}

export async function getCommentCounts() {
  const byPath = await loadPullComments();
  const counts = new Map();
  for (const [path, list] of byPath.entries()) {
    let total = 0;
    let unresolved = 0;
    const seenThreads = new Set();
    for (const comment of list) {
      total += 1;
      const key = comment.isFileLevel
        ? `file:${comment.id}`
        : threadKey(comment.side, comment.lineNumber);
      if (seenThreads.has(key)) continue;
      seenThreads.add(key);
      if (!comment.resolver) unresolved += 1;
    }
    counts.set(path, { total, unresolved });
  }
  return counts;
}

export function subscribeToRefresh(fn) {
  refreshListeners.add(fn);
  return () => refreshListeners.delete(fn);
}

function notifyRefreshed() {
  for (const fn of refreshListeners) {
    try {
      fn();
    } catch (error) {
      console.warn("Pierre PR bridge: refresh listener failed", error);
    }
  }
}

export async function refreshAll() {
  await loadPullComments({ force: true });
  notifyRefreshed();
}

// --- POST helpers --------------------------------------------------------

async function postFormToForgejo(url, fields, { acceptJson = false } = {}) {
  const form = new FormData();
  form.set("_csrf", csrfToken());
  for (const [k, v] of Object.entries(fields)) {
    if (v === undefined || v === null) continue;
    form.set(k, typeof v === "boolean" ? (v ? "true" : "false") : String(v));
  }
  const response = await fetch(url, {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "X-Csrf-Token": csrfToken(),
      ...(acceptJson ? { Accept: "application/json" } : {}),
    },
    body: form,
  });
  if (!response.ok) {
    throw new Error(`POST ${url} failed: ${response.status}`);
  }
  return response;
}

function pierreSideToFormSide(side) {
  return side === "deletions" ? "previous" : "proposed";
}

export async function postNewComment({
  path,
  side,
  line,
  body,
  mode = "single",
}) {
  const ctx = await getPullContext();
  if (!ctx?.createCommentUrl) throw new Error("missing create-comment URL");
  if (!body || !body.trim()) throw new Error("empty comment");
  const fields = {
    origin: "diff",
    before_commit_id: ctx.beforeCommitID || "",
    latest_commit_id: ctx.afterCommitID || "",
    side: pierreSideToFormSide(side),
    line: line || 0,
    path,
    content: body,
  };
  if (mode === "single") fields.single_review = true;
  await postFormToForgejo(ctx.createCommentUrl, fields);
  await refreshAll();
  return true;
}

export async function postReplyComment({
  path,
  side,
  line,
  body,
  replyTo,
  mode = "single",
}) {
  const ctx = await getPullContext();
  if (!ctx?.createCommentUrl) throw new Error("missing create-comment URL");
  if (!body || !body.trim()) throw new Error("empty comment");
  const fields = {
    origin: "diff",
    before_commit_id: ctx.beforeCommitID || "",
    latest_commit_id: ctx.afterCommitID || "",
    side: pierreSideToFormSide(side),
    line: line || 0,
    path,
    content: body,
    reply: replyTo,
  };
  if (mode === "single") fields.single_review = true;
  await postFormToForgejo(ctx.createCommentUrl, fields);
  await refreshAll();
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
  await refreshAll();
  return true;
}

export async function updateCommentContent({ commentId, content }) {
  const ctx = await getPullContext();
  if (!ctx?.updateCommentUrl) throw new Error("missing update-comment URL");
  await postFormToForgejo(`${ctx.updateCommentUrl}/${commentId}`, { content });
  await refreshAll();
  return true;
}

export async function deleteComment({ commentId }) {
  const ctx = await getPullContext();
  if (!ctx?.updateCommentUrl) throw new Error("missing update-comment URL");
  await postFormToForgejo(`${ctx.updateCommentUrl}/${commentId}/delete`, {});
  await refreshAll();
  return true;
}

export async function toggleReaction({ commentId, content, mode }) {
  const ctx = await getPullContext();
  if (!ctx?.reactionsBaseUrl) throw new Error("missing reactions URL");
  await postFormToForgejo(
    `${ctx.reactionsBaseUrl}/${commentId}/reactions/${mode}`,
    { content },
  );
  await refreshAll();
  return true;
}

export async function submitReview({ type, body }) {
  const ctx = await getPullContext();
  if (!ctx?.submitReviewUrl) throw new Error("missing submit-review URL");
  await postFormToForgejo(ctx.submitReviewUrl, {
    commit_id: ctx.afterCommitID || "",
    Type: type,
    Content: body || "",
  });
  await refreshAll();
  return true;
}

// --- Rendering ------------------------------------------------------------

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

function isSignedUserOwn(comment, ctx) {
  if (!ctx?.signedUserID) return false;
  return comment.user?.id === ctx.signedUserID;
}

const DEFAULT_REACTIONS = [
  "+1",
  "-1",
  "laugh",
  "hooray",
  "confused",
  "heart",
  "rocket",
  "eyes",
];

function reactionEmoji(name) {
  switch (name) {
    case "+1":
      return "\u{1F44D}";
    case "-1":
      return "\u{1F44E}";
    case "laugh":
      return "\u{1F604}";
    case "hooray":
      return "\u{1F389}";
    case "confused":
      return "\u{1F615}";
    case "heart":
      return "\u{2764}\u{FE0F}";
    case "rocket":
      return "\u{1F680}";
    case "eyes":
      return "\u{1F440}";
    default:
      return name;
  }
}

function renderReactions(comment, ctx) {
  if (!ctx?.canComment) return null;
  const allowed =
    Array.isArray(ctx.allowedReactions) && ctx.allowedReactions.length
      ? ctx.allowedReactions
      : DEFAULT_REACTIONS;
  const counts = new Map();
  if (Array.isArray(comment.reactions)) {
    for (const r of comment.reactions) {
      if (!r || !r.content) continue;
      const entry = counts.get(r.content) || { count: 0, mine: false };
      entry.count += 1;
      if (r.user?.id === ctx.signedUserID) entry.mine = true;
      counts.set(r.content, entry);
    }
  }

  const bar = document.createElement("div");
  bar.className = "harivan-pierre-reactions";

  for (const [content, entry] of counts.entries()) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "harivan-pierre-reaction";
    if (entry.mine) btn.classList.add("is-mine");
    btn.title = content;
    btn.dataset.content = content;
    const emoji = document.createElement("span");
    emoji.className = "harivan-pierre-reaction-emoji";
    emoji.textContent = reactionEmoji(content);
    const num = document.createElement("span");
    num.className = "harivan-pierre-reaction-count";
    num.textContent = String(entry.count);
    btn.append(emoji, num);
    btn.addEventListener("click", async () => {
      btn.disabled = true;
      try {
        await toggleReaction({
          commentId: comment.id,
          content,
          mode: entry.mine ? "unreact" : "react",
        });
      } catch (error) {
        console.warn("Pierre PR bridge: reaction failed", error);
        btn.disabled = false;
      }
    });
    bar.append(btn);
  }

  const picker = document.createElement("details");
  picker.className = "harivan-pierre-reaction-picker";
  const summary = document.createElement("summary");
  summary.className = "harivan-pierre-reaction-add";
  summary.textContent = "+";
  summary.title = "Add reaction";
  picker.append(summary);

  const palette = document.createElement("div");
  palette.className = "harivan-pierre-reaction-palette";
  for (const name of allowed) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "harivan-pierre-reaction-palette-btn";
    btn.title = name;
    btn.textContent = reactionEmoji(name);
    btn.addEventListener("click", async () => {
      picker.open = false;
      try {
        const mine = counts.get(name)?.mine;
        await toggleReaction({
          commentId: comment.id,
          content: name,
          mode: mine ? "unreact" : "react",
        });
      } catch (error) {
        console.warn("Pierre PR bridge: reaction failed", error);
      }
    });
    palette.append(btn);
  }
  picker.append(palette);
  bar.append(picker);

  return bar;
}

function detectSuggestion(comment) {
  const re = /```suggestion\n([\s\S]*?)```/g;
  const matches = [];
  let m;
  while ((m = re.exec(comment.body)) !== null) {
    matches.push({ original: m[0], replacement: m[1] });
  }
  return matches;
}

function renderSuggestionBlocks(comment, bodyContainer) {
  const suggestions = detectSuggestion(comment);
  if (suggestions.length === 0) return;
  for (const suggestion of suggestions) {
    const wrap = document.createElement("div");
    wrap.className = "harivan-pierre-suggestion";
    const header = document.createElement("div");
    header.className = "harivan-pierre-suggestion-header";
    header.textContent = "Suggested change";
    wrap.append(header);
    const pre = document.createElement("pre");
    pre.className = "harivan-pierre-suggestion-body";
    pre.textContent = suggestion.replacement;
    wrap.append(pre);
    const note = document.createElement("div");
    note.className = "harivan-pierre-suggestion-note";
    note.textContent =
      "Forgejo does not support applying suggestions directly. Copy the change manually.";
    wrap.append(note);
    bodyContainer.append(wrap);
  }
}

function renderCommentItem(comment, meta) {
  const ctx = readPullContext();
  const item = document.createElement("article");
  item.className = "harivan-pierre-comment";
  if (comment.id != null) item.dataset.commentId = String(comment.id);
  if (comment.isPending) item.classList.add("harivan-pierre-comment-pending");

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
  if (comment.isPending) {
    const pendingBadge = document.createElement("span");
    pendingBadge.className =
      "harivan-pierre-comment-badge harivan-pierre-comment-badge-pending";
    pendingBadge.textContent = "Pending";
    header.append(pendingBadge);
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
  renderSuggestionBlocks(comment, body);
  item.append(body);

  const reactions = renderReactions(comment, ctx);
  if (reactions) item.append(reactions);

  const own = isSignedUserOwn(comment, ctx);
  const canComment = Boolean(ctx?.canComment);
  if (canComment) {
    const overflow = buildCommentOverflowMenu({
      comment,
      meta,
      own,
      itemEl: item,
    });
    if (overflow) {
      // Stash the menu inside the header so it floats to the right edge.
      header.append(overflow);
    }
  }

  return item;
}

function buildCommentOverflowMenu({ comment, meta, own, itemEl }) {
  const items = [];

  items.push({
    label: "Quote reply",
    onSelect: () => {
      openReplyComposer({
        meta,
        replyTo: meta.rootCommentId,
        prefill:
          comment.body
            .split("\n")
            .map((line) => `> ${line}`)
            .join("\n") + "\n\n",
      });
    },
  });

  if (comment.htmlUrl) {
    items.push({
      label: "Copy link",
      onSelect: async () => {
        try {
          await navigator.clipboard.writeText(
            new URL(comment.htmlUrl, window.location.origin).toString(),
          );
        } catch {
          // ignore clipboard failure
        }
      },
    });
  }

  if (own) {
    items.push({
      label: "Edit",
      onSelect: () => mountInlineEditor(itemEl, comment),
    });
    items.push({
      label: "Delete",
      danger: true,
      onSelect: async () => {
        if (!window.confirm("Delete this comment? This cannot be undone."))
          return;
        try {
          await deleteComment({ commentId: comment.id });
        } catch (error) {
          console.warn("Pierre PR bridge: delete failed", error);
        }
      },
    });
  }

  if (items.length === 0) return null;

  const wrap = document.createElement("details");
  wrap.className = "harivan-pierre-overflow";
  const summary = document.createElement("summary");
  summary.className = "harivan-pierre-overflow-summary";
  summary.setAttribute("aria-label", "More actions");
  summary.textContent = "⋯"; // horizontal ellipsis
  wrap.append(summary);

  const menu = document.createElement("div");
  menu.className = "harivan-pierre-overflow-menu";
  for (const entry of items) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "harivan-pierre-overflow-item";
    if (entry.danger) btn.classList.add("harivan-pierre-overflow-danger");
    btn.textContent = entry.label;
    btn.addEventListener("click", (event) => {
      event.preventDefault();
      wrap.open = false;
      entry.onSelect();
    });
    menu.append(btn);
  }
  wrap.append(menu);

  // Close when clicking outside.
  const closeOnOutside = (event) => {
    if (!wrap.open) return;
    if (event.target instanceof Node && wrap.contains(event.target)) return;
    wrap.open = false;
  };
  document.addEventListener("pointerdown", closeOnOutside);

  return wrap;
}

function mountInlineEditor(item, comment) {
  if (item.querySelector(".harivan-pierre-inline-editor")) return;
  const ctx = readPullContext();
  const editor = document.createElement("form");
  editor.className = "harivan-pierre-inline-editor";

  const textarea = document.createElement("textarea");
  textarea.className = "harivan-pierre-composer-textarea";
  textarea.rows = 5;
  textarea.value = comment.body;
  editor.append(textarea);
  attachAutocomplete(textarea, ctx?.postersUrl);

  const actions = document.createElement("div");
  actions.className = "harivan-pierre-composer-actions";
  const save = document.createElement("button");
  save.type = "submit";
  save.className = "ui primary button";
  save.textContent = "Save";
  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "ui basic button";
  cancel.textContent = "Cancel";
  actions.append(save, cancel);
  editor.append(actions);

  cancel.addEventListener("click", () => editor.remove());

  editor.addEventListener("submit", async (event) => {
    event.preventDefault();
    save.disabled = true;
    try {
      await updateCommentContent({
        commentId: comment.id,
        content: textarea.value,
      });
    } catch (error) {
      console.warn("Pierre PR bridge: edit failed", error);
      save.disabled = false;
    }
  });

  item.append(editor);
  textarea.focus();
  textarea.setSelectionRange(textarea.value.length, textarea.value.length);
}

function renderThreadActions(meta) {
  const ctx = readPullContext();
  const canComment = Boolean(ctx?.canComment);
  const wrapper = document.createElement("div");
  wrapper.className = "harivan-pierre-thread-actions";

  if (canComment) {
    const replyBtn = document.createElement("button");
    replyBtn.type = "button";
    replyBtn.className = "ui basic tiny button harivan-pierre-reply-btn";
    replyBtn.textContent = "Reply";
    replyBtn.addEventListener("click", () =>
      openReplyComposer({ meta, replyTo: meta.rootCommentId }),
    );
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
      } catch (error) {
        console.warn("Pierre PR bridge: resolve toggle failed", error);
        resolveBtn.disabled = false;
      }
    });
    wrapper.append(resolveBtn);
  }

  return wrapper;
}

function openReplyComposer({ meta, replyTo, prefill }) {
  const thread = document.querySelector(
    `.harivan-pierre-comment-thread[data-root-comment-id="${meta.rootCommentId}"]`,
  );
  if (!thread) return;
  const existing = thread.querySelector(".harivan-pierre-composer");
  if (existing) {
    existing.remove();
    return;
  }
  const composer = buildComposer({
    path: meta.path,
    side: meta.side,
    lineNumber: meta.line,
    mode: "reply",
    replyTo,
    prefill,
  });
  thread.append(composer);
  composer.querySelector("textarea")?.focus();
}

export function renderCommentAnnotation(annotation) {
  const meta = annotation?.metadata;
  if (!meta || meta.kind !== "pr-thread") return undefined;

  const wrapper = document.createElement("div");
  wrapper.className = "harivan-pierre-comment-thread";
  if (meta.resolved)
    wrapper.classList.add("harivan-pierre-comment-thread-resolved");
  if (meta.outdated)
    wrapper.classList.add("harivan-pierre-comment-thread-outdated");
  if (meta.hasPending)
    wrapper.classList.add("harivan-pierre-comment-thread-has-pending");
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
    wrapper.append(renderCommentItem(comment, meta));
  }

  wrapper.append(renderThreadActions(meta));
  return wrapper;
}

// --- Composer -------------------------------------------------------------

function buildComposer({
  path,
  side,
  lineNumber,
  mode,
  replyTo,
  prefill,
}) {
  const ctx = readPullContext();
  const wrapper = document.createElement("form");
  wrapper.className = "harivan-pierre-composer";
  wrapper.dataset.side = side;
  wrapper.dataset.line = String(lineNumber);
  wrapper.dataset.mode = mode;

  const heading = document.createElement("div");
  heading.className = "harivan-pierre-composer-heading";
  if (mode === "reply") {
    heading.textContent = `Reply on ${path} ${side === "deletions" ? "L" : "R"}${lineNumber}`;
  } else if (mode === "file") {
    heading.textContent = `Comment on ${path}`;
  } else {
    heading.textContent = `Comment on ${path} ${side === "deletions" ? "L" : "R"}${lineNumber}`;
  }
  wrapper.append(heading);

  const tabs = document.createElement("div");
  tabs.className = "harivan-pierre-composer-tabs";
  const tabWrite = document.createElement("button");
  tabWrite.type = "button";
  tabWrite.className = "harivan-pierre-composer-tab is-active";
  tabWrite.textContent = "Write";
  const tabPreview = document.createElement("button");
  tabPreview.type = "button";
  tabPreview.className = "harivan-pierre-composer-tab";
  tabPreview.textContent = "Preview";
  tabs.append(tabWrite, tabPreview);
  wrapper.append(tabs);

  const textarea = document.createElement("textarea");
  textarea.className = "harivan-pierre-composer-textarea";
  textarea.placeholder =
    mode === "reply"
      ? "Leave a reply"
      : mode === "file"
        ? "Leave a comment on this file"
        : "Leave a comment";
  textarea.rows = 4;
  if (prefill) textarea.value = prefill;
  wrapper.append(textarea);
  attachAutocomplete(textarea, ctx?.postersUrl);

  const preview = document.createElement("div");
  preview.className = "harivan-pierre-composer-preview tw-hidden";
  wrapper.append(preview);

  tabWrite.addEventListener("click", () => {
    tabWrite.classList.add("is-active");
    tabPreview.classList.remove("is-active");
    textarea.classList.remove("tw-hidden");
    preview.classList.add("tw-hidden");
    textarea.focus();
  });
  tabPreview.addEventListener("click", async () => {
    tabPreview.classList.add("is-active");
    tabWrite.classList.remove("is-active");
    textarea.classList.add("tw-hidden");
    preview.classList.remove("tw-hidden");
    preview.textContent = "Loading preview...";
    try {
      const html = await renderMarkup({
        markupUrl: ctx?.markupUrl,
        repoLink: ctx?.repoLink,
        text: textarea.value,
      });
      preview.innerHTML = html || "<em>Nothing to preview</em>";
    } catch (error) {
      preview.textContent = `Preview failed: ${error.message}`;
    }
  });

  const actions = document.createElement("div");
  actions.className = "harivan-pierre-composer-actions";

  const hasPending = Boolean(ctx?.hasCurrentReview);
  const submits = [];

  // Single primary submit, plus an optional chevron menu for the alternate
  // submission mode. Reply mode collapses to one button entirely.
  const primary = document.createElement("button");
  primary.type = "submit";
  primary.className = "ui primary button harivan-pierre-composer-primary";
  let primaryMode = "single";
  let alternate = null;

  if (mode === "reply") {
    primary.textContent = "Reply";
    primaryMode = "single";
  } else if (hasPending) {
    primary.textContent = "Add review comment";
    primaryMode = "queue";
    alternate = { label: "Add single comment", mode: "single" };
  } else {
    primary.textContent = "Start a review";
    primaryMode = "queue";
    alternate = { label: "Add single comment", mode: "single" };
  }
  primary.dataset.mode = primaryMode;
  submits.push({ button: primary, mode: primaryMode });

  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "ui basic button";
  cancel.textContent = "Cancel";

  if (alternate) {
    const group = document.createElement("div");
    group.className = "harivan-pierre-composer-split";
    group.append(primary);

    const chevronWrap = document.createElement("details");
    chevronWrap.className = "harivan-pierre-composer-chevron";
    const chevronSummary = document.createElement("summary");
    chevronSummary.className =
      "ui primary button harivan-pierre-composer-chevron-summary";
    chevronSummary.setAttribute("aria-label", "More submit options");
    chevronSummary.textContent = "▾"; // small down triangle
    chevronWrap.append(chevronSummary);

    const altMenu = document.createElement("div");
    altMenu.className = "harivan-pierre-composer-chevron-menu";
    const altBtn = document.createElement("button");
    altBtn.type = "submit";
    altBtn.className = "harivan-pierre-overflow-item";
    altBtn.textContent = alternate.label;
    altBtn.dataset.mode = alternate.mode;
    submits.push({ button: altBtn, mode: alternate.mode });
    altMenu.append(altBtn);
    chevronWrap.append(altMenu);

    group.append(chevronWrap);
    actions.append(group);
  } else {
    actions.append(primary);
  }

  actions.append(cancel);
  wrapper.append(actions);

  cancel.addEventListener("click", () => wrapper.remove());

  let chosenMode = primaryMode;
  for (const { button, mode: m } of submits) {
    button.addEventListener("click", () => {
      chosenMode = m;
    });
  }

  wrapper.addEventListener("submit", async (event) => {
    event.preventDefault();
    for (const { button } of submits) button.disabled = true;
    try {
      if (mode === "reply") {
        await postReplyComment({
          path,
          side,
          line: lineNumber,
          body: textarea.value,
          replyTo,
          mode: chosenMode,
        });
      } else {
        await postNewComment({
          path,
          side,
          line: mode === "file" ? 0 : lineNumber,
          body: textarea.value,
          mode: chosenMode,
        });
      }
      wrapper.remove();
    } catch (error) {
      console.warn("Pierre PR bridge: comment submit failed", error);
      for (const { button } of submits) button.disabled = false;
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

export function mountComposer({ box, side, lineNumber, path }) {
  const existing = box.querySelector(".harivan-pierre-composer");
  if (existing) existing.remove();
  const composer = buildComposer({
    path,
    side,
    lineNumber,
    mode: "new",
  });
  box.append(composer);
  composer.querySelector("textarea")?.focus();
}

// Only mounts when there are existing file-level comments from the API.
// We do not surface a "Add a comment on this file" trigger because the
// per-line gutter already covers the common case; file-level commenting
// is an edge case that doesn't deserve a permanent affordance.
export function renderFileLevelComments({ container, path }) {
  container.replaceChildren();
  container.classList.remove("harivan-pierre-file-comments-visible");
  getFileLevelComments(path)
    .then((comments) => {
      if (comments.length === 0) return;
      container.classList.add("harivan-pierre-file-comments-visible");
      const wrapper = document.createElement("div");
      wrapper.className = "harivan-pierre-file-comments-wrap";
      for (const comment of comments) {
        wrapper.append(
          renderCommentItem(comment, {
            kind: "pr-thread",
            path,
            line: 0,
            side: "additions",
            rootCommentId: comment.id,
          }),
        );
      }
      container.append(wrapper);
    })
    .catch((error) => {
      console.warn("Pierre PR bridge: file-level comments failed", error);
    });
}
