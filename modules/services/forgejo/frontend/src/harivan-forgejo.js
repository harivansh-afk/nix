import { replaceRepositoryFileIcons } from "./nonicons.js";
import { hydratePierreDiffs } from "./pierre/diff-view.js";

function init() {
  replaceRepositoryFileIcons();
  hydratePierreDiffs();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init, { once: true });
} else {
  init();
}

document.addEventListener("turbo:load", init);
