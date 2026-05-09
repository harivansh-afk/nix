export function diffStyleFromLocation() {
  return new URLSearchParams(window.location.search).get("style") === "split"
    ? "split"
    : "unified";
}

export function diffRenderOptions(overrides = {}) {
  return {
    diffIndicators: "bars",
    diffStyle: diffStyleFromLocation(),
    lineDiffType: "char",
    maxLineDiffLength: 500,
    ...overrides,
  };
}
