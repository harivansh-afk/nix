// PR review comment bridge for Pierre.
//
// Reads the pull-context JSON embedded by box.tmpl, fetches existing review
// comments via Forgejo's public API, and exposes:
//   - getAnnotationsForPath(path): DiffLineAnnotation[] for that file
//   - renderCommentAnnotation(annotation): HTMLElement to mount in Pierre
//   - openComposer({box, fileDiff, range, onSubmit}): mounts a composer over
//     the placeholder and POSTs to the Forgejo new_comment endpoint
//
// This is a v1: it renders top-level comments as read-only annotations and
// supports posting a brand new top-level comment on a selected line. Reply
// threading and resolved/outdated state are not yet wired up - see README
// for the TODO list.

let pullContextPromise;
let pullCommentsPromise;
let pullCommentsByPath;
let lastCommentsFetchAt = 0;

function readPullContext() {
  const node = document.getElementById("harivan-pierre-pull-context");
  if (!node) return null;
  try {
    return JSON.parse(node.textContent || "{}");
  } catch (error) {
    console.warn("Pierre PR bridge: malformed pull-context JSON", error);
    return null;
  }
}

export function getPullContext() {
  if (!pullContextPromise) {
    const value = readPullContext();
    pullContextPromise = value ? Promise.resolve(value) : Promise.reject(new Error("no pull context"));
  }
  return pullContextPromise;
}

export function hasPullContext() {
  return Boolean(readPullContext());
}

function csrfToken() {
  return window.config?.csrfToken || "";
}

// Parse the line number out of a diff_hunk + position pair. Forgejo's API
// returns `position` as the 1-based offset within the diff_hunk where the
// comment is anchored, and `diff_hunk` is the slice of the unified diff that
// contains the line. We walk the hunk and count to derive the line number on
// the new (additions) or old (deletions) side.
function deriveLineFromDiffHunk(diffHunk, position) {
  if (!diffHunk || !Number.isFinite(position) || position < 1) return null;
  const lines = diffHunk.split("\n");
  let hunkOldStart = 0;
  let hunkNewStart = 0;
  let oldLine = 0;
  let newLine = 0;
  let row = 0;
  let side = "additions";
  let lineNumber = null;

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (line.startsWith("@@")) {
      const match = line.match(/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
      if (match) {
        hunkOldStart = Number.parseInt(match[1], 10);
        hunkNewStart = Number.parseInt(match[2], 10);
        oldLine = hunkOldStart - 1;
        newLine = hunkNewStart - 1;
      }
      continue;
    }

    row += 1;
    if (line.startsWith("+")) {
      newLine += 1;
      if (row === position) {
        side = "additions";
        lineNumber = newLine;
        break;
      }
    } else if (line.startsWith("-")) {
      oldLine += 1;
      if (row === position) {
        side = "deletions";
        lineNumber = oldLine;
        break;
      }
    } else {
      newLine += 1;
      oldLine += 1;
      if (row === position) {
        side = "additions";
        lineNumber = newLine;
        break;
      }
    }
  }

  if (lineNumber === null) return null;
  return { side, lineNumber };
}

function commentSideFromApi(comment) {
  // Forgejo also exposes a `line` and may expose a side hint via `original_position`.
  // We try the cheapest signals first.
  if (typeof comment.line === "number" && comment.line > 0) {
    return { side: "additions", lineNumber: comment.line };
  }
  if (typeof comment.old_line === "number" && comment.old_line > 0) {
    return { side: "deletions", lineNumber: comment.old_line };
  }
  return deriveLineFromDiffHunk(comment.diff_hunk, comment.position || comment.original_position);
}

function groupCommentsByPath(comments) {
  const byPath = new Map();
  for (const comment of comments) {
    if (!comment || !comment.path) continue;
    const placement = commentSideFromApi(comment);
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
    pullCommentsByPath = groupCommentsByPath(Array.isArray(comments) ? comments : []);
    lastCommentsFetchAt = Date.now();
    return pullCommentsByPath;
  })().catch((error) => {
    console.warn("Pierre PR bridge: failed to load comments", error);
    pullCommentsByPath = new Map();
    return pullCommentsByPath;
  });
  return pullCommentsPromise;
}

function annotationsFromComments(perPath, path) {
  const comments = perPath.get(path) || [];
  // Group comments on the same line+side into a single annotation thread.
  const threads = new Map();
  for (const comment of comments) {
    const key = `${comment.side}:${comment.lineNumber}`;
    const existing = threads.get(key);
    if (existing) {
      existing.metadata.comments.push(comment);
    } else {
      threads.set(key, {
        side: comment.side,
        lineNumber: comment.lineNumber,
        metadata: {
          kind: "pr-thread",
          path,
          line: comment.lineNumber,
          side: comment.side,
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

export function renderCommentAnnotation(annotation) {
  const meta = annotation?.metadata;
  if (!meta || meta.kind !== "pr-thread") return undefined;

  const wrapper = document.createElement("div");
  wrapper.className = "harivan-pierre-comment-thread";
  wrapper.dataset.path = meta.path || "";
  wrapper.dataset.line = String(meta.line || "");
  wrapper.dataset.side = meta.side || "";

  for (const comment of meta.comments) {
    const item = document.createElement("article");
    item.className = "harivan-pierre-comment";
    if (comment.id != null) item.dataset.commentId = String(comment.id);

    const header = document.createElement("header");
    header.className = "harivan-pierre-comment-header";
    const avatar = renderAvatar(comment.user);
    if (avatar) header.append(avatar);
    const author = document.createElement("a");
    author.className = "harivan-pierre-comment-author";
    author.textContent = comment.user?.login || comment.user?.full_name || "user";
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
    item.append(header);

    const body = document.createElement("div");
    body.className = "harivan-pierre-comment-body";
    if (comment.htmlBody) {
      body.innerHTML = comment.htmlBody;
    } else {
      body.textContent = comment.body;
    }
    item.append(body);

    wrapper.append(item);
  }

  return wrapper;
}

function pierreSideToFormSide(side) {
  return side === "deletions" ? "previous" : "proposed";
}

export async function postNewComment({ path, side, line, body }) {
  const ctx = await getPullContext();
  if (!ctx?.newCommentUrl) throw new Error("missing new-comment URL");
  if (!body || !body.trim()) throw new Error("empty comment");
  const form = new FormData();
  form.set("_csrf", csrfToken());
  form.set("origin", "diff");
  form.set("path", path);
  form.set("side", pierreSideToFormSide(side));
  form.set("line", String(line));
  form.set("content", body);
  // Single-comment style (not part of a pending review). Forgejo treats the
  // absence of is_review as a single comment.
  const response = await fetch(ctx.newCommentUrl, {
    method: "POST",
    credentials: "same-origin",
    headers: { "X-Csrf-Token": csrfToken() },
    body: form,
  });
  if (!response.ok) {
    throw new Error(`new-comment POST failed: ${response.status}`);
  }
  await loadPullComments({ force: true });
  return true;
}

export function mountComposer({ box, side, lineNumber, path, onSubmitted }) {
  const existing = box.querySelector(".harivan-pierre-composer");
  if (existing) {
    existing.remove();
  }

  const wrapper = document.createElement("form");
  wrapper.className = "harivan-pierre-composer";
  wrapper.dataset.side = side;
  wrapper.dataset.line = String(lineNumber);

  const heading = document.createElement("div");
  heading.className = "harivan-pierre-composer-heading";
  heading.textContent = `Comment on ${path} ${side === "deletions" ? "L" : "R"}${lineNumber}`;
  wrapper.append(heading);

  const textarea = document.createElement("textarea");
  textarea.className = "harivan-pierre-composer-textarea";
  textarea.placeholder = "Leave a comment";
  textarea.rows = 4;
  wrapper.append(textarea);

  const actions = document.createElement("div");
  actions.className = "harivan-pierre-composer-actions";
  const submit = document.createElement("button");
  submit.type = "submit";
  submit.className = "ui primary button";
  submit.textContent = "Comment";
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
      await postNewComment({ path, side, line: lineNumber, body: textarea.value });
      wrapper.remove();
      onSubmitted?.();
    } catch (error) {
      console.warn("Pierre PR bridge: comment submit failed", error);
      submit.disabled = false;
      const err = wrapper.querySelector(".harivan-pierre-composer-error") || document.createElement("div");
      err.className = "harivan-pierre-composer-error";
      err.textContent = String(error.message || error);
      if (!err.isConnected) wrapper.append(err);
    }
  });

  box.append(wrapper);
  textarea.focus();
}
