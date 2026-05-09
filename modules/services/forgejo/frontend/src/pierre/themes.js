const cozyboxDark = {
  name: "cozybox-dark",
  type: "dark",
  colors: {
    "editor.background": "#141414",
    "editor.foreground": "#ebdbb2",
    foreground: "#ebdbb2",
    focusBorder: "#5b84de",
    "selection.background": "#504945",
    "editor.selectionBackground": "#504945",
    "editor.lineHighlightBackground": "#1e1e1e",
    "editorCursor.foreground": "#ebdbb2",
    "editorLineNumber.foreground": "#928374",
    "editorLineNumber.activeForeground": "#d5c4a1",
    "gitDecoration.addedResourceForeground": "#8ec97c",
    "gitDecoration.modifiedResourceForeground": "#5b84de",
    "gitDecoration.deletedResourceForeground": "#ea6962",
    "terminal.ansiRed": "#ea6962",
    "terminal.ansiGreen": "#8ec97c",
    "terminal.ansiYellow": "#d79921",
    "terminal.ansiBlue": "#5b84de",
    "terminal.ansiMagenta": "#d3869b",
    "terminal.ansiCyan": "#8ec07c",
  },
  tokenColors: [
    { scope: ["comment", "punctuation.definition.comment"], settings: { foreground: "#928374", fontStyle: "italic" } },
    { scope: ["string", "constant.other.symbol"], settings: { foreground: "#8ec97c" } },
    { scope: ["constant.numeric", "constant.language.boolean"], settings: { foreground: "#d3869b" } },
    { scope: ["constant", "variable.language"], settings: { foreground: "#d79921" } },
    { scope: ["keyword", "storage", "storage.type", "storage.modifier"], settings: { foreground: "#ea6962" } },
    { scope: ["variable", "identifier", "meta.definition.variable"], settings: { foreground: "#ebdbb2" } },
    { scope: ["variable.parameter", "variable.parameter.function"], settings: { foreground: "#d5c4a1" } },
    { scope: ["support.function", "entity.name.function", "meta.function-call", "variable.function"], settings: { foreground: "#5b84de" } },
    { scope: ["support.type", "entity.name.type", "entity.name.class", "support.class"], settings: { foreground: "#d3869b" } },
    { scope: ["keyword.operator", "punctuation", "meta.brace"], settings: { foreground: "#a89984" } },
    { scope: ["keyword.operator.logical", "keyword.operator.arithmetic", "keyword.operator.comparison"], settings: { foreground: "#8ec07c" } },
    { scope: ["entity.name.tag", "support.type.property-name", "meta.object-literal.key"], settings: { foreground: "#fabd2f" } },
    { scope: ["invalid", "invalid.illegal"], settings: { foreground: "#ea6962", fontStyle: "bold" } },
  ],
};

const cozyboxLight = {
  name: "cozybox-light",
  type: "light",
  colors: {
    "editor.background": "#dcdcdc",
    "editor.foreground": "#282828",
    foreground: "#282828",
    focusBorder: "#4261a5",
    "selection.background": "#c3c7c9",
    "editor.selectionBackground": "#c3c7c9",
    "editor.lineHighlightBackground": "#d3d3d3",
    "editorCursor.foreground": "#282828",
    "editorLineNumber.foreground": "#7c7c7c",
    "editorLineNumber.activeForeground": "#504945",
    "gitDecoration.addedResourceForeground": "#427b58",
    "gitDecoration.modifiedResourceForeground": "#4261a5",
    "gitDecoration.deletedResourceForeground": "#c5524a",
    "terminal.ansiRed": "#c5524a",
    "terminal.ansiGreen": "#427b58",
    "terminal.ansiYellow": "#b57614",
    "terminal.ansiBlue": "#4261a5",
    "terminal.ansiMagenta": "#8f3f71",
    "terminal.ansiCyan": "#3c7678",
  },
  tokenColors: [
    { scope: ["comment", "punctuation.definition.comment"], settings: { foreground: "#7c7c7c", fontStyle: "italic" } },
    { scope: ["string", "constant.other.symbol"], settings: { foreground: "#427b58" } },
    { scope: ["constant.numeric", "constant.language.boolean"], settings: { foreground: "#8f3f71" } },
    { scope: ["constant", "variable.language"], settings: { foreground: "#b57614" } },
    { scope: ["keyword", "storage", "storage.type", "storage.modifier"], settings: { foreground: "#c5524a" } },
    { scope: ["variable", "identifier", "meta.definition.variable"], settings: { foreground: "#282828" } },
    { scope: ["variable.parameter", "variable.parameter.function"], settings: { foreground: "#504945" } },
    { scope: ["support.function", "entity.name.function", "meta.function-call", "variable.function"], settings: { foreground: "#4261a5" } },
    { scope: ["support.type", "entity.name.type", "entity.name.class", "support.class"], settings: { foreground: "#8f3f71" } },
    { scope: ["keyword.operator", "punctuation", "meta.brace"], settings: { foreground: "#665c54" } },
    { scope: ["keyword.operator.logical", "keyword.operator.arithmetic", "keyword.operator.comparison"], settings: { foreground: "#3c7678" } },
    { scope: ["entity.name.tag", "support.type.property-name", "meta.object-literal.key"], settings: { foreground: "#b57614" } },
    { scope: ["invalid", "invalid.illegal"], settings: { foreground: "#c5524a", fontStyle: "bold" } },
  ],
};

export const pierreTheme = { dark: "cozybox-dark", light: "cozybox-light" };
let pierreThemesRegistered = false;

export function registerPierreThemes({ registerCustomTheme }) {
  if (pierreThemesRegistered) return;
  registerCustomTheme("cozybox-dark", () => Promise.resolve(cozyboxDark));
  registerCustomTheme("cozybox-light", () => Promise.resolve(cozyboxLight));
  pierreThemesRegistered = true;
}
