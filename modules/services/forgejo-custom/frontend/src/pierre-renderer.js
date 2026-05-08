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

const noniconGlyphs = {
  biome: 62078,
  book: 61711,
  c: 61718,
  'c-plusplus': 61719,
  'c-sharp': 61720,
  code: 61734,
  css: 61743,
  dart: 61744,
  database: 61746,
  diff: 61752,
  docker: 61758,
  elixir: 61971,
  elm: 61763,
  eslint: 61981,
  file: 61766,
  'file-binary': 61768,
  'file-directory-fill': 62011,
  'file-zip': 61775,
  gear: 61781,
  'git-branch': 61783,
  'git-commit': 61784,
  globe: 61788,
  go: 61789,
  graphql: 61994,
  html: 61799,
  image: 61801,
  java: 61809,
  javascript: 61810,
  json: 61811,
  key: 61813,
  kotlin: 61814,
  law: 61816,
  lock: 61823,
  log: 62015,
  lua: 61826,
  markdown: 61829,
  next: 61991,
  nginx: 61838,
  npm: 61843,
  package: 61846,
  perl: 61853,
  php: 61855,
  play: 61857,
  prettier: 61982,
  python: 61863,
  r: 61866,
  react: 61867,
  rss: 61879,
  ruby: 61880,
  rust: 61881,
  scala: 61882,
  shield: 61889,
  svelte: 61992,
  swift: 61906,
  terminal: 61911,
  terraform: 61972,
  tmux: 61915,
  toml: 61916,
  typescript: 61923,
  typography: 61924,
  vim: 61932,
  vue: 61940,
  yaml: 61945,
  yarn: 61946,
};

const noniconExtMap = {
  lua: 'lua',
  luac: 'lua',
  luau: 'lua',
  js: 'javascript',
  cjs: 'javascript',
  mjs: 'javascript',
  jsx: 'react',
  tsx: 'react',
  ts: 'typescript',
  cts: 'typescript',
  mts: 'typescript',
  'd.ts': 'typescript',
  py: 'python',
  pyc: 'python',
  pyd: 'python',
  pyi: 'python',
  pyo: 'python',
  pyw: 'python',
  pyx: 'python',
  rb: 'ruby',
  rake: 'ruby',
  gemspec: 'ruby',
  rs: 'rust',
  rlib: 'rust',
  go: 'go',
  c: 'c',
  h: 'c',
  cpp: 'c-plusplus',
  cc: 'c-plusplus',
  cxx: 'c-plusplus',
  'c++': 'c-plusplus',
  cp: 'c-plusplus',
  hh: 'c-plusplus',
  hpp: 'c-plusplus',
  hxx: 'c-plusplus',
  cs: 'c-sharp',
  java: 'java',
  jar: 'java',
  kt: 'kotlin',
  kts: 'kotlin',
  swift: 'swift',
  dart: 'dart',
  elm: 'elm',
  ex: 'elixir',
  exs: 'elixir',
  eex: 'elixir',
  heex: 'elixir',
  vue: 'vue',
  svelte: 'svelte',
  html: 'html',
  htm: 'html',
  css: 'css',
  scss: 'css',
  sass: 'css',
  less: 'css',
  json: 'json',
  json5: 'json',
  jsonc: 'json',
  yaml: 'yaml',
  yml: 'yaml',
  toml: 'toml',
  md: 'markdown',
  markdown: 'markdown',
  mdx: 'markdown',
  php: 'php',
  pl: 'perl',
  pm: 'perl',
  r: 'r',
  rmd: 'r',
  scala: 'scala',
  sc: 'scala',
  sbt: 'scala',
  vim: 'vim',
  graphql: 'graphql',
  gql: 'graphql',
  tf: 'terraform',
  tfvars: 'terraform',
  dockerfile: 'docker',
  dockerignore: 'docker',
  sh: 'terminal',
  bash: 'terminal',
  zsh: 'terminal',
  fish: 'terminal',
  nix: 'code',
  sql: 'database',
  sqlite: 'database',
  db: 'database',
  rss: 'rss',
  tmux: 'tmux',
  nginx: 'nginx',
  diff: 'diff',
  patch: 'diff',
  lock: 'lock',
  conf: 'gear',
  cfg: 'gear',
  ini: 'gear',
  env: 'key',
  git: 'git-branch',
  license: 'law',
  log: 'log',
  xml: 'code',
  png: 'image',
  jpg: 'image',
  jpeg: 'image',
  gif: 'image',
  bmp: 'image',
  ico: 'image',
  webp: 'image',
  avif: 'image',
  svg: 'image',
  zip: 'file-zip',
  gz: 'file-zip',
  tgz: 'file-zip',
  '7z': 'file-zip',
  rar: 'file-zip',
  bz2: 'file-zip',
  xz: 'file-zip',
  zst: 'file-zip',
  tar: 'file-zip',
  bin: 'file-binary',
  exe: 'file-binary',
  dll: 'file-binary',
  so: 'file-binary',
  o: 'file-binary',
  mp3: 'play',
  mp4: 'play',
  mkv: 'play',
  mov: 'play',
  flac: 'play',
  wav: 'play',
  ttf: 'typography',
  otf: 'typography',
  woff: 'typography',
  woff2: 'typography',
};

const noniconFilenameMap = {
  dockerfile: 'docker',
  containerfile: 'docker',
  'docker-compose.yml': 'docker',
  'docker-compose.yaml': 'docker',
  'compose.yml': 'docker',
  'compose.yaml': 'docker',
  '.dockerignore': 'docker',
  '.gitignore': 'git-branch',
  '.gitconfig': 'git-branch',
  '.gitattributes': 'git-branch',
  '.gitmodules': 'git-branch',
  '.git-blame-ignore-revs': 'git-branch',
  commit_editmsg: 'git-commit',
  '.bashrc': 'terminal',
  '.bash_profile': 'terminal',
  '.zshrc': 'terminal',
  '.zshenv': 'terminal',
  '.zprofile': 'terminal',
  makefile: 'terminal',
  gnumakefile: 'terminal',
  justfile: 'terminal',
  '.justfile': 'terminal',
  '.eslintrc': 'eslint',
  '.eslintignore': 'eslint',
  'eslint.config.js': 'eslint',
  'eslint.config.cjs': 'eslint',
  'eslint.config.mjs': 'eslint',
  'eslint.config.ts': 'eslint',
  'biome.json': 'biome',
  'biome.jsonc': 'biome',
  '.prettierrc': 'prettier',
  '.prettierignore': 'prettier',
  'prettier.config.js': 'prettier',
  'prettier.config.cjs': 'prettier',
  'prettier.config.mjs': 'prettier',
  'prettier.config.ts': 'prettier',
  package: 'package',
  'package.json': 'npm',
  'package-lock.json': 'npm',
  '.npmrc': 'npm',
  'pnpm-lock.yaml': 'yarn',
  'pnpm-workspace.yaml': 'package',
  'bun.lock': 'package',
  'bun.lockb': 'package',
  'tsconfig.json': 'typescript',
  license: 'law',
  'license.md': 'law',
  copying: 'law',
  unlicense: 'law',
  'tmux.conf': 'tmux',
  'tmux.conf.local': 'tmux',
  readme: 'book',
  'readme.md': 'book',
  'go.mod': 'go',
  'go.sum': 'go',
  'go.work': 'go',
  '.vimrc': 'vim',
  '.gvimrc': 'vim',
  'next.config.js': 'next',
  'next.config.cjs': 'next',
  'next.config.ts': 'next',
  'svelte.config.js': 'svelte',
  'mix.lock': 'elixir',
  '.env': 'key',
  config: 'gear',
  '.editorconfig': 'gear',
  gemfile: 'ruby',
  rakefile: 'ruby',
  security: 'shield',
  'security.md': 'shield',
  'robots.txt': 'globe',
  'vite.config.js': 'code',
  'vite.config.ts': 'code',
  'vite.config.cjs': 'code',
  'vite.config.mjs': 'code',
  'cmakelists.txt': 'code',
};

function noniconChar(name) {
  return String.fromCodePoint(noniconGlyphs[name] || noniconGlyphs.file);
}

function resolveNoniconName(filename, isDirectory = false) {
  if (isDirectory) return 'file-directory-fill';
  const lower = (filename || '').toLowerCase();
  if (noniconFilenameMap[lower]) return noniconFilenameMap[lower];
  const parts = lower.split('.');
  while (parts.length > 1) {
    parts.shift();
    const ext = parts.join('.');
    if (noniconExtMap[ext]) return noniconExtMap[ext];
  }
  return 'file';
}

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

function fileNameFromLink(link) {
  const title = link?.getAttribute('title')?.trim();
  if (title) return title.split('/').pop();
  return link?.textContent?.trim()?.split('/').pop() || '';
}

function replaceFileIcon(icon, filename, isDirectory) {
  if (!icon || icon.dataset.harivanNonicon === '1') return;
  const name = resolveNoniconName(filename, isDirectory);
  const span = document.createElement('span');
  span.className = `harivan-nonicon${isDirectory ? ' harivan-nonicon-folder' : ''}`;
  span.dataset.harivanNonicon = '1';
  span.setAttribute('aria-hidden', 'true');
  span.textContent = noniconChar(name);
  icon.replaceWith(span);
}

function replaceRepositoryFileIcons() {
  const rows = document.querySelectorAll('tr, .repo-file-item, .repository.file.list .item');
  for (const row of rows) {
    if (row.dataset.harivanNonicons === '1') continue;
    const icon = row.querySelector('svg.octicon-file, svg.octicon-file-code, svg.octicon-file-directory, svg.octicon-file-directory-fill, svg.octicon-file-submodule, svg.octicon-file-symlink-file');
    if (!icon) continue;
    const link = row.querySelector('a[title], a[href*="/src/"], a[href*="/tree/"]');
    const filename = fileNameFromLink(link);
    if (!filename) continue;
    const isDirectory = icon.classList.contains('octicon-file-directory') || icon.classList.contains('octicon-file-directory-fill');
    replaceFileIcon(icon, filename, isDirectory);
    row.dataset.harivanNonicons = '1';
  }
}

async function init() {
  await Promise.allSettled([
    renderFileView(),
    renderDiffView(),
  ]);
  replaceRepositoryFileIcons();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init, {once: true});
} else {
  init();
}

document.addEventListener('turbo:load', init);
