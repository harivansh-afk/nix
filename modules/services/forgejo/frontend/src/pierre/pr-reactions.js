import { toggleReaction } from "./pr-api.js";

const DEFAULT_REACTIONS = [
  "+1",
  "-1",
  "laugh",
  "hooray",
  "confused",
  "heart",
  "rocket",
  "eyes",
];

function reactionEmoji(name) {
  switch (name) {
    case "+1":
      return "\u{1F44D}";
    case "-1":
      return "\u{1F44E}";
    case "laugh":
      return "\u{1F604}";
    case "hooray":
      return "\u{1F389}";
    case "confused":
      return "\u{1F615}";
    case "heart":
      return "\u{2764}\u{FE0F}";
    case "rocket":
      return "\u{1F680}";
    case "eyes":
      return "\u{1F440}";
    default:
      return name;
  }
}

export function renderReactions(comment, ctx) {
  if (!ctx?.canComment) return null;
  const allowed =
    Array.isArray(ctx.allowedReactions) && ctx.allowedReactions.length
      ? ctx.allowedReactions
      : DEFAULT_REACTIONS;
  const counts = new Map();
  if (Array.isArray(comment.reactions)) {
    for (const r of comment.reactions) {
      if (!r || !r.content) continue;
      const entry = counts.get(r.content) || { count: 0, mine: false };
      entry.count += 1;
      if (r.user?.id === ctx.signedUserID) entry.mine = true;
      counts.set(r.content, entry);
    }
  }

  const bar = document.createElement("div");
  bar.className = "harivan-pierre-reactions";
  for (const [content, entry] of counts.entries()) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "harivan-pierre-reaction";
    if (entry.mine) btn.classList.add("is-mine");
    btn.title = content;
    btn.dataset.content = content;
    const emoji = document.createElement("span");
    emoji.className = "harivan-pierre-reaction-emoji";
    emoji.textContent = reactionEmoji(content);
    const count = document.createElement("span");
    count.className = "harivan-pierre-reaction-count";
    count.textContent = String(entry.count);
    btn.append(emoji, count);
    btn.addEventListener("click", async () => {
      btn.disabled = true;
      try {
        await toggleReaction({
          commentId: comment.id,
          content,
          mode: entry.mine ? "unreact" : "react",
        });
      } catch (error) {
        console.warn("Pierre PR bridge: reaction failed", error);
        btn.disabled = false;
      }
    });
    bar.append(btn);
  }

  const picker = document.createElement("details");
  picker.className = "harivan-pierre-reaction-picker";
  const summary = document.createElement("summary");
  summary.className = "harivan-pierre-reaction-add";
  summary.textContent = "+";
  summary.title = "Add reaction";
  picker.append(summary);

  const palette = document.createElement("div");
  palette.className = "harivan-pierre-reaction-palette";
  for (const name of allowed) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "harivan-pierre-reaction-palette-btn";
    btn.title = name;
    btn.textContent = reactionEmoji(name);
    btn.addEventListener("click", async () => {
      picker.open = false;
      try {
        const mine = counts.get(name)?.mine;
        await toggleReaction({
          commentId: comment.id,
          content: name,
          mode: mine ? "unreact" : "react",
        });
      } catch (error) {
        console.warn("Pierre PR bridge: reaction failed", error);
      }
    });
    palette.append(btn);
  }
  picker.append(palette);
  bar.append(picker);
  return bar;
}
