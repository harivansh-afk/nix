import { diffChars, diffWordsWithSpace } from "diff";

function cleanLastNewline(contents) {
  return contents.replace(/\n$|\r\n$/, "");
}

function pushOrJoinSpan({
  item,
  spans,
  enableJoin,
  isNeutral = false,
  isLastItem = false,
}) {
  const previous = spans.at(-1);
  if (!previous || isLastItem || !enableJoin) {
    spans.push([isNeutral ? 0 : 1, item.value]);
    return;
  }

  const previousIsNeutral = previous[0] === 0;
  if (
    isNeutral === previousIsNeutral ||
    (isNeutral && item.value.length === 1 && !previousIsNeutral)
  ) {
    previous[1] += item.value;
    return;
  }

  spans.push([isNeutral ? 0 : 1, item.value]);
}

function activeSpanRanges(spans) {
  const ranges = [];
  let offset = 0;
  for (const [active, value] of spans) {
    if (active === 1) ranges.push({ start: offset, end: offset + value.length });
    offset += value.length;
  }
  return ranges;
}

export function changedLineRanges(deletionLine, additionLine, options) {
  if (
    deletionLine == null ||
    additionLine == null ||
    options.lineDiffType === "none"
  ) {
    return { additions: [], deletions: [] };
  }

  const cleanDeletion = cleanLastNewline(deletionLine);
  const cleanAddition = cleanLastNewline(additionLine);
  if (
    cleanDeletion.length > options.maxLineDiffLength ||
    cleanAddition.length > options.maxLineDiffLength
  ) {
    return { additions: [], deletions: [] };
  }

  const diff =
    options.lineDiffType === "char"
      ? diffChars(cleanDeletion, cleanAddition)
      : diffWordsWithSpace(cleanDeletion, cleanAddition);
  const additions = [];
  const deletions = [];
  const enableJoin = options.lineDiffType === "word-alt";
  const lastItem = diff.at(-1);

  for (const item of diff) {
    const isLastItem = item === lastItem;
    if (!item.added && !item.removed) {
      pushOrJoinSpan({
        item,
        spans: deletions,
        enableJoin,
        isNeutral: true,
        isLastItem,
      });
      pushOrJoinSpan({
        item,
        spans: additions,
        enableJoin,
        isNeutral: true,
        isLastItem,
      });
    } else if (item.removed) {
      pushOrJoinSpan({ item, spans: deletions, enableJoin, isLastItem });
    } else {
      pushOrJoinSpan({ item, spans: additions, enableJoin, isLastItem });
    }
  }

  return {
    additions: activeSpanRanges(additions),
    deletions: activeSpanRanges(deletions),
  };
}
