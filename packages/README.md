# packages/

Centralized home for this repo's own buildable artifacts: CLIs, services, and
(over time) the agent factory. Inspired by `indexable-inc/index`: one directory
per package, auto-discovered by a registry, so adding a package is dropping a
directory and nothing else.

## Layout

```
packages/
  registry.nix         auto-discovery: every <name>/ with a package.nix is a package
  default.nix          the "packageSet" view, for NixOS / nix-darwin modules to import
  lib.nix              shared helpers (mkScript)
  <name>/package.nix   one package
```

## The package contract

`<name>/package.nix` is a function:

```nix
{ pkgs, lib, inputs, system, ... }:
{
  id        = "kb-search";              # flake output / attrset key (required)
  platforms = [ "aarch64-linux" ];      # optional; omitted = all systems
  package   = <derivation>;             # the build (required)
  tests     = { smoke = <derivation>; };# optional; each becomes a flake check
}
```

Reading `.id` must not force `.package` (keep build inputs inside a `let`), so a
package can be discovered without its inputs being present.

## What you get (the niceties)

- `nix run .#<id>` / `nix build .#<id>` for every package, host-scoped by `platforms`.
- `nix flake check` runs every package's `tests` as `<id>-<test>`.
- Modules consume the same registry via `import ../../packages { inherit pkgs lib; }`,
  so flake outputs and module package sets can never drift.

## Not here on purpose

- **Dotfiles** stay live-edited under `dots/` and are symlinked into `$HOME`; they
  are never store-baked here.
- **Deployment glue** (systemd units, activation scripts, venv bootstraps, sops
  wiring) stays in `modules/`. A package is the portable artifact; the module is
  how a host runs it.
```
