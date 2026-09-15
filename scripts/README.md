# scripts

Repo tooling, nothing here lands in a user environment (packaged scripts are
`pkgs/scripts/`). Forgejo's run-by-hand mirror scripts live with the service
in `hosts/spark/services/forgejo/scripts/`.

- `nvim-smoke.sh`: startup and integration tests for the packaged editor. The `pr` flake check runs the tests from the pinned `pr.nvim` repository.
- `nvim-update.sh`: update one pinned Neovim plugin; `just nvim-update <plugin> [revision]`.
