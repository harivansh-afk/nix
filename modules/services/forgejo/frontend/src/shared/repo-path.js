export function pathParts(pathname = window.location.pathname) {
  return pathname.split("/").filter(Boolean).map(decodeURIComponent);
}

export function repoPrefix(parts = pathParts()) {
  if (parts.length < 2) return null;
  return `/${encodeURIComponent(parts[0])}/${encodeURIComponent(parts[1])}`;
}

export function pullsIndex(parts = pathParts()) {
  const pullsAt = parts.indexOf("pulls");
  if (pullsAt < 0) return null;
  const indexPart = parts[pullsAt + 1];
  if (!indexPart) return null;
  const index = Number.parseInt(indexPart, 10);
  if (!Number.isFinite(index)) return null;
  return index;
}

export function isPullFilesPath(parts = pathParts()) {
  const pullsAt = parts.indexOf("pulls");
  if (pullsAt < 0) return false;
  return Boolean(parts[pullsAt + 1]) && parts[pullsAt + 2] === "files";
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

  if (isPullFilesPath(parts)) {
    const index = pullsIndex(parts);
    if (index !== null) {
      return `${prefix}/pulls/${index}.diff`;
    }
  }

  return null;
}
