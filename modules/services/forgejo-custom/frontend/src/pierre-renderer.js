import {File, FileDiff, parsePatchFiles, registerCustomTheme} from '@pierre/diffs';

const cozyboxDark = {
  name: 'cozybox-dark',
  type: 'dark',
  colors: {
    'editor.background': '#141414',
    'editor.foreground': '#ebdbb2',
    foreground: '#ebdbb2',
    focusBorder: '#5b84de',
    'selection.background': '#504945',
    'editor.selectionBackground': '#504945',
    'editor.lineHighlightBackground': '#1e1e1e',
    'editorCursor.foreground': '#ebdbb2',
    'editorLineNumber.foreground': '#928374',
    'editorLineNumber.activeForeground': '#d5c4a1',
    'gitDecoration.addedResourceForeground': '#8ec97c',
    'gitDecoration.modifiedResourceForeground': '#5b84de',
    'gitDecoration.deletedResourceForeground': '#ea6962',
    'terminal.ansiRed': '#ea6962',
    'terminal.ansiGreen': '#8ec97c',
    'terminal.ansiYellow': '#d79921',
    'terminal.ansiBlue': '#5b84de',
    'terminal.ansiMagenta': '#d3869b',
    'terminal.ansiCyan': '#8ec07c',
  },
  tokenColors: [
    {scope: ['comment', 'punctuation.definition.comment'], settings: {foreground: '#928374', fontStyle: 'italic'}},
    {scope: ['string', 'constant.other.symbol'], settings: {foreground: '#8ec97c'}},
    {scope: ['constant.numeric', 'constant.language.boolean'], settings: {foreground: '#d3869b'}},
    {scope: ['constant', 'variable.language'], settings: {foreground: '#d79921'}},
    {scope: ['keyword', 'storage', 'storage.type', 'storage.modifier'], settings: {foreground: '#ea6962'}},
    {scope: ['variable', 'identifier', 'meta.definition.variable'], settings: {foreground: '#ebdbb2'}},
    {scope: ['variable.parameter', 'variable.parameter.function'], settings: {foreground: '#d5c4a1'}},
    {scope: ['support.function', 'entity.name.function', 'meta.function-call', 'variable.function'], settings: {foreground: '#5b84de'}},
    {scope: ['support.type', 'entity.name.type', 'entity.name.class', 'support.class'], settings: {foreground: '#d3869b'}},
    {scope: ['keyword.operator', 'punctuation', 'meta.brace'], settings: {foreground: '#a89984'}},
    {scope: ['keyword.operator.logical', 'keyword.operator.arithmetic', 'keyword.operator.comparison'], settings: {foreground: '#8ec07c'}},
    {scope: ['entity.name.tag', 'support.type.property-name', 'meta.object-literal.key'], settings: {foreground: '#fabd2f'}},
    {scope: ['invalid', 'invalid.illegal'], settings: {foreground: '#ea6962', fontStyle: 'bold'}},
  ],
};

const cozyboxLight = {
  name: 'cozybox-light',
  type: 'light',
  colors: {
    'editor.background': '#dcdcdc',
    'editor.foreground': '#282828',
    foreground: '#282828',
    focusBorder: '#4261a5',
    'selection.background': '#c3c7c9',
    'editor.selectionBackground': '#c3c7c9',
    'editor.lineHighlightBackground': '#d3d3d3',
    'editorCursor.foreground': '#282828',
    'editorLineNumber.foreground': '#7c7c7c',
    'editorLineNumber.activeForeground': '#504945',
    'gitDecoration.addedResourceForeground': '#427b58',
    'gitDecoration.modifiedResourceForeground': '#4261a5',
    'gitDecoration.deletedResourceForeground': '#c5524a',
    'terminal.ansiRed': '#c5524a',
    'terminal.ansiGreen': '#427b58',
    'terminal.ansiYellow': '#b57614',
    'terminal.ansiBlue': '#4261a5',
    'terminal.ansiMagenta': '#8f3f71',
    'terminal.ansiCyan': '#3c7678',
  },
  tokenColors: [
    {scope: ['comment', 'punctuation.definition.comment'], settings: {foreground: '#7c7c7c', fontStyle: 'italic'}},
    {scope: ['string', 'constant.other.symbol'], settings: {foreground: '#427b58'}},
    {scope: ['constant.numeric', 'constant.language.boolean'], settings: {foreground: '#8f3f71'}},
    {scope: ['constant', 'variable.language'], settings: {foreground: '#b57614'}},
    {scope: ['keyword', 'storage', 'storage.type', 'storage.modifier'], settings: {foreground: '#c5524a'}},
    {scope: ['variable', 'identifier', 'meta.definition.variable'], settings: {foreground: '#282828'}},
    {scope: ['variable.parameter', 'variable.parameter.function'], settings: {foreground: '#504945'}},
    {scope: ['support.function', 'entity.name.function', 'meta.function-call', 'variable.function'], settings: {foreground: '#4261a5'}},
    {scope: ['support.type', 'entity.name.type', 'entity.name.class', 'support.class'], settings: {foreground: '#8f3f71'}},
    {scope: ['keyword.operator', 'punctuation', 'meta.brace'], settings: {foreground: '#665c54'}},
    {scope: ['keyword.operator.logical', 'keyword.operator.arithmetic', 'keyword.operator.comparison'], settings: {foreground: '#3c7678'}},
    {scope: ['entity.name.tag', 'support.type.property-name', 'meta.object-literal.key'], settings: {foreground: '#b57614'}},
    {scope: ['invalid', 'invalid.illegal'], settings: {foreground: '#c5524a', fontStyle: 'bold'}},
  ],
};

registerCustomTheme('cozybox-dark', () => Promise.resolve(cozyboxDark));
registerCustomTheme('cozybox-light', () => Promise.resolve(cozyboxLight));

const pierreTheme = {dark: 'cozybox-dark', light: 'cozybox-light'};

function pathParts() {
  return window.location.pathname.split('/').filter(Boolean).map(decodeURIComponent);
}

function repoPrefix(parts = pathParts()) {
  if (parts.length < 2) return null;
  return `/${encodeURIComponent(parts[0])}/${encodeURIComponent(parts[1])}`;
}

function setLineHash(range) {
  if (!range) return;
  const {start, end} = range;
  window.history.replaceState(null, '', start === end ? `#L${start}` : `#L${start}-L${end}`);
}

async function renderFileView() {
  const target = document.querySelector('.harivan-file-render-target');
  if (!target || target.dataset.harivanPierre === '1') return;
  target.dataset.harivanPierre = '1';

  const rawUrl = target.dataset.rawUrl;
  const filePath = target.dataset.filePath || target.dataset.filename || 'file';
  const cacheKey = target.dataset.cacheKey || filePath;
  if (!rawUrl) return;

  const mount = document.createElement('div');
  mount.className = 'harivan-pierre-file';
  target.replaceChildren(mount);

  try {
    const response = await fetch(rawUrl, {credentials: 'same-origin'});
    if (!response.ok) throw new Error(response.statusText);
    const contents = await response.text();
    const file = new File({
      disableFileHeader: true,
      enableLineSelection: true,
      overflow: 'scroll',
      theme: pierreTheme,
      onLineSelectionEnd: setLineHash,
    });
    file.render({
      file: {
        name: filePath,
        contents,
        cacheKey,
      },
      containerWrapper: mount,
    });
  } catch (error) {
    console.warn('Pierre file rendering failed', error);
    mount.remove();
    const link = document.createElement('a');
    link.href = rawUrl;
    link.rel = 'nofollow';
    link.textContent = 'View raw file';
    target.append(link);
  }
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
    theme: pierreTheme,
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

async function renderDiffView() {
  const boxes = Array.from(document.querySelectorAll('#diff-file-boxes .diff-file-box[id^="diff-"]'));
  if (boxes.length === 0) return;
  const url = diffUrlFromLocation();
  if (!url) return;

  try {
    const response = await fetch(url, {credentials: 'same-origin'});
    if (!response.ok) throw new Error(response.statusText);
    const patch = await response.text();
    const parsed = parsePatchFiles(patch, `harivan:${url}`);
    const byName = indexPatchFiles(parsed);
    for (const box of boxes) {
      const fileName = fileNameForBox(box);
      const fileDiff = byName.get(fileName);
      if (fileDiff) renderDiffFile(box, fileDiff, url);
    }
  } catch (error) {
    console.warn('Pierre diff rendering failed', error);
  }
}

async function init() {
  await Promise.allSettled([
    renderFileView(),
    renderDiffView(),
  ]);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init, {once: true});
} else {
  init();
}
