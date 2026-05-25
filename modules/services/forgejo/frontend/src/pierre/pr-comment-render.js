// Re-export from pr-comments so diff-view has a single import for the
// renderAnnotation callback Pierre invokes per annotation entry.
export { renderPlaceholderAnnotation as renderAnnotation } from "./pr-comments.js";
