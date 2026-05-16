import { attachAutocomplete } from "./pr-autocomplete.js";
import { postNewComment, postReplyComment } from "./pr-api.js";
import {
  buildSubmitButtons,
  mountPreviewTabs,
} from "./pr-composer-controls.js";
import { pullContextSync } from "./pr-context.js";

function buildComposer({
  path,
  side,
  lineNumber,
  mode,
  replyTo,
  prefill,
}) {
  const ctx = pullContextSync();
  const wrapper = document.createElement("form");
  wrapper.className = "harivan-pierre-composer";
  wrapper.dataset.side = side;
  wrapper.dataset.line = String(lineNumber);
  wrapper.dataset.mode = mode;

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
  attachAutocomplete(textarea, ctx?.postersUrl);
  mountPreviewTabs({ wrapper, textarea, ctx });

  const actions = document.createElement("div");
  actions.className = "harivan-pierre-composer-actions";
  const hasPending = Boolean(ctx?.hasCurrentReview);
  const { submits, primaryMode } = buildSubmitButtons({
    actions,
    mode,
    hasPending,
  });

  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "ui submit tiny basic button";
  cancel.textContent = "Cancel";
  actions.append(cancel);
  wrapper.append(actions);

  cancel.addEventListener("click", () => wrapper.remove());

  let chosenMode = primaryMode;
  for (const { button, mode: submitMode } of submits) {
    button.addEventListener("click", () => {
      chosenMode = submitMode;
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

export function openReplyComposer({ meta, replyTo, prefill }) {
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
