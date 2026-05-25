// Per-placeholder index: { fileDiff, instance, annotationsByKey: Map<"side:line", annotation> }
const placeholderState = new WeakMap();

// Per-path list of stable annotations (existing review conversations), used as
// the baseline; the active composer (if any) is layered on top.
const conversationsByPath = new Map();

function annotationKey(side, lineNumber) {
  return `${side}:${lineNumber}`;
}

export function setDiffInstance(placeholder, entry) {
  placeholderState.set(placeholder, { ...entry, composer: null });
}

export function getDiffInstance(placeholder) {
  return placeholderState.get(placeholder);
}

// Walk the server-emitted hidden conversation blocks and group them by path.
// Each `<div class="harivan-pierre-conversation-item">` is one review thread for
// a single line + side. We hand its outerHTML to Pierre as the annotation body.
export function loadConversationsFromDom() {
  conversationsByPath.clear();
  const blocks = document.querySelectorAll('[data-harivan-pierre-conversations="1"]');
  for (const block of blocks) {
    const path = block.dataset.path;
    if (!path) continue;
    const items = block.querySelectorAll(".harivan-pierre-conversation-item");
    const annotations = [];
    for (const item of items) {
      const line = Number(item.dataset.line);
      const side = item.dataset.side === "deletions" ? "deletions" : "additions";
      if (!Number.isFinite(line) || line <= 0) continue;
      annotations.push({
        side,
        lineNumber: line,
        metadata: {
          kind: "conversation",
          path,
          conversationId: item.dataset.conversationId,
          html: item.innerHTML,
        },
      });
    }
    conversationsByPath.set(path, annotations);
    block.remove();
  }
}

export function annotationsForPath(path) {
  return (conversationsByPath.get(path) ?? []).slice();
}

export function replaceConversation({ path, lineNumber, side, html, conversationId }) {
  const list = conversationsByPath.get(path) ?? [];
  const key = annotationKey(side, lineNumber);
  const next = list.filter((a) => annotationKey(a.side, a.lineNumber) !== key);
  next.push({
    side,
    lineNumber,
    metadata: { kind: "conversation", path, conversationId, html },
  });
  conversationsByPath.set(path, next);
}

// Compose the current view-state for a placeholder = stable conversations
// + active composer (if any).
export function viewAnnotationsForPlaceholder(placeholder) {
  const state = placeholderState.get(placeholder);
  if (!state) return [];
  const path = placeholder.dataset.harivanPierreFile;
  const base = annotationsForPath(path);
  if (!state.composer) return base;
  // Composer overrides any existing conversation at the same line+side slot.
  const key = annotationKey(state.composer.side, state.composer.lineNumber);
  const filtered = base.filter((a) => annotationKey(a.side, a.lineNumber) !== key);
  filtered.push(state.composer);
  return filtered;
}

export function setComposer(placeholder, composer) {
  const state = placeholderState.get(placeholder);
  if (!state) return;
  state.composer = composer;
}

export function clearComposer(placeholder) {
  const state = placeholderState.get(placeholder);
  if (!state) return;
  state.composer = null;
}
