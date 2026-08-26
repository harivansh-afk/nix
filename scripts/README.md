# scripts

Run-by-hand and CI helper scripts. Nothing here is packaged into a user
environment; the packaged script builders live in `pkgs/scripts/`.

## Run-by-hand scripts (`forgejo-mirror/`)

Not wired into any package or unit. Run manually as documented in `AGENTS.md`:

- `reconcile.sh` - reconcile forgejo push-mirrors against
  `/etc/forgejo-mirror/manifest.json`. Run as root.
- `github-ux.sh` - apply GitHub-side metadata/banners to push-mirrors. Run on demand.
- `avatar-backfill.sh` - backfill Forgejo mirror-owner org avatars from GitHub. Dry-run by default; use `--apply` to write through the Forgejo API.

## Repo tooling

- `pr-smoke.sh` - smoke test for the nvim `pr` review tooling; runs as the
  `pr` flake check.
- `nvim-pack-sources.sh` - regenerate `dots/nvim/pack-sources.json` from the
  local nvim-pack lock; run via `just nvim-pack-sources`.
- `omp/claude-hooks-smoke.sh` - catch omp extension-API drift in the Claude
  bridges after an omp version bump.
