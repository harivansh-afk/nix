export function isNearViewport(element, margin = 1200) {
  const rect = element.getBoundingClientRect();
  return rect.bottom >= -margin && rect.top <= window.innerHeight + margin;
}

export function sortByViewport(elements, margin = 1200) {
  return elements
    .map((element, index) => ({
      element,
      index,
      top: element.getBoundingClientRect().top,
      visible: isNearViewport(element, margin),
    }))
    .sort((a, b) => {
      if (a.visible !== b.visible) return a.visible ? -1 : 1;
      return a.top - b.top || a.index - b.index;
    })
    .map(({ element }) => element);
}

export function runWhenIdle(callback) {
  const runIdle =
    window.requestIdleCallback ||
    ((idleCallback) =>
      window.setTimeout(() => idleCallback({ timeRemaining: () => 0 }), 1));
  runIdle(callback);
}

export function scheduleViewportWork(
  elements,
  run,
  { margin = 1200, rootMargin = "1600px 0px", markDeferred } = {},
) {
  const deferred = [];
  let completedInitial = 0;

  for (const element of sortByViewport(elements, margin)) {
    if (isNearViewport(element, margin) || completedInitial === 0) {
      if (run(element)) completedInitial += 1;
    } else {
      markDeferred?.(element);
      deferred.push(element);
    }
  }

  if (deferred.length === 0) return;

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          observer.unobserve(entry.target);
          run(entry.target);
        }
      },
      { rootMargin },
    );
    for (const element of deferred) observer.observe(element);
    return;
  }

  for (const element of deferred) runWhenIdle(() => run(element));
}
