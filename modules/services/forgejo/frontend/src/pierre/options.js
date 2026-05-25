export function pierreDiffOptions(placeholder) {
  return {
    disableFileHeader: true,
    diffStyle: placeholder?.dataset.harivanPierreSplit === "1" ? "split" : "unified",
    lineDiffType: "word-alt",
    theme: {
      dark: "cozybox-dark",
      light: "cozybox-light",
    },
    themeType: "system",
    // Pierre 1.2.3 gates the gutter utility behind these two flags. Without
    // them, InteractionManager.setup never calls ensureGutterUtilityNode, so
    // no <slot name="gutter-utility-slot"> is created in shadow DOM and the
    // "+" button we return from renderGutterUtility lands in light DOM with
    // nowhere to project (invisible).
    enableGutterUtility: true,
    usesCustomGutterUtility: true,
  };
}
