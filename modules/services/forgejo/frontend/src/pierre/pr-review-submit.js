// Floating "Submit review" panel for the PR Files page.
//
// Mirrors Forgejo's native new_review form: a textarea + three radios
// (Approve / Request changes / Comment) + submit button. Hits POST
// {issueLink}/files/reviews/submit. Shown only when the signed user has
// permission to comment and either has a pending review queued or has not
// approved yet.

import {
  getPullContext,
  hasPullContext,
  pullContextSync,
  refreshAll,
  submitReview,
  subscribeToRefresh,
} from "./pr-comments.js";

let panel = null;

function ensureMount() {
  if (panel) return panel;
  panel = document.createElement("aside");
  panel.className = "harivan-pierre-review-panel";
  panel.dataset.harivanPierreReviewPanel = "1";

  const heading = document.createElement("div");
  heading.className = "harivan-pierre-review-panel-heading";
  heading.textContent = "Finish your review";
  panel.append(heading);

  const summary = document.createElement("div");
  summary.className = "harivan-pierre-review-panel-summary";
  panel.append(summary);

  const textarea = document.createElement("textarea");
  textarea.className = "harivan-pierre-composer-textarea";
  textarea.rows = 3;
  textarea.placeholder = "Leave a review summary (optional)";
  panel.append(textarea);

  const choices = document.createElement("div");
  choices.className = "harivan-pierre-review-panel-choices";
  const choiceLabels = [
    { value: "comment", label: "Comment" },
    { value: "approve", label: "Approve" },
    { value: "reject", label: "Request changes" },
  ];
  for (const { value, label } of choiceLabels) {
    const wrap = document.createElement("label");
    wrap.className = "harivan-pierre-review-panel-choice";
    const radio = document.createElement("input");
    radio.type = "radio";
    radio.name = "harivan-pierre-review-type";
    radio.value = value;
    if (value === "comment") radio.checked = true;
    wrap.append(radio, document.createTextNode(` ${label}`));
    choices.append(wrap);
  }
  panel.append(choices);

  const actions = document.createElement("div");
  actions.className = "harivan-pierre-review-panel-actions";
  const submit = document.createElement("button");
  submit.type = "button";
  submit.className = "ui primary button";
  submit.textContent = "Submit review";
  const dismiss = document.createElement("button");
  dismiss.type = "button";
  dismiss.className = "ui basic button";
  dismiss.textContent = "Hide";
  actions.append(submit, dismiss);
  panel.append(actions);

  const errorBox = document.createElement("div");
  errorBox.className = "harivan-pierre-composer-error";
  errorBox.hidden = true;
  panel.append(errorBox);

  submit.addEventListener("click", async () => {
    const type =
      panel.querySelector('input[name="harivan-pierre-review-type"]:checked')
        ?.value || "comment";
    const body = textarea.value.trim();
    submit.disabled = true;
    errorBox.hidden = true;
    try {
      await submitReview({
        type:
          type === "approve"
            ? "approve"
            : type === "reject"
              ? "reject"
              : "comment",
        body,
      });
      // Reload so the native review state and timeline both refresh.
      window.location.reload();
    } catch (error) {
      submit.disabled = false;
      errorBox.hidden = false;
      errorBox.textContent = error.message || String(error);
    }
  });

  dismiss.addEventListener("click", () => {
    panel.classList.toggle("is-collapsed");
  });

  document.body.append(panel);
  return panel;
}

function refresh() {
  const ctx = pullContextSync();
  if (!ctx?.canComment) {
    panel?.remove();
    panel = null;
    return;
  }
  ensureMount();
  const summary = panel.querySelector(".harivan-pierre-review-panel-summary");
  if (summary) {
    if (ctx.hasCurrentReview) {
      summary.textContent =
        "You have a pending review on this PR. Add a summary and submit when ready.";
    } else {
      summary.textContent =
        "Add a one-off review by submitting below, or queue comments first and then submit them as a review.";
    }
  }
}

export async function startSubmitReviewPanel() {
  if (!hasPullContext()) return;
  await getPullContext().catch(() => null);
  refresh();
  subscribeToRefresh(refresh);
}
