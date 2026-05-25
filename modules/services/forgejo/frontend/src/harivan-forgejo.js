import { replaceRepositoryFileIcons } from "./nonicons.js";

function init() {
  replaceRepositoryFileIcons();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init, { once: true });
} else {
  init();
}

document.addEventListener("turbo:load", init);
