# Forgejo Custom Layer

This directory holds the small custom layer that is mounted into Forgejo's normal
`custom/` directory by `modules/services/forgejo.nix`.

The important boundary is:

- Cozybox remains the real Forgejo theme.
- This directory does not define or register a Forgejo color theme.
- This directory injects Berkeley Mono and the Pierre file/diff renderer.

## Shape

```
forgejo-custom/
  default.nix
  assets/
    css/
      harivan-forgejo.css
  frontend/
    package.json
    package-lock.json
    src/
      pierre-renderer.js
  patches/
    0001-client-side-file-rendering.patch
  templates/
    custom/
      header.tmpl
      footer.tmpl
    repo/
      view_file.tmpl
```

## Nix Wiring

`default.nix` builds the frontend bundle with `pkgs.buildNpmPackage` and returns
three outputs to the service module:

- `frontend`: the bundled JavaScript at `$out/js/harivan-forgejo.js`.
- `assets`: static files under `assets/`.
- `templates`: Forgejo custom templates under `templates/`.

`modules/services/forgejo.nix` imports this directory and links the outputs into
`/var/lib/forgejo/custom` using `systemd.tmpfiles.rules`.

The current intended live paths are:

- `/var/lib/forgejo/custom/public/assets/css/harivan-forgejo.css`
- `/var/lib/forgejo/custom/public/assets/fonts/BerkeleyMono-Regular.otf`
- `/var/lib/forgejo/custom/public/assets/js/harivan-forgejo.js`
- `/var/lib/forgejo/custom/templates/custom/header.tmpl`
- `/var/lib/forgejo/custom/templates/custom/footer.tmpl`

## Templates

`header.tmpl` loads `harivan-forgejo.css`.

`footer.tmpl` is intentionally empty.

These templates are the only hook into Forgejo's rendered pages. The header
loads the Pierre renderer. If the templates are removed, the custom font and
Pierre renderer stop loading, but Forgejo itself continues to use its normal
templates and Cozybox theme.

## CSS

`assets/css/harivan-forgejo.css` is intentionally narrow. It should only contain:

- Berkeley Mono `@font-face`.
- Font-family rules that make Forgejo use Berkeley Mono.
- Pierre container/layout rules.
- Pierre CSS variable mappings to the active Forgejo theme.

Do not put color palette variables or `data-theme` selectors here. Color work
belongs in the existing Cozybox theme CSS in `modules/services/forgejo.nix`, so
Forgejo keeps one theme source of truth. Pierre should consume those variables
instead of defining a competing Forgejo theme.

## Frontend

`patches/0001-client-side-file-rendering.patch` changes Forgejo's source-file
backend path so normal code files skip server-side Chroma highlighting. Forgejo
still computes file metadata and line counts, but it sends an empty
`FileContent` list and marks the page for client-side rendering.

`templates/repo/view_file.tmpl` mirrors Forgejo's upstream file-view template,
except the normal source-file branch emits a `.harivan-file-render-target`
instead of the native line table when the Go patch marks the page for
client-side rendering.

`frontend/src/pierre-renderer.js` imports `@pierre/diffs` and renders the file
or diff surface.

It currently handles:

- Normal file views under `/owner/repo/src/<kind>/<ref>/<path>`.
- Commit diffs under `/owner/repo/commit/<sha>`.
- Pull request diffs under `/owner/repo/pulls/<number>`.

For normal file views, the renderer reads metadata from
`.harivan-file-render-target`, fetches Forgejo's raw endpoint, and renders
Pierre as the first visible code view. Diff views still fetch the `.diff`
endpoint and hide the native diff table after Pierre has a mount point. If file
rendering fails, the file view falls back to a raw-file link.

The bundle registers `cozybox-dark` and `cozybox-light` Shiki themes and passes
them to Pierre as `{ dark: "cozybox-dark", light: "cozybox-light" }`. This is
what controls syntax highlighting inside Pierre's shadow DOM. The surrounding
diff row colors come from the CSS variable bridge above.

## Changing It

For Pierre behavior, edit `frontend/src/pierre-renderer.js`, then update the npm
hash if dependencies changed.

For font/layout behavior, edit `assets/css/harivan-forgejo.css`.

For color theme changes, edit the Cozybox theme definitions in
`modules/services/forgejo.nix`, not this directory.

After edits, validate with:

```sh
nix build --no-link .#nixosConfigurations.spark.config.system.build.toplevel
```

Then deploy on Spark with:

```sh
just switch-spark
```
