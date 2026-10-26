# AGENTS.md

## Hosts

| Host | System | Role |
|------|--------|------|
| `macbook` | nix-darwin, aarch64-darwin | Workstation: Homebrew casks, Determinate Nix |
| `spark` | NixOS, aarch64-linux | DGX Spark server: disko, sops-nix, Caddy, cloudflared, Tailscale |

Host records live in `flake/args.nix`; `flake/hosts.nix` builds darwin and `flake/nixos.nix` builds NixOS.

Spark web traffic: Cloudflare edge → cloudflared → Caddy on `127.0.0.1:80` → services on loopback ports. No ACME, no public web ports.

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

On spark, Claude Code also gets the `codex` MCP server (`pkgs/codex-mcp`): `codex` and `codex_reply` run `codex exec --json` in the session directory and come back as task notifications. Codex keeps MCP OAuth tokens in files because the headless keyring hangs `codex exec`. Reauthorize Beeper with `codex mcp login beeper --oauth-client-registration dcr`.

## Layout

```
flake/        host records, builders, packages, checks
lib/          palette.json, theme.nix (renderers), neovim.nix, remotes.nix, agent-instructions.nix
modules/      common.nix, nix-settings.nix, users/ (user-config, accounts), security/sops.nix
hosts/macbook defaults, homebrew, launchd services, startup guard, voiceink, logitech
hosts/spark   hardware, networking, users, kernel hardening, services/ (one file per service)
pkgs/         sets.nix, scripts/, zmx/, codex-mcp/, other derivations
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
- A Rex pane runs `rex-spark`, which runs `ssh -t spark zmx attach rex-<REX_BLOCK>` and reconnects when ssh drops. Closing the pane kills the session. `REX_LOCAL=1` (the `ctrl+b shift+hjkl` splits) gives a plain Mac shell.

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

`deploy.yml` runs `spark-deploy`, which runs `nixos-rebuild switch` as its own root unit. `gitea-runner-spark` is `restartIfChanged = false`, because restarting the runner mid-deploy kills the switch. A changed runner unit applies only after a manual restart. A red X that raced a deploy may be a cancelled sibling job, so check the runner journal.

## Forgejo mirroring

- `hosts/spark/services/forgejo/mirror-manifest.nix` holds policy only. Repos are discovered from Forgejo's database, and `scripts/reconcile.sh` (root, `--dry-run` available) makes the mirror tables match.
- Owned repos are forge-canonical and push-mirror to GitHub. Repos in `github_canonical_repos` are inbound pull mirrors instead.
- Pull mirrors authenticate through one credential-store entry fed by `secrets/hosts/spark/forgejo-mirror-github-token.env`: a classic PAT with `repo` scope and no expiry. A dead token only breaks private mirrors, and `mirror_updated` advances even when a sync fails, so check with `journalctl -u forgejo | rg "Invalid username or token"`.

## Agent desktop

Browser and desktop work on spark goes through the `spark-computer` skill (agent-browser plus Cua MCP). Agents attach to the running Chromium and use their own tabs. Never commit profiles or put credentials in the store.

## Codex account gateway

`hosts/spark/services/codex-lb.nix` runs codex-lb on `127.0.0.1:18475`, and spark's Codex uses it as `model_provider`. State lives in `~/.local/state/codex-lb`. Add an account from a throwaway `CODEX_HOME`, never from `~/.codex/auth.json`:

```sh
d=$(mktemp -d); CODEX_HOME=$d codex login --device-auth
curl -F "auth_json=@$d/auth.json;type=application/json" http://127.0.0.1:18475/api/accounts/import
rm -rf "$d"
```

After changing the provider, run `codex app-server daemon restart`.

## Beeper bridges

`hosts/spark/services/beeper-bridges.nix` runs self-hosted mautrix bridges through `bbctl`, one user unit per entry in `bridges` (`beeper-<name>`, bot `@sh-<name>bot:beeper.local`). Binaries come from Nix, never from bbctl downloads. Setup: `bbctl login`, start the unit, then DM the bot `login`. State in `~/.config/bbctl` and `~/.local/share/bbctl` is private and mutable.
