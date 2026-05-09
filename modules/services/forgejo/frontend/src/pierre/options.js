import { diffRenderOptions } from "../diff/options.js";
import { pierreTheme } from "./themes.js";

export function pierreDiffRenderOptions(overrides = {}) {
  return {
    ...diffRenderOptions(),
    disableFileHeader: true,
    enableLineSelection: true,
    theme: pierreTheme,
    ...overrides,
  };
}

export function pierreFileRenderOptions(overrides = {}) {
  return {
    disableFileHeader: true,
    enableLineSelection: true,
    overflow: "scroll",
    theme: pierreTheme,
    ...overrides,
  };
}
