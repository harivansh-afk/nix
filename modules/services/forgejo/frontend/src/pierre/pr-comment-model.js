function placementForComment(comment) {
  const position = Number(comment.position) || 0;
  const original = Number(comment.original_position) || 0;
  if (position > 0) return { side: "additions", lineNumber: position };
  if (original > 0) return { side: "deletions", lineNumber: original };
  return { side: "additions", lineNumber: 0 };
}

function commentIsOutdated(comment) {
  if (!comment.commit_id || !comment.original_commit_id) return false;
  return comment.commit_id !== comment.original_commit_id;
}

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

export function groupCommentsByPath(comments, pendingReviewIds) {
  const byPath = new Map();
  for (const comment of comments) {
    if (!comment || !comment.path) continue;
    const normalized = normalizeComment(comment);
    if (pendingReviewIds?.has(normalized.reviewId)) normalized.isPending = true;
    const entry = byPath.get(comment.path) || [];
    entry.push(normalized);
    byPath.set(comment.path, entry);
  }
  return byPath;
}

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
    reviewId: null,
    resolved: true,
    outdated: false,
    hasPending: false,
    comments: [],
  };
}

export function annotationsFromComments(perPath, path, { includeOutdated }) {
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
      thread.metadata.reviewId = comment.reviewId;
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

export function fileLevelComments(perPath, path) {
  return (perPath.get(path) || [])
    .filter((comment) => comment.isFileLevel)
    .sort(
      (a, b) => Date.parse(a.createdAt || 0) - Date.parse(b.createdAt || 0),
    );
}

export function commentCounts(perPath) {
  const counts = new Map();
  for (const [path, list] of perPath.entries()) {
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
