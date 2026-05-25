import { pierre } from "./client.js";
import { pierreDiffOptions } from "./options.js";
import { renderAnnotation } from "./pr-comment-render.js";
import {
  lineAnnotations,
  renderGutterUtility,
} from "./pr-comments.js";
import {
  loadConversationsFromDom,
  setDiffInstance,
  viewAnnotationsForPlaceholder,
} from "./pr-store.js";

let patchPromise;

function diffUrl() {
  const url = new URL(window.location.href);
  if (url.pathname.endsWith("/files")) {
    url.pathname = url.pathname.slice(0, -"/files".length) + ".diff";
    url.search = "";
    url.hash = "";
    return url.href;
  }
  if (!url.pathname.endsWith(".diff")) {
    url.pathname += ".diff";
  }
  url.search = "";
  url.hash = "";
  return url.href;
}

async function loadPatchFiles() {
  if (!patchPromise) {
    patchPromise = fetch(diffUrl(), {
      credentials: "same-origin",
      headers: { "X-Requested-With": "XMLHttpRequest" },
    })
      .then((response) => {
        if (!response.ok) throw new Error(`diff request failed: ${response.status}`);
        return response.text();
      })
      .then((text) => pierre.parsePatchFiles(text).flatMap((patch) => patch.files || []));
  }
  return patchPromise;
}

function matchFile(files, name) {
  return files.find((file) => file.name === name || file.prevName === name);
}

async function hydratePlaceholder(placeholder) {
  if (placeholder.dataset.harivanPierreHydrated === "1") return;
  placeholder.dataset.harivanPierreHydrated = "1";

  let fileDiff;
  try {
    fileDiff = matchFile(await loadPatchFiles(), placeholder.dataset.harivanPierreFile);
  } catch (error) {
    console.warn("Pierre diff metadata load failed", error);
  }

  try {
    const instance = new pierre.FileDiff({
      ...pierreDiffOptions(placeholder),
      renderAnnotation,
      renderGutterUtility: renderGutterUtility(placeholder),
    });
    // Seed the store entry before hydrate so the gutter handler can write a
    // composer annotation through it without racing the assignment below.
    setDiffInstance(placeholder, { instance, fileDiff });
    // Declarative shadow DOM (<template shadowrootmode="open">) populated
    // placeholder.shadowRoot at HTML parse time, so we do not pass
    // prerenderedHTML; Pierre's prerenderHTMLIfNecessary leaves a populated
    // shadow root untouched.
    instance.hydrate({
      fileContainer: placeholder,
      fileDiff,
      lineAnnotations: lineAnnotations(placeholder),
    });
    // Apply the full view-state (existing conversations + composer slot if any)
    // so Pierre projects each annotation into a slot at the matching row.
    instance.setLineAnnotations(viewAnnotationsForPlaceholder(placeholder));
  } catch (error) {
    console.warn("Pierre diff hydration failed", error);
    delete placeholder.dataset.harivanPierreHydrated;
  }
}

export function hydratePierreDiffs() {
  // Read all server-emitted hidden conversation blocks before any FileDiff is
  // created so lineAnnotations() returns the right baseline at hydrate time.
  loadConversationsFromDom();
  for (const placeholder of document.querySelectorAll('[data-harivan-pierre-placeholder="1"]')) {
    void hydratePlaceholder(placeholder);
  }
}
