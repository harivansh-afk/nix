import { renderMarkup } from "./pr-markup.js";

export function renderCommentBody(body, comment, ctx) {
  if (comment.htmlBody) {
    body.innerHTML = comment.htmlBody;
    return;
  }

  body.textContent = comment.body;
  renderMarkup({
    markupUrl: ctx?.markupUrl,
    repoLink: ctx?.repoLink,
    text: comment.body,
  })
    .then((html) => {
      if (html) body.innerHTML = html;
    })
    .catch(() => {});
}
