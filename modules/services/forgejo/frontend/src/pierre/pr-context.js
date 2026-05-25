export function prContext(placeholder) {
  return {
    canComment: placeholder?.dataset.harivanPierreCanComment === "1",
    isPull: placeholder?.dataset.harivanPierrePull === "1",
    newCommentUrl: placeholder?.dataset.newCommentUrl || "",
    path: placeholder?.dataset.path || placeholder?.dataset.harivanPierreFile || "",
  };
}

