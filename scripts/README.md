# scripts

Repo tooling, nothing here lands in a user environment (packaged scripts are
`pkgs/scripts/`). Forgejo's run-by-hand mirror scripts live with the service
in `hosts/spark/services/forgejo/scripts/`.

- `pr-smoke.sh`: smoke test for the nvim `pr` tooling; the `pr` flake check.
- `nvim-update.sh`: update one pinned Neovim plugin; `just nvim-update <plugin> [revision]`.
