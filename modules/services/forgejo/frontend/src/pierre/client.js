import { registerPierreThemes } from "./themes.js";

let pierreModulePromise;

export async function loadPierre() {
  if (!pierreModulePromise) {
    pierreModulePromise = import("@pierre/diffs")
      .then((module) => {
        registerPierreThemes(module);
        return module;
      })
      .catch((error) => {
        pierreModulePromise = undefined;
        throw error;
      });
  }
  return pierreModulePromise;
}
