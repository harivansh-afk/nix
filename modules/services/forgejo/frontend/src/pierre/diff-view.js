import { diffUrlFromLocation, isPullFilesPath } from "../shared/repo-path.js";
import { scheduleViewportWork } from "../shared/viewport.js";
import { loadPierre } from "./client.js";
import { getDiffText, getParsedDiff, indexPatchFiles } from "./diff-data.js";
import { pierreDiffRenderOptions } from "./options.js";
import {
  getAnnotationsForPath,
  hasPullContext,
  loadPullComments,
  mountComposer,
  renderCommentAnnotation,
  renderFileLevelComments,
  subscribeToRefresh,
} from "./pr-comments.js";

const diffSelectors = {
  boxes: '#diff-file-boxes .diff-file-box[id^="diff-"]',
  placeholder:
    '.harivan-pierre-diff-target[data-harivan-pierre-placeholder="1"]',
};
const diffState = {
  pending: "pending",
  rendering: "rendering",
  rendered: "rendered",
};
let diffBoxObserver;
let diffBoxObserverContainer;
let diffRenderQueued = false;

function diffPathCandidates(box) {
  const placeholder = pierreDiffPlaceholder(box);
  const values = [
    placeholder?.dataset.newFilename,
    placeholder?.dataset.oldFilename,
    box.dataset.newFilename,
    box.dataset.oldFilename,
  ];
  return values
    .filter(Boolean)
    .map((value) => value.trim())
    .filter((value, index, all) => value && all.indexOf(value) === index);
}

function diffFileForBox(box, byName) {
  for (const path of diffPathCandidates(box)) {
    const file = byName.get(path);
    if (file) return file;
  }
  return null;
}

function pierreDiffPlaceholder(box) {
  return box.querySelector(diffSelectors.placeholder);
}

function shouldRenderDiffBox(box) {
  return box.dataset.harivanPierreMode !== "native";
}

function diffBoxes() {
  return Array.from(document.querySelectorAll(diffSelectors.boxes));
}

function renderableDiffBoxes() {
  return diffBoxes().filter(shouldRenderDiffBox);
}

function showDiffRenderFallback(box, url) {
  const target = pierreDiffPlaceholder(box);
  if (!target) return;
  if (target.querySelector("table.chroma")) return;
  target.classList.add("harivan-pierre-diff-fallback");
  target.replaceChildren();

  const message = document.createElement("span");
  message.textContent = "Diff rendering failed.";
  target.append(message);

  if (url) {
    target.append(" ");
    const link = document.createElement("a");
    link.href = url;
    link.textContent = "Open raw diff";
    target.append(link);
  }
}

function createDiffContainer() {
  return document.createElement("diffs-container");
}

function mountRenderedDiff(placeholder, fileContainer) {
  placeholder.classList.remove(
    "code-diff",
    "harivan-pr-diff",
    "harivan-pierre-diff-fallback",
  );
  placeholder.classList.add("harivan-pierre-diff");
  delete placeholder.dataset.harivanPrDiffIndicators;
  placeholder.replaceChildren(fileContainer);
}

function markDiffRendered(box, placeholder, fileContainer) {
  let marked = false;
  return () => {
    if (marked) return;
    marked = true;
    requestAnimationFrame(() => {
      mountRenderedDiff(placeholder, fileContainer);
      box.dataset.harivanPierreState = diffState.rendered;
      delete box.dataset.harivanPierreQueued;
    });
  };
}

function boxIsPullRequest(box) {
  return box.querySelector('[data-harivan-pierre-pull="1"]') !== null;
}

function boxCanComment(box) {
  return (
    box.querySelector('[data-harivan-pierre-can-comment="1"]') !== null
  );
}

function pathForBox(box, fileDiff) {
  return (
    fileDiff?.name ||
    fileDiff?.prevName ||
    box.dataset.newFilename ||
    box.dataset.oldFilename ||
    null
  );
}

const boxInstances = new WeakMap();

async function refreshAnnotationsForBox(box) {
  const entry = boxInstances.get(box);
  if (!entry) return;
  try {
    const annotations = await getAnnotationsForPath(entry.path);
    entry.instance.setLineAnnotations(annotations);
    // Pierre allocates grid slots for annotations during render(); a bare
    // setLineAnnotations() will not re-run grid layout, so existing rows
    // wouldn't have slots and the wrapper nodes would fall to the bottom.
    // Force a rerender so the slots line up with the right code rows.
    entry.instance.rerender();
  } catch (error) {
    console.warn("Pierre PR bridge: refreshing annotations failed", error);
  }
}

function renderDiffBox(box, fileDiff, cacheKey, pierre) {
  if (box.dataset.harivanPierreState === diffState.rendered) return false;
  if (box.dataset.harivanPierreState === diffState.rendering) return false;

  const body = box.querySelector(".diff-file-body");
  const placeholder = pierreDiffPlaceholder(box);
  if (!body || !placeholder) {
    showDiffFallback(box, cacheKey);
    return false;
  }
  box.dataset.harivanPierreState = diffState.rendering;

  const fileContainer = createDiffContainer();
  const options = pierreDiffRenderOptions();
  const markRendered = markDiffRendered(box, placeholder, fileContainer);
  const isPullRequest = boxIsPullRequest(box);
  const canComment = isPullRequest && boxCanComment(box);
  const path = pathForBox(box, fileDiff);

  options.onLineSelectionEnd = (range) => {
    if (!range) return;
    const prefix = range.side === "additions" ? "R" : "L";
    window.history.replaceState(
      null,
      "",
      `#${box.id || "diff"}${prefix}${range.start}`,
    );
  };
  options.onPostRender = markRendered;

  if (isPullRequest) {
    options.renderAnnotation = renderCommentAnnotation;
    if (canComment && path) {
      options.enableGutterUtility = true;
      options.onGutterUtilityClick = (range) => {
        if (!range) return;
        mountComposer({
          box,
          side: range.side === "deletions" ? "deletions" : "additions",
          lineNumber: range.start,
          path,
        });
      };
    }
  }

  try {
    const instance = new pierre.FileDiff(options);
    const rendered = instance.render({
      fileDiff: {
        ...fileDiff,
        cacheKey: `${cacheKey}:${fileDiff.name || fileDiff.prevName || "file"}`,
      },
      fileContainer,
    });
    if (rendered) markRendered();
    if (isPullRequest && path) {
      boxInstances.set(box, { instance, path });
      getAnnotationsForPath(path)
        .then((annotations) => {
          if (annotations.length === 0) return;
          instance.setLineAnnotations(annotations);
          // Re-run render so Pierre allocates grid slots for the annotation
          // wrapper nodes; otherwise they fall to the bottom of the file.
          instance.rerender();
        })
        .catch((error) => {
          console.warn("Pierre PR bridge: initial annotations failed", error);
        });
      const fileLevelContainer = box.querySelector(
        '[data-harivan-pierre-file-comments="1"]',
      );
      if (fileLevelContainer) {
        renderFileLevelComments({ container: fileLevelContainer, path });
      }
    }
    return true;
  } catch (error) {
    console.warn("Pierre diff rendering failed", error);
    showDiffRenderFallback(box, cacheKey);
    delete box.dataset.harivanPierreState;
    delete box.dataset.harivanPierreQueued;
    return false;
  }
}

function showDiffFallback(box, url) {
  showDiffRenderFallback(box, url);
  delete box.dataset.harivanPierreState;
  delete box.dataset.harivanPierreQueued;
}

function showDiffFallbacks(boxes, url) {
  for (const box of boxes) showDiffFallback(box, url);
}

function markDiffPending(box) {
  if (!shouldRenderDiffBox(box)) return;
  if (box.dataset.harivanPierreState || box.dataset.harivanPierreQueued) return;
  const placeholder = pierreDiffPlaceholder(box);
  if (!placeholder) return;
  box.dataset.harivanPierreState = diffState.pending;
}

function markDiffsPending(boxes) {
  for (const box of boxes) markDiffPending(box);
}

function scheduleDiffRendering(boxes, byName, url, pierre) {
  const renderOne = (box) => {
    if (!shouldRenderDiffBox(box)) return false;
    const fileDiff = diffFileForBox(box, byName);
    if (!fileDiff) {
      showDiffFallback(box, url);
      return false;
    }
    return renderDiffBox(box, fileDiff, url, pierre);
  };

  scheduleViewportWork(
    boxes.filter((box) => {
      const state = box.dataset.harivanPierreState;
      return (
        state !== diffState.rendered &&
        state !== diffState.rendering &&
        !box.dataset.harivanPierreQueued
      );
    }),
    renderOne,
    {
      margin: 1200,
      rootMargin: "1600px 0px",
      markDeferred: (box) => {
        box.dataset.harivanPierreQueued = "1";
      },
    },
  );
}

function queueDiffRendering() {
  if (diffRenderQueued) return;
  diffRenderQueued = true;
  window.setTimeout(() => {
    diffRenderQueued = false;
    renderDiffView();
  }, 0);
}

function observeDiffBoxes() {
  const container = document.querySelector("#diff-file-boxes");
  if (!container) return;
  if (diffBoxObserver && diffBoxObserverContainer === container) return;
  diffBoxObserver?.disconnect();
  diffBoxObserverContainer = container;
  diffBoxObserver = new MutationObserver((records) => {
    let shouldRender = false;
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node.nodeType !== 1) continue;
        const boxes = [];
        if (node.matches?.('.diff-file-box[id^="diff-"]')) boxes.push(node);
        boxes.push(
          ...(node.querySelectorAll?.('.diff-file-box[id^="diff-"]') ?? []),
        );
        for (const box of boxes) {
          if (!shouldRenderDiffBox(box)) continue;
          markDiffPending(box);
          shouldRender = true;
        }
      }
    }
    if (shouldRender) queueDiffRendering();
  });
  diffBoxObserver.observe(container, { childList: true, subtree: true });
}

let refreshSubscribed = false;

function subscribeBoxesToRefresh() {
  if (refreshSubscribed) return;
  refreshSubscribed = true;
  subscribeToRefresh(async () => {
    for (const box of document.querySelectorAll(
      '#diff-file-boxes .diff-file-box[id^="diff-"]',
    )) {
      const entry = boxInstances.get(box);
      if (entry) {
        try {
          const annotations = await getAnnotationsForPath(entry.path);
          entry.instance.setLineAnnotations(annotations);
          entry.instance.rerender();
        } catch (error) {
          console.warn("Pierre PR bridge: refresh failed", error);
        }
        const fileLevelContainer = box.querySelector(
          '[data-harivan-pierre-file-comments="1"]',
        );
        if (fileLevelContainer) {
          renderFileLevelComments({
            container: fileLevelContainer,
            path: entry.path,
          });
        }
      }
    }
  });
}

export async function renderDiffView() {
  const boxes = renderableDiffBoxes();
  if (boxes.length === 0) return;
  const url = diffUrlFromLocation();
  if (!url) return;
  markDiffsPending(boxes);
  observeDiffBoxes();

  if (isPullFilesPath() && hasPullContext()) {
    loadPullComments().catch(() => {});
    subscribeBoxesToRefresh();
  }

  try {
    const pierrePromise = loadPierre();
    const patchPromise = getDiffText(url);
    const pierre = await pierrePromise;
    const parsed = await getParsedDiff(
      url,
      pierre.parsePatchFiles,
      patchPromise,
    );
    const indexed = indexPatchFiles(parsed);
    scheduleDiffRendering(boxes, indexed, url, pierre);
  } catch (error) {
    console.warn("Pierre diff rendering failed", error);
    showDiffFallbacks(boxes, url);
  }
}
