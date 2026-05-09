import { fetchText } from "../shared/fetch.js";
import { loadPierre } from "./client.js";
import { pierreFileRenderOptions } from "./options.js";

function setLineHash(range) {
  if (!range) return;
  const { start, end } = range;
  window.history.replaceState(
    null,
    "",
    start === end ? `#L${start}` : `#L${start}-L${end}`,
  );
}

export async function renderFileView() {
  const target = document.querySelector(".harivan-file-render-target");
  if (!target || target.dataset.harivanPierre === "1") return;
  target.dataset.harivanPierre = "1";

  const rawUrl = target.dataset.rawUrl;
  const filePath = target.dataset.filePath || target.dataset.filename || "file";
  const cacheKey = target.dataset.cacheKey || filePath;
  if (!rawUrl) return;

  const mount = document.createElement("div");
  mount.className = "harivan-pierre-file";
  target.replaceChildren(mount);

  try {
    const pierrePromise = loadPierre();
    const contentsPromise = fetchText(rawUrl);
    const [{ File }, contents] = await Promise.all([
      pierrePromise,
      contentsPromise,
    ]);
    const file = new File(pierreFileRenderOptions({
      onLineSelectionEnd: setLineHash,
    }));
    file.render({
      file: {
        name: filePath,
        contents,
        cacheKey,
      },
      containerWrapper: mount,
    });
  } catch (error) {
    console.warn("Pierre file rendering failed", error);
    mount.remove();
    const link = document.createElement("a");
    link.href = rawUrl;
    link.rel = "nofollow";
    link.textContent = "View raw file";
    target.append(link);
  }
}
