import { toggleResolveConversation } from "./pr-api.js";
import { renderCommentBody } from "./pr-comment-body.js";
import { buildCommentOverflowMenu } from "./pr-comment-menu.js";
import { openReplyComposer } from "./pr-composer.js";
import { pullContextSync } from "./pr-context.js";
import { renderReactions } from "./pr-reactions.js";
import { getFileLevelComments } from "./pr-store.js";

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

function renderCommentHeader(comment) {
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

  return header;
}

function renderCommentItem(comment, meta) {
  const ctx = pullContextSync();
  const item = document.createElement("article");
  item.className = "harivan-pierre-comment";
  if (comment.id != null) item.dataset.commentId = String(comment.id);

  const header = renderCommentHeader(comment);
  item.append(header);

  const body = document.createElement("div");
  body.className = "harivan-pierre-comment-body render-content markup";
  renderCommentBody(body, comment, ctx);
  item.append(body);

  const reactions = renderReactions(comment, ctx);
  if (reactions) item.append(reactions);

  if (ctx?.canComment) {
    header.append(buildCommentOverflowMenu({ comment, meta, itemEl: item, ctx }));
  }

  return item;
}

function renderThreadActions(meta) {
  const ctx = pullContextSync();
  const wrapper = document.createElement("div");
  wrapper.className = "harivan-pierre-thread-actions";
  if (!ctx?.canComment) return wrapper;

  const replyBtn = document.createElement("button");
  replyBtn.type = "button";
  replyBtn.className = "ui basic tiny button harivan-pierre-reply-btn";
  replyBtn.textContent = "Reply";
  replyBtn.addEventListener("click", () =>
    openReplyComposer({ meta, replyTo: meta.reviewId }),
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

  return wrapper;
}

export function renderCommentAnnotation(annotation) {
  const meta = annotation?.metadata;
  if (!meta || meta.kind !== "pr-thread") return undefined;

  const wrapper = document.createElement("div");
  wrapper.className = "harivan-pierre-comment-thread";
  if (meta.resolved) {
    wrapper.classList.add("harivan-pierre-comment-thread-resolved");
  }
  wrapper.dataset.path = meta.path || "";
  wrapper.dataset.line = String(meta.line || "");
  wrapper.dataset.side = meta.side || "";
  wrapper.dataset.rootCommentId = String(meta.rootCommentId || "");

  for (const comment of meta.comments) {
    wrapper.append(renderCommentItem(comment, meta));
  }
  wrapper.append(renderThreadActions(meta));
  return wrapper;
}

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
            reviewId: comment.reviewId,
          }),
        );
      }
      container.append(wrapper);
    })
    .catch((error) => {
      console.warn("Pierre PR bridge: file-level comments failed", error);
    });
}
