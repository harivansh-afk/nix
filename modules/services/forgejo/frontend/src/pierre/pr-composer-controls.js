import { renderMarkup } from "./pr-markup.js";

export function buildSubmitButtons({ actions, mode, hasPending }) {
  const submits = [];
  const primary = document.createElement("button");
  primary.type = "submit";
  primary.className = "ui submit primary tiny button";

  let primaryMode = "single";
  if (mode === "reply") {
    primary.textContent = "Reply";
  } else if (hasPending) {
    primary.textContent = "Add review comment";
    primaryMode = "queue";
  } else {
    primary.textContent = "Start a review";
    primaryMode = "queue";
  }

  primary.dataset.mode = primaryMode;
  submits.push({ button: primary, mode: primaryMode });
  actions.append(primary);

  if (mode !== "reply" && !hasPending) {
    const single = document.createElement("button");
    single.type = "submit";
    single.className = "ui submit tiny basic button";
    single.textContent = "Add single comment";
    single.dataset.mode = "single";
    submits.push({ button: single, mode: "single" });
    actions.append(single);
  }

  return { submits, primaryMode };
}

export function mountPreviewTabs({ wrapper, textarea, ctx }) {
  const tabs = document.createElement("div");
  tabs.className = "harivan-pierre-composer-tabs";
  const tabWrite = document.createElement("button");
  tabWrite.type = "button";
  tabWrite.className = "harivan-pierre-composer-tab is-active";
  tabWrite.textContent = "Write";
  const tabPreview = document.createElement("button");
  tabPreview.type = "button";
  tabPreview.className = "harivan-pierre-composer-tab";
  tabPreview.textContent = "Preview";
  tabs.append(tabWrite, tabPreview);
  wrapper.append(tabs);

  wrapper.append(textarea);

  const preview = document.createElement("div");
  preview.className = "harivan-pierre-composer-preview markup tw-hidden";
  wrapper.append(preview);

  tabWrite.addEventListener("click", () => {
    tabWrite.classList.add("is-active");
    tabPreview.classList.remove("is-active");
    textarea.classList.remove("tw-hidden");
    preview.classList.add("tw-hidden");
    textarea.focus();
  });

  tabPreview.addEventListener("click", async () => {
    tabPreview.classList.add("is-active");
    tabWrite.classList.remove("is-active");
    textarea.classList.add("tw-hidden");
    preview.classList.remove("tw-hidden");
    preview.textContent = "Loading preview...";
    try {
      const html = await renderMarkup({
        markupUrl: ctx?.markupUrl,
        repoLink: ctx?.repoLink,
        text: textarea.value,
      });
      preview.innerHTML = html || "<em>Nothing to preview</em>";
    } catch (error) {
      preview.textContent = `Preview failed: ${error.message}`;
    }
  });
}
