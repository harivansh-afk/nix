import { replaceRepositoryFileIcons } from "./nonicons.js";
import { renderPullRequestDiffView } from "./diff/pr-native-bridge.js";
import { renderDiffView } from "./pierre/diff-view.js";
import { renderFileView } from "./pierre/file-view.js";

function init() {
  renderFileView();
  renderDiffView();
  renderPullRequestDiffView();
  replaceRepositoryFileIcons();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init, { once: true });
} else {
  init();
}

document.addEventListener("turbo:load", init);
