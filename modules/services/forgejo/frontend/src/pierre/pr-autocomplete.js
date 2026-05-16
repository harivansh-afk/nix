// Lightweight @-mention autocomplete for the comment composer.
//
// Hits Forgejo's /{owner}/{repo}/issues/posters?type=pulls&q= endpoint and
// surfaces a positioned dropdown anchored to the textarea caret. Replaces
// the in-progress @token with @login on selection.

let activePopup = null;
let debounceTimer;

function fetchPosters(url, query) {
  return fetch(`${url}&q=${encodeURIComponent(query)}`, {
    credentials: "same-origin",
    headers: { Accept: "application/json" },
  })
    .then((response) => (response.ok ? response.json() : []))
    .catch(() => []);
}

function caretAtToken(textarea) {
  const value = textarea.value;
  const pos = textarea.selectionStart;
  const upToCursor = value.slice(0, pos);
  const match = upToCursor.match(/(?:^|\s)@([A-Za-z0-9_-]{0,38})$/);
  if (!match) return null;
  return {
    query: match[1],
    start: pos - match[1].length - 1,
    end: pos,
  };
}

function removePopup() {
  if (!activePopup) return;
  activePopup.remove();
  activePopup = null;
}

function renderPopup(textarea, users, token) {
  removePopup();
  if (!users.length) return;

  const popup = document.createElement("div");
  popup.className = "harivan-pierre-autocomplete";
  let selected = 0;

  function applySelection(index) {
    const user = users[index];
    if (!user) return;
    const before = textarea.value.slice(0, token.start);
    const after = textarea.value.slice(token.end);
    const insertion = `@${user.login} `;
    textarea.value = `${before}${insertion}${after}`;
    const cursor = before.length + insertion.length;
    textarea.setSelectionRange(cursor, cursor);
    removePopup();
    textarea.dispatchEvent(new Event("input", { bubbles: true }));
  }

  function updateHighlight() {
    for (const [i, child] of [...popup.children].entries()) {
      child.classList.toggle("is-active", i === selected);
    }
  }

  for (const [index, user] of users.entries()) {
    const item = document.createElement("button");
    item.type = "button";
    item.className = "harivan-pierre-autocomplete-item";
    item.dataset.index = String(index);
    if (user.avatar_url) {
      const avatar = document.createElement("img");
      avatar.src = user.avatar_url;
      avatar.width = 16;
      avatar.height = 16;
      item.append(avatar);
    }
    const login = document.createElement("span");
    login.className = "harivan-pierre-autocomplete-login";
    login.textContent = user.login;
    item.append(login);
    if (user.full_name) {
      const full = document.createElement("span");
      full.className = "harivan-pierre-autocomplete-fullname";
      full.textContent = user.full_name;
      item.append(full);
    }
    item.addEventListener("mousedown", (event) => {
      event.preventDefault();
      applySelection(index);
    });
    popup.append(item);
  }

  const rect = textarea.getBoundingClientRect();
  popup.style.position = "fixed";
  popup.style.left = `${rect.left}px`;
  popup.style.top = `${rect.bottom + 4}px`;
  popup.style.minWidth = `${Math.min(rect.width, 280)}px`;
  document.body.append(popup);

  updateHighlight();

  function onKey(event) {
    if (!activePopup) return;
    if (event.key === "ArrowDown") {
      event.preventDefault();
      selected = (selected + 1) % users.length;
      updateHighlight();
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      selected = (selected - 1 + users.length) % users.length;
      updateHighlight();
    } else if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault();
      applySelection(selected);
    } else if (event.key === "Escape") {
      event.preventDefault();
      removePopup();
    }
  }

  textarea.addEventListener("keydown", onKey);
  popup.addEventListener("remove", () => textarea.removeEventListener("keydown", onKey));
  activePopup = popup;
}

export function attachAutocomplete(textarea, postersUrl) {
  if (!textarea || !postersUrl) return;
  const close = () => removePopup();
  textarea.addEventListener("blur", () => window.setTimeout(close, 100));
  textarea.addEventListener("input", () => {
    const token = caretAtToken(textarea);
    if (!token) {
      removePopup();
      return;
    }
    window.clearTimeout(debounceTimer);
    debounceTimer = window.setTimeout(async () => {
      const users = await fetchPosters(postersUrl, token.query);
      renderPopup(textarea, users.slice(0, 8), token);
    }, 150);
  });
}
