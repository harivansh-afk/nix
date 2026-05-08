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
      harivan-forgejo.js
  templates/
    custom/
      header.tmpl
      footer.tmpl
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

`footer.tmpl` loads `harivan-forgejo.js` as an ES module.

These templates are the only hook into Forgejo's rendered pages. If they are
removed, the custom font and Pierre renderer stop loading, but Forgejo itself
continues to use its normal templates and Cozybox theme.

## CSS

`assets/css/harivan-forgejo.css` is intentionally narrow. It should only contain:

- Berkeley Mono `@font-face`.
- Font-family rules that make Forgejo use Berkeley Mono.
- Pierre container/layout rules.

Do not put color palette variables or `data-theme` selectors here. Color work
belongs in the existing Cozybox theme CSS in `modules/services/forgejo.nix`, so
Forgejo keeps one theme source of truth.

## Frontend

`frontend/src/harivan-forgejo.js` bundles `@pierre/diffs` and progressively
replaces Forgejo's built-in code and diff surfaces.

It currently handles:

- Normal file views under `/owner/repo/src/<kind>/<ref>/<path>`.
- Commit diffs under `/owner/repo/commit/<sha>`.
- Pull request diffs under `/owner/repo/pulls/<number>`.

The script fetches Forgejo's raw file or `.diff` endpoint, renders Pierre into a
new mount element, and keeps Forgejo's original markup hidden as a fallback. If
Pierre throws or a fetch fails, the original Forgejo view is shown again.

## Changing It

For Pierre behavior, edit `frontend/src/harivan-forgejo.js`, then update the npm
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
