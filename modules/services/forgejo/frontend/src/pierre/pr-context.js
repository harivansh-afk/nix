let pullContextCache;

const refreshListeners = new Set();

export function pullContextSync() {
  if (pullContextCache !== undefined) return pullContextCache;
  const node = document.getElementById("harivan-pierre-pull-context");
  if (!node) {
    pullContextCache = null;
    return null;
  }
  try {
    pullContextCache = JSON.parse(node.textContent || "{}");
  } catch (error) {
    console.warn("Pierre PR bridge: malformed pull-context JSON", error);
    pullContextCache = null;
  }
  return pullContextCache;
}

export function getPullContext() {
  const value = pullContextSync();
  return value
    ? Promise.resolve(value)
    : Promise.reject(new Error("no pull context"));
}

export function hasPullContext() {
  return Boolean(pullContextSync());
}

export function csrfToken() {
  return window.config?.csrfToken || "";
}

export function getShowOutdated() {
  const params = new URLSearchParams(window.location.search);
  const flag = params.get("show-outdated");
  if (flag === "true" || flag === "1") return true;
  if (flag === "false" || flag === "0") return false;
  return Boolean(pullContextSync()?.showOutdatedComments);
}

export function subscribeToRefresh(fn) {
  refreshListeners.add(fn);
  return () => refreshListeners.delete(fn);
}

export function notifyRefreshed() {
  for (const fn of refreshListeners) {
    try {
      fn();
    } catch (error) {
      console.warn("Pierre PR bridge: refresh listener failed", error);
    }
  }
}
