export async function fetchNativeCommentForm(url) {
  if (!url) throw new Error("missing comment form URL");
  const response = await fetch(url, {
    credentials: "same-origin",
    headers: { "X-Requested-With": "XMLHttpRequest" },
  });
  if (!response.ok) throw new Error(`comment form request failed: ${response.status}`);
  return response.text();
}
