async function fetchJson(url) {
  const response = await fetch(url, {
    credentials: "same-origin",
    headers: { Accept: "application/json" },
  });
  if (!response.ok) throw new Error(`GET ${url} failed: ${response.status}`);
  return response.json();
}

function isSignedUsersPendingReview(review, ctx) {
  return (
    review?.state === "PENDING" &&
    ctx?.signedUserID &&
    review.user?.id === ctx.signedUserID
  );
}

async function fetchReviewComments(ctx, review) {
  try {
    const comments = await fetchJson(`${ctx.apiReviewsUrl}/${review.id}/comments`);
    return (Array.isArray(comments) ? comments : []).map((comment) => ({
      ...comment,
      pull_request_review_id: comment.pull_request_review_id || review.id,
      review_state: review.state,
      review_user_id: review.user?.id || null,
    }));
  } catch (error) {
    console.warn(
      `Pierre PR bridge: failed to load review ${review.id} comments`,
      error,
    );
    return [];
  }
}

export async function fetchReviewsWithComments(ctx) {
  if (!ctx?.apiReviewsUrl) return [];
  const reviews = await fetchJson(ctx.apiReviewsUrl);
  const list = Array.isArray(reviews) ? reviews : [];
  const pendingReview = list.find((review) =>
    isSignedUsersPendingReview(review, ctx),
  );
  ctx.hasCurrentReview = Boolean(pendingReview);
  ctx.currentReviewID = pendingReview?.id || null;

  const withComments = list.filter((review) => Number(review.comments_count) > 0);
  return (await Promise.all(withComments.map((r) => fetchReviewComments(ctx, r))))
    .flat();
}
