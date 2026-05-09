import { changedLineRanges } from "./line-ranges.js";

function cleanLastNewline(contents) {
  return contents.replace(/\n$|\r\n$/, "");
}

function unwrapLineDiffSpans(code) {
  const spans = code.querySelectorAll(".added-code, .removed-code");
  for (const span of spans) span.replaceWith(...span.childNodes);
  code.normalize();
}

function textSegments(root, start, end) {
  const segments = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let offset = 0;
  let node;

  while ((node = walker.nextNode())) {
    const nodeStart = offset;
    const nodeEnd = offset + node.data.length;
    const segmentStart = Math.max(start, nodeStart);
    const segmentEnd = Math.min(end, nodeEnd);

    if (segmentStart < segmentEnd) {
      segments.push({
        node,
        start: segmentStart - nodeStart,
        end: segmentEnd - nodeStart,
      });
    }

    offset = nodeEnd;
    if (offset >= end) break;
  }

  return segments;
}

function wrapTextRange(root, range, className) {
  if (range.end <= range.start) return;

  for (const segment of textSegments(root, range.start, range.end).reverse()) {
    let node = segment.node;
    if (segment.end < node.data.length) node.splitText(segment.end);
    if (segment.start > 0) node = node.splitText(segment.start);
    if (!node.data) continue;

    const wrapper = document.createElement("span");
    wrapper.className = className;
    node.parentNode.insertBefore(wrapper, node);
    wrapper.append(node);
  }
}

function codeText(code) {
  return cleanLastNewline(code.textContent ?? "");
}

function applyLineDiffPair(deletionCode, additionCode, options) {
  const ranges = changedLineRanges(
    codeText(deletionCode),
    codeText(additionCode),
    {
      lineDiffType: options.lineDiffType,
      maxLineDiffLength: options.maxLineDiffLength,
    },
  );

  for (const range of ranges.deletions) {
    wrapTextRange(deletionCode, range, "removed-code");
  }
  for (const range of ranges.additions) {
    wrapTextRange(additionCode, range, "added-code");
  }
}

export function lineDiffOptionKey(options) {
  return `${options.lineDiffType}:${options.maxLineDiffLength}`;
}

export function applyLineDiffs({ additions, deletions, options }) {
  for (const code of [...deletions, ...additions]) unwrapLineDiffSpans(code);

  const pairs = Math.min(deletions.length, additions.length);
  for (let index = 0; index < pairs; index += 1) {
    applyLineDiffPair(deletions[index], additions[index], options);
  }
}
