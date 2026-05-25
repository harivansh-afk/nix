import { fetchNativeCommentForm } from "./pr-api.js";

function setInput(root, name, value) {
  const input = root.querySelector(`[name="${name}"]`);
  if (input) input.value = value;
}

// Mount Forgejo's native composer HTML into the slotted annotation wrapper.
// Forgejo's own `initRepoDiffConversationForm` (web_src/js/features/repo-diff.js)
// already installs a delegated submit handler on `.conversation-holder form`.
// Slotted elements remain in light-DOM ownership so the delegated handler fires
// normally; after submit Forgejo replaces the inner .conversation-holder with
// the rendered thread, and Pierre's slot keeps projecting it into the row.
//
// All this code needs to do is fetch the form, populate path/line/side, and
// optionally initialize ComboMarkdownEditor + Dropzone if Forgejo's bootstrap
// has exposed them globally (see 0002-forgejo-init-globals.patch).
export async function mountNativeComposer({
  host,
  newCommentUrl,
  path,
  lineNumber,
  side,
  onClose,
}) {
  const wrapper = document.createElement("div");
  wrapper.className = "harivan-pierre-native-composer";
  wrapper.innerHTML = await fetchNativeCommentForm(newCommentUrl);

  setInput(wrapper, "line", String(lineNumber || 0));
  setInput(wrapper, "side", side === "deletions" ? "previous" : "proposed");
  setInput(wrapper, "path", path);

  // Wire cancel buttons (markup uses .cancel-code-comment or .quote-reply-cancel).
  const cancelButtons = wrapper.querySelectorAll(
    ".cancel-code-comment, .quote-reply-cancel, [data-button-name='cancel-edit']",
  );
  for (const button of cancelButtons) {
    button.addEventListener("click", (event) => {
      event.preventDefault();
      onClose?.();
    });
  }

  host.append(wrapper);

  // Initialize ComboMarkdownEditor + Dropzone on the new form so the markdown
  // toolbar, @mention autocomplete, preview tab, and attachment uploader work
  // exactly like Forgejo's native inline composer.
  try {
    const dropzone = wrapper.querySelector(".dropzone");
    if (dropzone && typeof window.initDropzone === "function") {
      await window.initDropzone(dropzone);
    }
    const editor = wrapper.querySelector(".combo-markdown-editor");
    if (editor && typeof window.initComboMarkdownEditor === "function") {
      const instance = await window.initComboMarkdownEditor(editor);
      instance?.focus?.();
    }
  } catch (error) {
    console.warn("Pierre composer init hooks failed", error);
  }

  wrapper.querySelector("textarea, input[type='text']")?.focus();
}
