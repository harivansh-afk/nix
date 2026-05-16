import { attachAutocomplete } from "./pr-autocomplete.js";
import { deleteComment, updateCommentContent } from "./pr-api.js";
import { openReplyComposer } from "./pr-composer.js";

function quoteBody(body) {
  return (
    body
      .split("\n")
      .map((line) => `> ${line}`)
      .join("\n") + "\n\n"
  );
}

function mountInlineEditor(item, comment, ctx) {
  if (item.querySelector(".harivan-pierre-inline-editor")) return;
  const editor = document.createElement("form");
  editor.className = "harivan-pierre-inline-editor";

  const textarea = document.createElement("textarea");
  textarea.className = "harivan-pierre-composer-textarea";
  textarea.rows = 5;
  textarea.value = comment.body;
  editor.append(textarea);
  attachAutocomplete(textarea, ctx?.postersUrl);

  const actions = document.createElement("div");
  actions.className = "harivan-pierre-composer-actions";
  const save = document.createElement("button");
  save.type = "submit";
  save.className = "ui primary button";
  save.textContent = "Save";
  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "ui basic button";
  cancel.textContent = "Cancel";
  actions.append(save, cancel);
  editor.append(actions);

  cancel.addEventListener("click", () => editor.remove());
  editor.addEventListener("submit", async (event) => {
    event.preventDefault();
    save.disabled = true;
    try {
      await updateCommentContent({
        commentId: comment.id,
        content: textarea.value,
      });
    } catch (error) {
      console.warn("Pierre PR bridge: edit failed", error);
      save.disabled = false;
    }
  });

  item.append(editor);
  textarea.focus();
  textarea.setSelectionRange(textarea.value.length, textarea.value.length);
}

export function buildCommentOverflowMenu({ comment, meta, itemEl, ctx }) {
  const own = ctx?.signedUserID && comment.user?.id === ctx.signedUserID;
  const items = [
    {
      label: "Quote reply",
      onSelect: () =>
        openReplyComposer({
          meta,
          replyTo: meta.reviewId,
          prefill: quoteBody(comment.body),
        }),
    },
  ];

  if (comment.htmlUrl) {
    items.push({
      label: "Copy link",
      onSelect: async () => {
        try {
          await navigator.clipboard.writeText(
            new URL(comment.htmlUrl, window.location.origin).toString(),
          );
        } catch {
          // ignore clipboard failure
        }
      },
    });
  }

  if (own) {
    items.push({
      label: "Edit",
      onSelect: () => mountInlineEditor(itemEl, comment, ctx),
    });
    items.push({
      label: "Delete",
      danger: true,
      onSelect: async () => {
        if (!window.confirm("Delete this comment? This cannot be undone.")) {
          return;
        }
        try {
          await deleteComment({ commentId: comment.id });
        } catch (error) {
          console.warn("Pierre PR bridge: delete failed", error);
        }
      },
    });
  }

  const wrap = document.createElement("details");
  wrap.className = "harivan-pierre-overflow";
  const summary = document.createElement("summary");
  summary.className = "harivan-pierre-overflow-summary";
  summary.setAttribute("aria-label", "More actions");
  summary.textContent = "⋯";
  wrap.append(summary);

  const menu = document.createElement("div");
  menu.className = "harivan-pierre-overflow-menu";
  for (const entry of items) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "harivan-pierre-overflow-item";
    if (entry.danger) btn.classList.add("harivan-pierre-overflow-danger");
    btn.textContent = entry.label;
    btn.addEventListener("click", (event) => {
      event.preventDefault();
      wrap.open = false;
      entry.onSelect();
    });
    menu.append(btn);
  }
  wrap.append(menu);

  document.addEventListener("pointerdown", (event) => {
    if (!wrap.open) return;
    if (event.target instanceof Node && wrap.contains(event.target)) return;
    wrap.open = false;
  });

  return wrap;
}
