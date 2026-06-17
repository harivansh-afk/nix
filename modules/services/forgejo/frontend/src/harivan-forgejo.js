import {
  replaceDiffFileTreeIcons,
  replaceRepositoryFileIcons,
} from "./nonicons.js";

let diffTreeObserver = null;
let diffTreeFrame = null;

function scheduleDiffTreeIcons() {
  if (diffTreeFrame !== null) return;
  diffTreeFrame = requestAnimationFrame(() => {
    diffTreeFrame = null;
    replaceDiffFileTreeIcons();
  });
}

function teardownDiffTreeIcons() {
  diffTreeObserver?.disconnect();
  diffTreeObserver = null;
  if (diffTreeFrame !== null) {
    cancelAnimationFrame(diffTreeFrame);
    diffTreeFrame = null;
  }
}

function setupDiffTreeIcons() {
  teardownDiffTreeIcons();
  const tree = document.getElementById("diff-file-tree");
  if (!tree) return;
  replaceDiffFileTreeIcons();
  // Vue mounts the tree asynchronously and appends more rows on "show more
  // files"; re-skin whatever gets added.
  diffTreeObserver = new MutationObserver(scheduleDiffTreeIcons);
  diffTreeObserver.observe(tree, { childList: true, subtree: true });
}

function init() {
  replaceRepositoryFileIcons();
  setupDiffTreeIcons();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init, { once: true });
} else {
  init();
}

document.addEventListener("turbo:load", init);
document.addEventListener("turbo:before-cache", teardownDiffTreeIcons);
