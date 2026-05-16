import {
  getPullContext,
  getShowOutdated,
  notifyRefreshed,
} from "./pr-context.js";
import {
  annotationsFromComments,
  commentCounts,
  fileLevelComments,
  groupCommentsByPath,
} from "./pr-comment-model.js";
import { fetchReviewsWithComments } from "./pr-review-comments.js";

let pullCommentsPromise;
let pullCommentsByPath;
let lastCommentsFetchAt = 0;

export async function loadPullComments({ force = false } = {}) {
  if (pullCommentsPromise && !force && Date.now() - lastCommentsFetchAt < 1000) {
    return pullCommentsPromise;
  }
  pullCommentsPromise = (async () => {
    const ctx = await getPullContext();
    if (!ctx?.apiReviewsUrl) {
      pullCommentsByPath = new Map();
      return pullCommentsByPath;
    }
    const comments = await fetchReviewsWithComments(ctx);
    const pendingReviewIds = new Set(
      comments
        .filter(
          (comment) =>
            comment.review_state === "PENDING" &&
            comment.review_user_id === ctx.signedUserID,
        )
        .map((comment) => comment.pull_request_review_id),
    );
    pullCommentsByPath = groupCommentsByPath(comments, pendingReviewIds);
    lastCommentsFetchAt = Date.now();
    return pullCommentsByPath;
  })().catch((error) => {
    console.warn("Pierre PR bridge: failed to load comments", error);
    pullCommentsByPath = new Map();
    return pullCommentsByPath;
  });
  return pullCommentsPromise;
}

export async function getAnnotationsForPath(path) {
  const byPath = await loadPullComments();
  return annotationsFromComments(byPath, path, {
    includeOutdated: getShowOutdated(),
  });
}

export async function getFileLevelComments(path) {
  const byPath = await loadPullComments();
  return fileLevelComments(byPath, path);
}

export async function getCommentCounts() {
  const byPath = await loadPullComments();
  return commentCounts(byPath);
}

export async function refreshAll() {
  await loadPullComments({ force: true });
  notifyRefreshed();
}

export { subscribeToRefresh } from "./pr-context.js";
