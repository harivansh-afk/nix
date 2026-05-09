export function fetchText(url) {
  return fetch(url, { credentials: "same-origin" }).then((response) => {
    if (!response.ok) throw new Error(response.statusText);
    return response.text();
  });
}
