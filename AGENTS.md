# AGENTS.md

## Hosts

| Host | System | Role |
|------|--------|------|
| `macbook` | nix-darwin, aarch64-darwin | Workstation: Homebrew casks, Determinate Nix |
| `spark` | NixOS, aarch64-linux | DGX Spark server: disko, sops-nix, Caddy, cloudflared, Tailscale |

Host records live in `flake/args.nix`; `flake/hosts.nix` builds darwin and `flake/nixos.nix` builds NixOS.

Spark web traffic: Cloudflare edge → cloudflared → Caddy on `127.0.0.1:80` → services on loopback ports. No public web ports.

Forgejo (`git.harivan.sh`) is tailnet-only: an unproxied A record points at spark's Tailscale IP, Caddy serves it on `:443` with a Let's Encrypt cert issued by DNS-01 through Cloudflare (`security.acme`, reusing `cloudflare-api-token`), and the firewall opens 443 only on `tailscale0`. Off the tailnet, use the GitHub mirrors.

## Secrets

sops-nix with age keys derived from each host's ed25519 SSH key (`admin_macbook` edits everything, `host_spark` decrypts at activation). Secrets live in `secrets/hosts/<host>/` and `secrets/user/`, and every one is declared in `secrets/registry.nix`. Edit with `just sops-edit <file>`. `secrets/user/*.env` files are sourced into interactive zsh; raw tokens set `exposeToShell = false`.

## Conventions

- No comments in `.nix` files.
- `just switch` rebuilds the macbook, `just switch-spark` rebuilds spark, `just fmt` formats.
- PRs go to Forgejo (`origin`, git.harivan.sh), never GitHub; `github` is a push mirror. Create them with `tea pr create --login harivan --repo harivansh-afk/nix --base main --head <branch>`, passing multiline bodies as real text, and check the rendered body afterwards.
- Share package definitions across hosts; only macOS GUI integrations are Darwin-only.
- Bugfix PRs stay minimal.
- No home-manager. `modules/users/user-config.nix` builds an activation script that symlinks `dots/` into the home directory. The owner's links point at the live checkout, so dotfile edits apply without a rebuild; other users get store copies.
- Berkeley Mono and Ghostty (Homebrew cask) are installed out of band. Ghostty's terminfo is declared in `modules/common.nix`; never `tic` into `~/.terminfo`.
- Neovim: one package in `lib/neovim.nix`. Plugin pins live in `dots/nvim/pack-sources.json`; bump one with `just nvim-update <plugin> [rev]`. No runtime plugin installs.
- Claude and Codex are curl-installed and need nix-ld on NixOS. Devin's config is a mutable copy because Devin rewrites it.

## Worktrees

Create task worktrees with `git worktree add .worktrees/<topic> -b <branch> main` from the main checkout, which stays on `main`.

## Agent instructions

`dots/agents/core.md` (every agent) and `claude.md` (Claude Code only) are rendered by `lib/agent-instructions.nix` into `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. Repo facts belong in the repo's `AGENTS.md`; the tracked `CLAUDE.md` only imports it.

Skills come from the `mattpocock-skills` input and are linked into `~/.agents/skills` and `~/.claude/skills`. No harness has hooks, and none should be added. Claude Code's denied tools are `permissions.deny` in `modules/users/user-config/agents.nix`.

On spark, Claude Code also gets the `codex` MCP server (`pkgs/codex-mcp`): `codex` and `codex_reply` run `codex exec --json` in the session directory, with Codex fan-out and multi-agent turned off, and come back as task notifications. Codex keeps MCP OAuth tokens in files because the headless keyring hangs `codex exec`. Reauthorize Beeper with `codex mcp login beeper --oauth-client-registration dcr`.

## Layout

```
flake/        host records, builders, packages, checks
lib/          palette.json, theme.nix (renderers), neovim.nix, remotes.nix, agent-instructions.nix
modules/      common.nix, nix-settings.nix, users/ (user-config, accounts), security/sops.nix
hosts/macbook defaults, homebrew, launchd services, startup guard, voiceink, logitech
hosts/spark   hardware, networking, users, kernel hardening, services/ (one file per service)
pkgs/         sets.nix, scripts/, codex-mcp/, other derivations
dots/         live dotfiles
terraform/    Cloudflare DNS via terranix
scripts/      nvim-smoke.sh, nvim-update.sh
```

## Theme

The cozybox palette is `lib/palette.json`; `lib/theme.nix` renders it for ghostty, fzf, pure, rex, sketchybar and zsh highlights. `~/.local/state/theme/current` holds `dark` or `light`. The `theme` script switches the symlinks and pokes live nvim servers; zsh re-syncs on `precmd`. Neovim's colours come from `cozybox.nvim`.

## Remote sessions and Rex

- `spark` / `macbook` connectors (`lib/remotes.nix`, `pkgs/scripts/bin/remote.sh`) open `mosh <host>`; `--ssh` forces ssh. Host settings live in `dots/ssh/config`. Portable scripts are flake packages for hosts outside this flake.
- Rex (`/Applications/Rex Beta.app`) is installed by hand. `dots/rex/init.lua` holds the keymap (`rex config reload` applies it). Activation rewrites `com.superlogical.rex` defaults from `rexDefaults` and `theme.renderRex`, so settings changed in Rex's UI last until the next switch.
- Activation builds `Berkeley Mono Nonicons` (`pkgs/scripts/lib/rex-font.py`) because Rex has a single font. Never use nerd-font-patcher; its glyph names collide with Berkeley Mono's.
- Spark runs the Rex login server (`hosts/spark/services/rex.nix`), published by Tailscale Serve at `https://spark.<tailnet>.ts.net:7297` and mapping the owner's Tailscale login to `rathi`. The Mac app adds it under Remote Hosts. A session lives on one server, and its tabs and splits open on that server. `init.lua` is linked on both hosts because each server loads its own keymap.

## Key dependencies

- `dgx-spark`: never set `inputs.nixpkgs.follows`; it pins nixpkgs for the NVIDIA kernel. Podman is the only container runtime (Docker API at `/run/podman/podman.sock`); never enable `virtualisation.docker`.
- `determinate`: owns Nix and `nix.conf`; on darwin use `determinateNix.customSettings`.
- `neovim-nightly`: use its package, never its overlay (the overlay rebuilds every plugin and grammar).

## Adding a service on spark

1. Add `hosts/spark/services/<name>.nix` and import it in `hosts/spark/default.nix`.
2. Add any secret under `secrets/hosts/spark/` and register it in `secrets/registry.nix`.
3. Route it with `services.caddy.virtualHosts."http://<domain>" = loopbackVhost <port>;`.
4. Add the DNS record in `terraform/cloudflare`.

## Adding a user on spark

Add `modules/users/accounts/<name>.nix` (`sshKeys`, `shell`, `extraGroups`) and import it from `accounts/default.nix`. Per-user system config goes in `hosts/spark/<name>/`.

## CI deploys

`deploy.yml` runs `spark-deploy`, which takes no arguments and runs `nixos-rebuild switch` as its own root unit on a fresh clone of `main` from Forgejo's on-disk repository, so no job can deploy a tree of its choosing. `gitea-runner-spark` is `restartIfChanged = false`, because restarting the runner mid-deploy kills the switch. A changed runner unit applies only after a manual restart. A red X that raced a deploy may be a cancelled sibling job, so check the runner journal.

## Forgejo mirroring

- `forgejo-mirror-sync` (`hosts/spark/services/forgejo/mirror.nix`) mirrors every GitHub org repo each account can see, every 30 minutes, with pruning off. It only adds; it never deletes or converts a repo. A same-named regular forge repo blocks the mirror: rename it to `<name>-bak` first.
- The same unit gives every non-archived `harivansh-afk` forge repo without one a push mirror to `github.com/harivansh-afk/<name>`, creating the GitHub repo with the forge visibility and a deploy key. It needs `GITHUB_TOKEN` to be `harivansh-afk` with `repo` scope. An existing GitHub repo is adopted only when the forge has all of its branch heads; otherwise it is logged and skipped.
- Accounts are `GITHUB_TOKEN` (`forgejo-mirror-github-token.env`) plus `GITHUB_TOKEN_<NAME>` in `forgejo-mirror-github-accounts.env` (separate Dueflow and Wiive logins). Forgejo stores the token each mirror was created with, encrypted per mirror, so a rotated token only applies to new mirrors.

## Agent desktop

Browser and desktop work on spark goes through the `spark-computer` skill (bdu plus Cua MCP). Agents attach to the running Chromium and use their own tabs. Never commit profiles or put credentials in the store.

## Codex account gateway

`hosts/spark/services/codex-lb.nix` runs codex-lb on `127.0.0.1:18475`, and spark's Codex uses it as `model_provider`. State lives in `~/.local/state/codex-lb`. Add an account from a throwaway `CODEX_HOME`, never from `~/.codex/auth.json`:

```sh
d=$(mktemp -d); CODEX_HOME=$d codex login --device-auth
curl -F "auth_json=@$d/auth.json;type=application/json" http://127.0.0.1:18475/api/accounts/import
rm -rf "$d"
```

After changing the provider, run `codex app-server daemon restart`.

## Hermes

`hosts/spark/services/hermes.nix` runs the upstream NixOS module as the owner: `hermes-agent.service` is the gateway and `hermes-backend.service` is the dashboard plus desktop backend on `127.0.0.1:9119`, published by Tailscale Serve at `https://spark.<tailnet>.ts.net:9119` behind the basic-auth login in `hermes.env`. The default model is Codex through codex-lb; `/model claude-opus-5-5 --provider cc-proxy` switches a session to Claude through cc-proxy, whose client key Hermes reads at runtime with `cc-proxy key`. `HERMES_HOME` is `~/.local/state/hermes/.hermes`: `config.yaml` is merged from `settings` on every switch, `.env` is rebuilt from the secret, and `SOUL.md` is copied from `dots/hermes/SOUL.md`. Skills are the Nix-selected set in `skills.external_dirs`; skills the agent writes land in `dots/hermes/skills` for review and commit, and bundled skills are off. Beeper is the only MCP server. There are no declared cron jobs, messaging platforms, or plugins.

## Beeper bridges

`hosts/spark/services/beeper-bridges.nix` runs self-hosted mautrix bridges through `bbctl`, one user unit per entry in `bridges` (`beeper-<name>`, bot `@sh-<name>bot:beeper.local`). Binaries come from Nix, never from bbctl downloads. Setup: `bbctl login`, start the unit, then DM the bot `login`. State in `~/.config/bbctl` and `~/.local/share/bbctl` is private and mutable.
