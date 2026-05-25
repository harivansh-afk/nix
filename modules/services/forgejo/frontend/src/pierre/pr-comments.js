import { mountNativeComposer } from "./pr-composer.js";
import { prContext } from "./pr-context.js";
import {
  annotationsForPath,
  clearComposer,
  getDiffInstance,
  setComposer,
  viewAnnotationsForPlaceholder,
} from "./pr-store.js";

// Pierre calls this once during hydrate to pull existing annotations for the
// file. The store is populated from server-emitted hidden conversation blocks
// at page load (see loadConversationsFromDom in pr-store.js).
export function lineAnnotations(placeholder) {
  return annotationsForPath(placeholder?.dataset.harivanPierreFile);
}

function refreshAnnotations(placeholder) {
  const entry = getDiffInstance(placeholder);
  if (!entry?.instance) return;
  entry.instance.setLineAnnotations(viewAnnotationsForPlaceholder(placeholder));
  entry.instance.rerender();
}

// Pierre invokes our gutter callback once per hydrate (inside the
// <diffs-container>'s shadow DOM via slot projection). The button returned
// here lives in the host's light DOM with slot="gutter-utility-slot" applied
// by Pierre's createGutterUtilityContentNode wrapper, so clicks fire normally
// and Pierre's InteractionManager repositions the slot to the hovered row.
export function renderGutterUtility(placeholder) {
  const context = prContext(placeholder);
  if (!context.isPull || !context.canComment) return undefined;

  return (getHoveredRow) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "harivan-pierre-gutter-comment";
    button.title = "Add comment";
    button.setAttribute("aria-label", "Add comment");
    button.textContent = "+";
    button.addEventListener("click", () => {
      const row = getHoveredRow?.();
      if (!row) return;
      const lineNumber = row.start ?? row.lineNumber ?? row.line ?? 0;
      if (!lineNumber) return;
      const side = row.side === "deletions" ? "deletions" : "additions";
      openComposer({ placeholder, context, lineNumber, side });
    });
    return button;
  };
}

function openComposer({ placeholder, context, lineNumber, side }) {
  setComposer(placeholder, {
    side,
    lineNumber,
    metadata: {
      kind: "composer",
      path: context.path,
      side,
      lineNumber,
      newCommentUrl: context.newCommentUrl,
      onClose: () => {
        clearComposer(placeholder);
        refreshAnnotations(placeholder);
      },
    },
  });
  refreshAnnotations(placeholder);
}

// Pierre calls our renderAnnotation per annotation entry. We return a
// light-DOM element; Pierre wraps it in <div data-annotation-slot slot="annotation-{side}-{N}">
// (createAnnotationWrapperNode) and appends to the host's light DOM. The
// matching <slot name="annotation-..."> in shadow DOM (created by Pierre's
// InteractionManager) projects it into the right row.
//
// For "conversation" entries we inject Forgejo's native conversation HTML, so
// every native delegated handler (.resolve-conversation, .comment-form-reply,
// .edit-content, $(document).on('submit', '.conversation-holder form'), etc.)
// fires correctly. For "composer" entries we mount the native new_comment.tmpl
// form; Forgejo's native submit handler will replace the inner conversation-holder
// with the rendered thread on success without our involvement.
export function renderPlaceholderAnnotation(annotation) {
  const meta = annotation?.metadata;
  if (!meta) return undefined;

  if (meta.kind === "conversation") {
    const wrapper = document.createElement("div");
    wrapper.className = "harivan-pierre-conversation";
    wrapper.dataset.path = meta.path ?? "";
    wrapper.dataset.line = String(annotation.lineNumber);
    wrapper.dataset.side = annotation.side;
    wrapper.innerHTML = meta.html ?? "";
    return wrapper;
  }

  if (meta.kind === "composer") {
    const wrapper = document.createElement("div");
    wrapper.className = "harivan-pierre-composer-slot";
    wrapper.dataset.path = meta.path ?? "";
    wrapper.dataset.line = String(annotation.lineNumber);
    wrapper.dataset.side = annotation.side;
    mountNativeComposer({
      host: wrapper,
      newCommentUrl: meta.newCommentUrl,
      path: meta.path,
      lineNumber: meta.lineNumber,
      side: meta.side,
      onClose: meta.onClose,
    }).catch((error) => {
      console.warn("Pierre composer mount failed", error);
      wrapper.textContent = "Failed to load comment form.";
      meta.onClose?.();
    });
    return wrapper;
  }

  return undefined;
}
