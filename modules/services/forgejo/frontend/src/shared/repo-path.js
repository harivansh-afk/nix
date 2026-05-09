export function pathParts(pathname = window.location.pathname) {
  return pathname.split("/").filter(Boolean).map(decodeURIComponent);
}

export function repoPrefix(parts = pathParts()) {
  if (parts.length < 2) return null;
  return `/${encodeURIComponent(parts[0])}/${encodeURIComponent(parts[1])}`;
}

export function diffUrlFromLocation(parts = pathParts()) {
  const prefix = repoPrefix(parts);
  if (!prefix) return null;

  const commitIndex = parts.indexOf("commit");
  if (commitIndex >= 0 && parts[commitIndex + 1]) {
    return `${prefix}/commit/${encodeURIComponent(parts[commitIndex + 1])}.diff`;
  }

  const compareIndex = parts.indexOf("compare");
  if (compareIndex >= 0 && parts[compareIndex + 1]) {
    const compareSpec = parts
      .slice(compareIndex + 1)
      .map(encodeURIComponent)
      .join("/");
    return `${prefix}/compare/${compareSpec}.diff`;
  }

  return null;
}
