import { csrfToken, getPullContext } from "./pr-context.js";
import { refreshAll } from "./pr-store.js";

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
  if (!response.ok) throw new Error(`POST ${url} failed: ${response.status}`);
  return response;
}

function pierreSideToFormSide(side) {
  return side === "deletions" ? "previous" : "proposed";
}

function commentFields(ctx, { path, side, line, body }) {
  return {
    origin: "diff",
    before_commit_id: ctx.beforeCommitID || "",
    latest_commit_id: ctx.afterCommitID || "",
    side: pierreSideToFormSide(side),
    line: line || 0,
    path,
    content: body,
  };
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
  const fields = commentFields(ctx, { path, side, line, body });
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
  if (!replyTo) throw new Error("missing review id");
  const fields = {
    ...commentFields(ctx, { path, side, line, body }),
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
