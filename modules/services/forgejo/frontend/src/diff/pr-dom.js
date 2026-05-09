export const prDiffSelectors = {
  container: "#diff-file-boxes",
  boxes: '#diff-file-boxes .diff-file-box[id^="diff-"]',
  nativeDiff: ".file-body.code-diff",
  rows: "tr[data-line-type]",
  table: "table.chroma",
};

export function isPullRequestDiffPage() {
  return Boolean(document.querySelector(".repository.pull.diff"));
}

export function pullDiffBoxes() {
  if (!isPullRequestDiffPage()) return [];
  return Array.from(document.querySelectorAll(prDiffSelectors.boxes)).filter(
    (box) => box.querySelector(prDiffSelectors.table),
  );
}

export function diffTableForBox(box) {
  const nativeDiff = box.querySelector(prDiffSelectors.nativeDiff);
  const table = nativeDiff?.querySelector(prDiffSelectors.table);
  if (!nativeDiff || !table) return null;
  return { nativeDiff, table };
}

function unifiedCodeCell(row) {
  return row.querySelector(
    ".lines-code:not(.lines-code-old):not(.lines-code-new)",
  );
}

function codeNode(cell) {
  return cell?.querySelector("code.code-inner") ?? null;
}

function changedCodeCells(row) {
  const cells = [];

  const oldCell = row.querySelector(".lines-code-old");
  if (
    oldCell?.classList.contains("del-code") ||
    (row.classList.contains("del-code") && !oldCell?.classList.contains("add-code"))
  ) {
    const code = codeNode(oldCell);
    if (code) cells.push({ side: "deletion", code });
  }

  const newCell = row.querySelector(".lines-code-new");
  if (
    newCell?.classList.contains("add-code") ||
    (row.classList.contains("add-code") && !newCell?.classList.contains("del-code"))
  ) {
    const code = codeNode(newCell);
    if (code) cells.push({ side: "addition", code });
  }

  const unifiedCell = unifiedCodeCell(row);
  if (unifiedCell && row.classList.contains("del-code")) {
    const code = codeNode(unifiedCell);
    if (code) cells.push({ side: "deletion", code });
  } else if (unifiedCell && row.classList.contains("add-code")) {
    const code = codeNode(unifiedCell);
    if (code) cells.push({ side: "addition", code });
  }

  return cells;
}

export function changedCodeCellGroups(table) {
  const groups = [];
  let group = null;

  const flush = () => {
    if (group && (group.additions.length > 0 || group.deletions.length > 0)) {
      groups.push(group);
    }
    group = null;
  };

  for (const row of table.querySelectorAll(prDiffSelectors.rows)) {
    const cells = changedCodeCells(row);
    if (cells.length === 0) {
      flush();
      continue;
    }

    group ??= { additions: [], deletions: [], rows: [] };
    group.rows.push(row);
    for (const cell of cells) {
      group[cell.side === "addition" ? "additions" : "deletions"].push(
        cell.code,
      );
    }
  }
  flush();

  return groups;
}
