import * as pierreModule from "@pierre/diffs";
import cozyboxDark from "./themes/cozybox-dark.json" with { type: "json" };
import cozyboxLight from "./themes/cozybox-light.json" with { type: "json" };

let registered = false;
if (!registered) {
  pierreModule.registerCustomTheme("cozybox-dark", () => Promise.resolve(cozyboxDark));
  pierreModule.registerCustomTheme("cozybox-light", () => Promise.resolve(cozyboxLight));
  registered = true;
}

export const pierre = pierreModule;
