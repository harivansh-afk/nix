// File tree badges: per-file unresolved comment counts on PR Files page.
//
// Forgejo's diff file tree is rendered by a Vue component into #diff-file-tree
// when the diff data script populates window.config.pageData.diffFileInfo.
// We don't have a clean handle on the Vue instance, so we run a passive
// MutationObserver over the tree DOM and decorate each entry whose
// data-path matches a path with comments. Cheap, idempotent, robust to the
// tree expanding directories lazily.

import {
  getCommentCounts,
  hasPullContext,
  subscribeToRefresh,
} from "./pr-comments.js";

const treeSelectors = {
  container: "#diff-file-tree",
  // The Vue file tree uses `.viewed-file-item-name` and `data-path` on items
  // for files. Folders don't have data-path.
  fileItem: "[data-path]",
};

let countsCache = new Map();
let mountedObserver = false;

function decorateItem(node, counts) {
  const path = node.getAttribute("data-path");
  if (!path) return;
  const data = counts.get(path);
  let badge = node.querySelector(".harivan-pierre-tree-badge");
  if (!data || data.unresolved === 0) {
    badge?.remove();
    return;
  }
  if (!badge) {
    badge = document.createElement("span");
    badge.className = "harivan-pierre-tree-badge";
    badge.title = `${data.unresolved} unresolved`;
    node.append(badge);
  }
  badge.textContent = String(data.unresolved);
}

function decorateAll() {
  const container = document.querySelector(treeSelectors.container);
  if (!container) return;
  for (const node of container.querySelectorAll(treeSelectors.fileItem)) {
    decorateItem(node, countsCache);
  }
}

function ensureObserver() {
  if (mountedObserver) return;
  const container = document.querySelector(treeSelectors.container);
  if (!container) return;
  mountedObserver = true;
  const observer = new MutationObserver(() => decorateAll());
  observer.observe(container, { childList: true, subtree: true });
}

async function refreshCounts() {
  try {
    countsCache = await getCommentCounts();
  } catch (error) {
    console.warn("Pierre PR bridge: tree counts failed", error);
    countsCache = new Map();
  }
  decorateAll();
}

export function startFileTreeBadges() {
  if (!hasPullContext()) return;
  ensureObserver();
  refreshCounts();
  subscribeToRefresh(() => refreshCounts());
}
