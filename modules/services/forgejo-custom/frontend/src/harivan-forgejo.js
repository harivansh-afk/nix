import {File, FileDiff, parsePatchFiles} from '@pierre/diffs';

function pathParts() {
  return window.location.pathname.split('/').filter(Boolean).map(decodeURIComponent);
}

function repoPrefix(parts = pathParts()) {
  if (parts.length < 2) return null;
  return `/${encodeURIComponent(parts[0])}/${encodeURIComponent(parts[1])}`;
}

function sourcePathFromLocation() {
  const parts = pathParts();
  const srcIndex = parts.indexOf('src');
  if (srcIndex < 0 || parts.length <= srcIndex + 2) return null;
  const refKind = parts[srcIndex + 1];
  const ref = parts[srcIndex + 2];
  const filePath = parts.slice(srcIndex + 3).join('/');
  const prefix = repoPrefix(parts);
  if (!prefix || !filePath) return null;
  return {
    rawUrl: `${prefix}/raw/${encodeURIComponent(refKind)}/${encodeURIComponent(ref)}/${filePath.split('/').map(encodeURIComponent).join('/')}`,
    cacheKey: `${refKind}:${ref}:${filePath}`,
    filePath,
  };
}

function setLineHash(range) {
  if (!range) return;
  const {start, end} = range;
  window.history.replaceState(null, '', start === end ? `#L${start}` : `#L${start}-L${end}`);
}

function renderFileView() {
  const target = document.querySelector('.repository.file .file-view.code-view');
  if (!target || target.dataset.harivanPierre === '1') return;
  const source = sourcePathFromLocation();
  if (!source) return;

  target.dataset.harivanPierre = '1';
  const fallback = target.cloneNode(true);
  fallback.classList.add('harivan-pierre-fallback');
  fallback.hidden = true;

  const mount = document.createElement('div');
  mount.className = 'harivan-pierre-file';
  target.replaceChildren(mount, fallback);

  fetch(source.rawUrl, {credentials: 'same-origin'})
    .then((response) => {
      if (!response.ok) throw new Error(response.statusText);
      return response.text();
    })
    .then((contents) => {
      const file = new File({
        disableFileHeader: true,
        enableLineSelection: true,
        overflow: 'scroll',
        onLineSelectionEnd: setLineHash,
      });
      file.render({
        file: {
          name: source.filePath,
          contents,
          cacheKey: source.cacheKey,
        },
        containerWrapper: mount,
      });
    })
    .catch((error) => {
      console.warn('Pierre file rendering failed', error);
      mount.remove();
      fallback.hidden = false;
    });
}

function diffUrlFromLocation() {
  const parts = pathParts();
  const prefix = repoPrefix(parts);
  if (!prefix) return null;
  const commitIndex = parts.indexOf('commit');
  if (commitIndex >= 0 && parts[commitIndex + 1]) {
    return `${prefix}/commit/${encodeURIComponent(parts[commitIndex + 1])}.diff`;
  }
  const pullsIndex = parts.indexOf('pulls');
  if (pullsIndex >= 0 && parts[pullsIndex + 1]) {
    return `${prefix}/pulls/${encodeURIComponent(parts[pullsIndex + 1])}.diff`;
  }
  return null;
}

function fileNameForBox(box) {
  return box.dataset.newFilename || box.dataset.oldFilename || box.querySelector('.file')?.textContent?.trim() || '';
}

function indexPatchFiles(parsed) {
  const files = parsed.flatMap((patch) => patch.files || []);
  const byName = new Map();
  for (const file of files) {
    if (file.name) byName.set(file.name, file);
    if (file.prevName) byName.set(file.prevName, file);
  }
  return byName;
}

function renderDiffFile(box, fileDiff, cacheKey) {
  const body = box.querySelector('.diff-file-body');
  const source = box.querySelector('.code-diff');
  if (!body || !source || source.dataset.harivanPierre === '1') return;
  source.dataset.harivanPierre = '1';
  source.hidden = true;

  const mount = document.createElement('div');
  mount.className = 'harivan-pierre-diff';
  body.append(mount);

  const instance = new FileDiff({
    diffStyle: new URLSearchParams(window.location.search).get('style') === 'split' ? 'split' : 'unified',
    disableFileHeader: true,
    enableLineSelection: true,
    onLineSelectionEnd: (range) => {
      if (!range) return;
      const prefix = range.side === 'additions' ? 'R' : 'L';
      window.history.replaceState(null, '', `#${box.id || 'diff'}${prefix}${range.start}`);
    },
  });

  try {
    instance.render({
      fileDiff: {
        ...fileDiff,
        cacheKey: `${cacheKey}:${fileDiff.name || fileDiff.prevName || 'file'}`,
      },
      containerWrapper: mount,
    });
  } catch (error) {
    console.warn('Pierre diff rendering failed', error);
    mount.remove();
    source.hidden = false;
  }
}

function renderDiffView() {
  const boxes = Array.from(document.querySelectorAll('#diff-file-boxes .diff-file-box[id^="diff-"]'));
  if (boxes.length === 0) return;
  const url = diffUrlFromLocation();
  if (!url) return;

  fetch(url, {credentials: 'same-origin'})
    .then((response) => {
      if (!response.ok) throw new Error(response.statusText);
      return response.text();
    })
    .then((patch) => {
      const parsed = parsePatchFiles(patch, `harivan:${url}`);
      const byName = indexPatchFiles(parsed);
      for (const box of boxes) {
        const fileName = fileNameForBox(box);
        const fileDiff = byName.get(fileName);
        if (fileDiff) renderDiffFile(box, fileDiff, url);
      }
    })
    .catch((error) => {
      console.warn('Pierre diff rendering failed', error);
    });
}

function init() {
  renderFileView();
  renderDiffView();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init, {once: true});
} else {
  init();
}
