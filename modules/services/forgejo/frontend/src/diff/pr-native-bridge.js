import { scheduleViewportWork } from "../shared/viewport.js";
import { applyLineDiffs, lineDiffOptionKey } from "./line-dom.js";
import { diffRenderOptions } from "./options.js";
import {
  changedCodeCellGroups,
  diffTableForBox,
  prDiffSelectors,
  pullDiffBoxes,
} from "./pr-dom.js";

const prDiffState = {
  queued: "queued",
  painted: "painted",
};

let prDiffObserver;
let prDiffObserverContainer;
let prDiffRenderQueued = false;

function applyNativeLineDiffs(table, options) {
  const optionKey = lineDiffOptionKey(options);
  for (const group of changedCodeCellGroups(table)) {
    if (group.rows.every((row) => row.dataset.harivanPrDiffAlgorithm === optionKey)) {
      continue;
    }

    applyLineDiffs({
      additions: group.additions,
      deletions: group.deletions,
      options,
    });

    for (const row of group.rows) {
      row.dataset.harivanPrDiffAlgorithm = optionKey;
    }
  }
}

function paintBox(box) {
  const diffTable = diffTableForBox(box);
  if (!diffTable) return false;
  const { nativeDiff, table } = diffTable;
  const options = diffRenderOptions();

  box.dataset.harivanPrDiffState = prDiffState.painted;
  nativeDiff.classList.add("harivan-pr-diff");
  nativeDiff.dataset.harivanPrDiffIndicators = options.diffIndicators;

  applyNativeLineDiffs(table, options);
  return true;
}

function schedulePullDiffPainting(boxes = pullDiffBoxes()) {
  scheduleViewportWork(
    boxes.filter(
      (box) => box.dataset.harivanPrDiffState !== prDiffState.queued,
    ),
    paintBox,
    {
      margin: 1600,
      rootMargin: "1800px 0px",
      markDeferred: (box) => {
        box.dataset.harivanPrDiffState = prDiffState.queued;
      },
    },
  );
}

function queuePullDiffPainting() {
  if (prDiffRenderQueued) return;
  prDiffRenderQueued = true;
  window.setTimeout(() => {
    prDiffRenderQueued = false;
    schedulePullDiffPainting();
  }, 0);
}

function addedNodeMayContainDiffRows(node) {
  if (node.nodeType !== 1) return false;
  if (node.matches?.(".diff-file-box")) {
    return Boolean(node.querySelector(prDiffSelectors.table));
  }
  if (node.querySelector?.(`${prDiffSelectors.boxes} ${prDiffSelectors.table}`)) {
    return true;
  }
  return (
    node.matches?.(prDiffSelectors.rows) ||
    Boolean(node.querySelector?.(prDiffSelectors.rows))
  );
}

function observePullDiffMutations() {
  const container = document.querySelector(prDiffSelectors.container);
  if (!container) return;
  if (prDiffObserver && prDiffObserverContainer === container) return;

  prDiffObserver?.disconnect();
  prDiffObserverContainer = container;
  prDiffObserver = new MutationObserver((records) => {
    if (
      records.some((record) =>
        Array.from(record.addedNodes).some(addedNodeMayContainDiffRows),
      )
    ) {
      queuePullDiffPainting();
    }
  });

  prDiffObserver.observe(container, { childList: true, subtree: true });
}

export function renderPullRequestDiffView() {
  const boxes = pullDiffBoxes();
  if (boxes.length === 0) return;
  observePullDiffMutations();
  schedulePullDiffPainting(boxes);
}

window.__harivanForgejoRepaintPullDiffs = renderPullRequestDiffView;
