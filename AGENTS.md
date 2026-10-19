# AGENTS.md

## Architecture

Two hosts, one flake:

| Host | Platform | System | Role |
|------|----------|--------|------|
| `macbook` | nix-darwin | aarch64-darwin | Dev workstation |
| `spark` | NixOS | aarch64-linux | NVIDIA DGX Spark server |

Both are declared as host records in `flake/args.nix` and assembled in `flake/hosts.nix` (darwin) and `flake/nixos.nix` (nixos). The same args module wires the shared args (`hosts`, `mkSpecialArgs`) consumed by both host builders; each host's primary `username` comes from its record.

### Host topology

- `macbook`: nix-darwin + Homebrew casks + Determinate Nix
- `spark`: NixOS + disko + sops-nix + dgx-spark upstream module + Caddy + cloudflared tunnel + Tailscale

### Service routing on spark

Internet traffic hits Cloudflare edge (TLS termination), then cloudflared tunnel delivers plain HTTP to Caddy on 127.0.0.1:80. Caddy dispatches by Host header to backend services, each bound to 127.0.0.1 on their own port. No ACME, no public firewall ports for web traffic.

Services: Forgejo (`git.harivan.sh`), Vaultwarden (`vault.harivan.sh`), draw (`draw.harivan.sh`, self-hosted Excalidraw+ from the `draw` flake input; see `hosts/spark/docs/draw.md`).

### Secrets

sops-nix with age encryption derived from each host's ed25519 SSH key. Secret files live under `secrets/hosts/<hostname>/` (plus per-admin secrets under `secrets/user/`). Edit with `just sops-edit secrets/hosts/spark/<file>`.

`.sops.yaml` recipient anchors are derived via `ssh-to-age`:

- `admin_macbook` — Hari's macbook SSH pubkey, edits everything.
- `host_spark` — Spark's `/etc/ssh/ssh_host_ed25519_key.pub`, decrypts at activation.

`secrets/hosts/spark/[^/]+$` encrypts secrets for `admin_macbook` and `host_spark`.

`secrets/registry.nix` declares every secret. `KEY=value` files under `secrets/user/` are named `.env` and sourced into interactive zsh; raw tokens have no extension and set `exposeToShell = false`.

## Conventions

- No comments in `.nix` files. The code is the documentation. Agent guidance lives here.
- Use `just switch` for macbook rebuilds, `just switch-spark` for spark rebuilds.
- `just fmt` runs `nix fmt` (nixfmt-tree).
- Pull requests for this repo go to Forgejo (`origin`, git.harivan.sh), never GitHub. The `github` remote is a push-mirror target only; its redirect-pr workflow auto-closes PRs opened there. Create PRs with `tea pr create --login harivan --repo harivansh-afk/nix --base main --head <branch>`.
- For multiline PR bodies, pass a real file's contents to `tea pr create --description` (or `gh --body-file -` when working on actual GitHub repos). Do not pass escaped `\\n` text; it renders as literal backslash-n. After creating or editing a PR, verify the rendered body before calling it done.
- Prefer common package definitions across macbook and spark; keep only truly macOS-specific Homebrew and GUI integrations Darwin-only.
- Bugfix PRs keep the diff minimal and exclude unrelated changes.
- Berkeley Mono is installed out-of-band. The flake only provides nerd-fonts symbol glyphs.
- There is no home-manager. Per-user config is `modules/users/user-config.nix`: plain dotfiles in `dots/` symlinked into the home directory by an activation script that runs as the user. The repo owner's links point at the live checkout (`~/Documents/Git/nix/dots`), so dotfile edits apply without a rebuild; other users get the nix-store copy. Configs that need store paths (zsh plugins, git credential helpers, theme renders) are store-generated shims that defer to the live dots file.
- Ghostty is installed via Homebrew cask, not nixpkgs. The flake owns its config files and its terminfo: `xterm-ghostty` is declarative in `modules/common.nix` (`pkgs.ghostty-bin.terminfo` on darwin, `pkgs.ghostty.terminfo` on linux) so env-scrubbed shells resolve it without `TERMINFO`. Never fix terminfo imperatively via `tic` into `~/.terminfo`.
- Neovim uses one package definition, `lib/neovim.nix`, for workstations and the portable command. Nix owns plugins, grammars, and matched queries; `lz.n` owns lazy loading. Plugin pins live in `dots/nvim/pack-sources.json`; update one with `just nvim-update <plugin> [revision]` and rebuild. Never add runtime installs or seed writable plugin copies. Keep the query-inheritance build check: missing shared queries silently break highlighting.
- Karabiner config is a directory symlink to `dots/karabiner/` so Karabiner can write freely.
- Claude and Codex are curl-installed binaries. On NixOS they need nix-ld.
- Devin config is seeded as a mutable copy since Devin rewrites it.
- `devin-codex` packages only the adapter; it uses the installed Codex and existing Devin login. Its native `/model` selector writes `~/.codex/devin-codex.config.toml`; leave that profile mutable and keep credentials out of the Nix closure. Protocol fixes belong in `~/Documents/Git/devin-codex`, then update this flake's input.

## Worktrees

- Always create task worktrees under the repo-local `.worktrees/<topic>` directory. For this repo, that means paths like `/home/rathi/Documents/Git/nix/.worktrees/<topic>`.
- Do not create sibling worktree directories such as `/home/rathi/Documents/Git/nix-<topic>` or global worktree directories such as `~/wt/<repo>/<topic>`.
- Create worktrees with plain Git from the main checkout: `git worktree add .worktrees/<topic> -b <branch> main`.
- Keep the main checkout on `main` unless the user explicitly asks otherwise.

## Agent instructions

Instructions for every agent harness are layered in `dots/agents/` and rendered by `lib/agent-instructions.nix`:

| Part | Read by | Holds |
|------|---------|-------|
| `core.md` | every agent | who Hari is, machines, forge, knowledge base, how to work with him |
| `coding.md` | Claude Code, Codex | tooling, git conventions, Spark CLI tools |
| `claude.md` | Claude Code | Claude-only steering (prose questions, outcome-first replies, delegation) |

Rendered outputs: `~/.claude/CLAUDE.md` (core + coding + claude), `~/.codex/AGENTS.md` (core + coding). A fact that is true for two parts moves up to `core.md`; a repo-specific fact belongs in that repo's `AGENTS.md` (this file), which the tracked `CLAUDE.md` imports with `@AGENTS.md`. Keep that file as the single import so local copies cannot accumulate conflicting instructions.

Skills come from the `mattpocock-skills` flake input. `modules/users/user-config/agents.nix` builds the selected skills into one link farm and the activation script links it to `~/.agents/skills` (Codex, and anything agentskills.io-compatible) and `~/.claude/skills` (Claude Code). Upgrade them with `nix flake update mattpocock-skills`.

No agent harness has hooks configured, and none should be created.

On spark, Claude Code delegates to Codex instead of its own subagents: `permissions.deny = [ "Agent" "Workflow" ]` (workflow scripts can only spawn Claude subagents), plus the `codex` MCP server from `pkgs/codex-mcp` (one Python file on the MCP SDK). Its `codex(prompt)` and `codex_reply(thread_id, prompt)` tools run `codex exec --json` in the session's directory with the normal Codex config (`gpt-6-astra`, medium), stream each event as MCP progress, and return the status, thread id, files changed and Codex's final message. Claude Code moves calls running past 10s (`CLAUDE_CODE_MCP_AUTO_BACKGROUND_MS`) to `/tasks`, and the result comes back as a task notification. Stopping the task kills Codex. A run with no events for 20 minutes (`CODEX_MCP_STALL_SECONDS`) is stopped and reported as `stalled`. The server's MCP instructions carry the delegation guidance.

## Module layout

```
flake.nix              Inputs + flake-parts structure
flake/
  args.nix             Host records (the two machines) + shared builders (mkPkgs, mkSpecialArgs)
  devshell.nix         Dev tools + formatter
  hosts.nix            macbook darwin configuration
  nixos.nix            spark NixOS configuration
  packages.nix         packages.<system> output: portable scripts (ga, connectors) + tool wrappers
lib/
  remotes.nix          Remote server registry: hosts for the per-remote connector commands
  theme.nix            Cozybox theme: colors, renderers for ghostty/fzf/pure-prompt/rex/sketchybar/zsh-highlights
modules/
  common.nix           Shared nix settings, overlays, the shared package set, fonts
  nix-settings.nix     nix.conf settings both hosts share (nix.settings on spark, determinateNix.customSettings on darwin)
  users/
    user-config.nix    Shared per-user dotfile/symlink/package builder (no home-manager)
    accounts/          User registry (rathi.nix: SSH keys + groups)
    nixos.nix          NixOS adapter: every user in accounts/, owner gets live dots
    darwin.nix         nix-darwin adapter: primary user, live dots
  security/
    sops.nix           sops-nix setup, age key from SSH host key
hosts/
  macbook/
    default.nix        Facts + imports only (hostname, user, stateVersion)
    apps.nix           GUI apps nix launches at login (apps with their own launch-at-login are NOT duplicated here)
    defaults.nix       System defaults (dock, finder, keyboard, screenshots, loginwindow)
    homebrew.nix       Taps, formulae, casks (every cask on the machine is declared)
    services.nix       Every launchd unit (aerospace, sketchybar, limit.maxfiles); the only service manager
    startup/           Login-item allowlist enforcement, undeclared launchd plist warnings (default.nix + guard.sh)
    voiceink/          VoiceInk built from source at activation (default.nix + build.sh)
    notch-inset/, sketchybar-feed/  ObjC sources compiled by services.nix
  spark/
    default.nix        Base NixOS config, nix-ld, verified boot
    hardware.nix       DGX Spark module + disko disk layout
    kernel-hardening.nix  Running-kernel boundary: module lock, sysctls, LSM order
    networking.nix     Wi-Fi (NetworkManager), Tailscale, firewall, zram
    users.nix          User accounts from modules/users/accounts, SSH, sudo
    docs/              Notes on the verified-boot, module-lock and strict-DMA setup
    services/          Every spark service; single-host, so they live with the host
      caddy.nix        Reverse proxy on loopback, loopbackVhost helper
      cloudflared.nix  Cloudflare tunnel to Caddy
      draw.nix         draw (self-hosted Excalidraw+) via the draw flake's NixOS module
      hermes/          Hermes gateway, desktop backend and messaging profiles
      inference.nix    Local vLLM inference container (GPU)
      mosh.nix         Mosh UDP server config
      vaultwarden.nix  Vaultwarden password manager
      website.nix      harivan.sh static site; caddy logs the view beacon, website-views timer bakes the counts (tools/views.mjs in the website repo)
      forgejo/         Forgejo server, cozybox css in assets/, mirror manifest, Actions runner, run-by-hand scripts/
pkgs/
  codex-mcp/           MCP server that gives Claude Code the codex and codex_reply tools
  sets.nix             Shared package sets (core, extras, darwinExtras, fonts) for modules/common.nix
  scripts/
    default.nix        Full script set for user profiles (portable + theme, account helpers)
    portable.nix       Home-independent scripts (ga, remote connectors)
    bin/               Script sources wired by default.nix
    lib/               Rex font helper (rex-font.py)
terraform/
  cloudflare/          Declarative Cloudflare DNS for harivan.sh and hari.cafe via terranix
scripts/               Repo tooling: nvim-smoke.sh, nvim-update.sh
assets/                Readme artwork + the static wallpapers
dots/                  Dotfile sources (nvim, karabiner, lazygit, agents/ instructions + skills, etc.)
```

## Theme system

The "cozybox" theme has dark and light variants defined in `lib/theme.nix`. A runtime state file at `~/.local/state/theme/current` holds `dark` or `light`. The `theme` script (from `pkgs/scripts/bin/theme.sh`) switches mode by updating symlinks for fzf, ghostty, and the wallpaper, then pokes live nvim servers. Wallpapers are fixed store assets: black for dark mode and white for light mode. Shell hooks in `dots/zsh/zshrc` re-apply prompt colors, zsh syntax highlights, and bat theme on every `precmd`.

## Remote sessions

Terminal sessions, panes, and persistence are the job of muxd (`~/Documents/Git/mux`): Rex panes on spark attach to spark's muxd through the Mac's (see Rex below), and a muxd restart takes every pane with it, so the `mux` input is bumped deliberately, never as part of a routine `nix flake update`. spark runs the daemon via `hosts/spark/services/muxd.nix`. Nothing in this repo multiplexes terminals.

The portable scripts (`ga`, the remote connectors) build without a home directory (`pkgs/scripts/portable.nix`) and are exposed as flake `packages`, so hosts not managed by this flake can install them with `nix profile add git+https://git.harivan.sh/harivansh-afk/nix#<name>`.

`lib/remotes.nix` maps a command name to the remote hostname. `pkgs/scripts/portable.nix` renders each entry into a connector command (via `pkgs/scripts/bin/remote.sh`) that lands in every user's profile: `spark` or `macbook` opens a shell over `mosh <host>`; `--ssh` forces `ssh -t` for UDP-hostile networks. Transport config (hostnames, keys, ControlMaster) stays in the live-edited `dots/ssh/config`; ssh, scp, and git are never wrapped. To add a server: one entry in `lib/remotes.nix` plus its `Host` block in `dots/ssh/config`.

## Rex

Rex (Superlogical's multiplexer, `/Applications/Rex Beta.app`) is installed by hand: the beta download sits behind a Discord login and Sparkle updates it in place. Everything else is declared here and applied by the darwin activation script.

- `dots/rex/init.lua` is linked to `~/.config/rex/init.lua` and read by the Rex server: ⌘K clears like Ghostty, ⌘⌥+arrows and ⌘[ / ⌘] move between panes, and `ctrl+b` sequences follow Mux's prefix keys. Apply edits with `rex config reload`; `rex keymap` shows the merged keymap. Shortcuts recorded in Rex's Settings override this file, so record none.
- Rex keeps its theme, font and terminal options in `com.superlogical.rex` defaults, not in a file. Activation rewrites them on every switch: the Cozybox themes from `theme.renderRex`, plus every other key in `rexDefaults` (`modules/users/user-config/apps.nix`), which carries the font, option-as-alt, padding colour and copy-on-select from Ghostty's config and the interface choices. To keep a setting changed in Rex's Settings, add it there; read the current values with `defaults read com.superlogical.rex`. Changing one of them in Settings lasts until the next switch. Quit and reopen Rex to pick up a change.
- Rex has one terminal font and no `font-codepoint-map`. Activation copies the nonicons glyphs into the out-of-band Berkeley Mono (`pkgs/scripts/lib/rex-font.py`, fontTools) as `~/Library/Fonts/BerkeleyMonoNonicons-*.otf`, family `Berkeley Mono Nonicons`, and rebuilds it only when an input changes. The icons keep nonicons' own em size, larger than a cell, because Ghostty's renderer (which Rex uses) only shrinks Nerd Font range glyphs to fit, into two cells when a space follows. Never use nerd-font-patcher here: it merges its Devicons set too, whose glyph names collide with Berkeley Mono's and shift its punctuation. Nothing is built when Berkeley Mono is missing.
- Rex starts panes as `xterm-256color` without shell integration, and muxd panes start as `xterm-ghostty` without it. `dots/zsh/zshrc` sets `TERM=xterm-ghostty` inside Rex and sources Ghostty's zsh integration in any `xterm-ghostty` shell outside Ghostty itself, for the OSC 133 prompt marks and OSC 7 working directory that Rex's program status and pane directory read. The Mac uses Rex's bundled copy (`GHOSTTY_RESOURCES_DIR`); on linux the zshrc shim exports `GHOSTTY_SHELL_INTEGRATION_DIR` from `pkgs.ghostty.shell_integration` (120 KiB, cached), so spark panes mark their prompts too.
- `rex` on PATH is `~/.local/bin/rex`, a link to the app's bundled CLI at `Contents/Helpers/Rex Server.rex/Contents/MacOS/rex` (`Rex Server.app` before the October 2026 builds; activation links whichever exists).
- No remote hosts are declared: Rex ships only its macOS server so far, so spark cannot serve Rex sessions yet. Spark panes go through Mux instead: inside Rex, `dots/zsh/zshrc` runs `rex-spark` (`pkgs/scripts/bin/rex-spark.sh`), which attaches the pane to a muxd pty on spark named `rex-<REX_BLOCK>` through the Mac's muxd, so a reopened pane reclaims its own shell; a new pane always gets a fresh pty. `ctrl+b '` and `ctrl+b -` split through `rex.session.new_split` with `REX_PARENT` set, and `rex-spark` passes `--cwd-from rex-<parent>` so the new spark pty starts in its parent's directory. The pty outlives sleep and reboots; closing the pane (or quitting Rex) closes it.
- Rex reads a pane's program (icon, status, the cmd+k rule) from the Mac process in the pty's foreground, and nothing in an escape sequence substitutes for that. Two things make a spark pane read like a native one. zshrc runs `rex-spark` as a job rather than an exec, so the relay has its own process group and is the foreground Rex inspects (an exec stays in `login`'s group and Rex sees `login`). And `mux-attach --mirror-foreground` re-execs itself under `~/.local/state/mux/as/<name>`, a link to its binary, whenever spark's muxd reports a new foreground program there, on the same socket with no replay: Rex finds a process invoked as `claude` and runs its Claude detector over the title and screen bytes, which pass through muxd unchanged. The one native detail missing is Rex's session-file reader, which cannot see spark; the on-screen permission prompt covers `blocked`. `ctrl+b shift+h/j/k/l` splits a plain Mac shell off the focused pane on that side (`local_split_*` in `dots/rex/init.lua`, a block with a `command`, which starts from a non-interactive login shell that zshrc never routes to spark, with `REX_LOCAL=1`). It starts in the focused pane's directory, read from the terminal block's `pwd` method with a spark pane's home mapped to the Mac's; Rex falls back to home when the path does not exist on the Mac. `ctrl+b r` then `shift+h/j/k/l` moves the focused pane to that side of its neighbour, as Mux's resize mode does (`move_pane_*`, which reads the session view for rects and calls `rex.session.move_block`). `cmd+k` clears a pane whose foreground is a relay (`mux-attach`, `mosh-client`) as well as a shell. `mux-attach` and `muxd` reach PATH from `hosts/macbook/muxd.nix`.

## Key dependencies

- `dgx-spark`: Upstream NixOS module for DGX Spark hardware. Do not set `inputs.nixpkgs.follows` - the upstream pins nixpkgs to a known-good revision for the NVIDIA kernel build. It also makes podman the machine's only container runtime and serves the Docker-compatible API at `/run/podman/podman.sock` (`dockerCompat`, `dockerSocket.enable`, socket group `podman`); anything speaking the Docker API (dockerode, docker CLI) uses that socket. Never set `virtualisation.docker.enable` - it conflicts with the podman socket, and enabling it rewired the CI runner's unit and aborted the #479 deploy mid-switch.
- `determinate`: Manages the Nix installation, daemon, and `/etc/nix/nix.conf`. On darwin, use `determinateNix.customSettings` instead of `nix.settings`.
- `neovim-nightly`: Both hosts' `nvim` runs this input's `packages.<system>.default`, passed to `lib/neovim.nix` through the user-config adapters; the `neovim` flake check uses it too. Never apply its overlay: replacing `pkgs.neovim` rebuilds every vim plugin and treesitter grammar from source (~660 derivations on spark). The portable command uses it too: the config relies on nightly-only runtime such as the `dir` directory viewer. nix-community's cache has no aarch64-linux build, so spark compiles nightly whenever the pin moves.

## Adding a new service on spark

1. Create `hosts/spark/services/<name>.nix`.
2. Add the sops secret: create `secrets/hosts/spark/<name>.env`, encrypt with `just sops-edit`, and register it in `secrets/registry.nix`.
3. Use `loopbackVhost` from caddy.nix: `services.caddy.virtualHosts."http://<domain>" = loopbackVhost <port>;`.
4. Import the new module in `hosts/spark/default.nix`.
5. Add the DNS record in Cloudflare pointing to the tunnel.

## Adding a new user on spark

1. Create `modules/users/accounts/<name>.nix` with `sshKeys`, `shell`, and `extraGroups`.
2. Add its import to `modules/users/accounts/default.nix`. `hosts/spark/users.nix` creates the account and `modules/users/nixos.nix` installs dotfiles and packages; non-owner dotfiles point at the Nix store.
3. For user-specific system config (services, slices), add a module under `hosts/spark/<name>/` and import it from `hosts/spark/default.nix`.

## CI deploys

`deploy.yml` runs `spark-deploy`, which starts `nixos-rebuild switch` as its own root unit (`spark-deploy-<epoch>`) and prints its journal when it finishes, so a switch that stops or replaces the runner no longer takes the switch down with it. The pin below still keeps routine deploys from restarting the runner: `gitea-runner-spark.service` is pinned `restartIfChanged = false` in `hosts/spark/services/forgejo/default.nix`. Without it, any config change that touches the runner unit (enabling docker did, via the gitea-actions-runner module's docker-label wiring) makes activation restart the runner mid-deploy; the runner's `shutdown_timeout=0s` kills its own jobs, including the nixos-rebuild driving the switch, and `switch-to-configuration` dies with its pty, leaving the system half-switched (the #479 deploy stopped postgresql and the runner this way and restarted neither). The cost: a changed runner unit lands on disk at switch but only applies on the next manual `systemctl restart gitea-runner-spark` or reboot. A cancelled sibling job on the same runner reads as a spurious failure (that is what "quality / Nix Format Check: failing after 0s" was), so check the runner journal before trusting a red X that raced a deploy.

## Forgejo mirroring

The legacy gitea-mirror Bun service has been removed. Forgejo's native mirror tables (`mirror` for inbound pulls, `push_mirror` for outbound pushes) are the source of truth. Two files drive the system:

- `hosts/spark/services/forgejo/mirror-manifest.nix`: policy-only config (intervals, `owned_owner`, the `github_canonical_repos` and `actions_enabled_repos` lists, `retired_mirror_owners`). No repo inventory is checked into nix; the actual list of repos to mirror is discovered at runtime by querying forgejo's own database. Rendered to `/etc/forgejo-mirror/manifest.json` at activation.
- `hosts/spark/services/forgejo/scripts/reconcile.sh`: idempotent script that reads the manifest, deletes pull-mirror rows on push-mirror targets, creates missing push-mirrors with `use_ssh=true sync_on_commit=true interval=15m`, registers the forgejo-generated public key as a github deploy key, and flips `has_actions` per the allowlist. Run as root: `sudo FORGEJO_MIRROR_MANIFEST=/etc/forgejo-mirror/manifest.json bash hosts/spark/services/forgejo/scripts/reconcile.sh [--dry-run]`.
- `hosts/spark/services/forgejo/scripts/github-ux.sh`: optional, applies the barrettruth full treatment (github description/homepage/has_* metadata, `.github/README.md` banner, redirect-pr workflow) to every push-mirror. Run on demand: `bash hosts/spark/services/forgejo/scripts/github-ux.sh [--dry-run] [--only owner/name]`.

### GitHub-canonical repos

Owned repos default to forge-canonical with a push-mirror to GitHub. `github_canonical_repos` in the manifest inverts that for the few whose truth has to live on GitHub (TouchedTips: Xcode Cloud builds from GitHub and PRs merge there). Such a repo sits on the forge as an ordinary inbound pull mirror, and phase 1 of reconcile.sh deletes any push-mirror it finds on it instead of creating one. To add one: rename the existing forge repo aside and archive it, migrate the GitHub repo as a mirror under the original name (`POST /repos/migrate` with `mirror: true`), add `owner/name` to the manifest, `just switch-spark`. Matching is case-insensitive, since the DB rows carry `lower_name`.

### Pull-mirror credentials

Inbound pull mirrors do not carry per-repo credentials. Their remote URLs are bare `https://github.com/...` and git resolves auth through a single host-scoped entry written by the forgejo `preStart` hook:

```
credential.helper = store --file /var/lib/forgejo/.git-credentials
```

The token behind it lives in its own secret, `secrets/hosts/spark/forgejo-mirror-github-token.env` (`GITHUB_TOKEN=<classic PAT with repo scope>`). It is deliberately split from `forgejo-mirror.env`, which holds the long-lived `FORGEJO_TOKEN` used by `forgejo-actions-enforce` and `avatar-backfill.sh`: the GitHub PAT is rotated on an expiry cadence and routine rotation should not touch the Forgejo API token.

Rotating is one edit plus a rebuild, never per-repo work:

```
just sops-edit secrets/hosts/spark/forgejo-mirror-github-token.env
just switch-spark
```

Generate the PAT with the **`repo`** scope and **no expiration**. A scopeless token still authenticates and still fetches public repos, so it looks healthy while every private mirror fails.

Two failure modes to know about. Git only consults the credential helper on a `401`, so when the token dies, public mirrors keep syncing and only private ones break: partial symptoms, not total. And forgejo bumps `mirror_updated` even when a sync fails, so the UI shows fresh timestamps on mirrors that have not updated in months. Never trust `mirror_updated` to prove a mirror is current; compare HEAD against upstream, or grep the journal:

```
journalctl -u forgejo --since today | rg "Invalid username or token"
```

Forgejo's own `[mirror] DEFAULT_INTERVAL` is `15m` and `[queue.mirror] MAX_WORKERS` is capped at `1`. The pre-start hook in `hosts/spark/services/forgejo/default.nix` uniformly jitters every pull-mirror's `next_update_unix` to `now + (repo_id % 900s)` on each forgejo start, so 100+ mirrors never bunch into a single hour the way they did under the old gitea-mirror scheduler.

## Hermes

Hermes runs through upstream's NixOS module in `hosts/spark/services/hermes/default.nix`.
The gateway and dashboard share `~/.local/state/hermes/.hermes`; the `~/.hermes`
symlink keeps existing CLI state reachable. Desktop uses Devin Astra; Relay uses Claude Opus 5.5;
provider setup and limitations are in `hosts/spark/docs/hermes.md`.
Browser and desktop actions use agent-browser CLI and upstream Cua MCP
through the `spark-computer` skill, also installed for coding agents. Delegation,
memory and skills are enabled for CLI and Relay. The personal KB,
its ingestion and embedding services, and its Hermes plugin are disabled.

Chromium's existing Default profile is private mutable state; agents attach to
the running browser and create task-owned tabs. Never commit profiles or put credentials
in the store. For browser identity, Sway/CUA diagnostics, Relay recovery or
post-deployment acceptance, read `hosts/spark/docs/hermes.md`.

Nix owns runtimes, settings and the assistant guidance in `dots/hermes/`. Memory,
learned skills and conversation state persist across rebuilds. Scheduled work is
created only on request; the old scanners, graph and automatic loops remain absent.

## Codex account gateway

`hosts/spark/services/codex-lb.nix` runs codex-lb (the `codex-lb` input) as the
`codex-lb` user unit on `127.0.0.1:18475`, with telemetry and dashboard auth off
(loopback, single user). Spark's Codex config sets `model_provider = "codex-lb"`,
so every Codex process on spark, the `codex` MCP tool included, spreads across the
pooled ChatGPT accounts. Sticky threads keep a thread on one account. The gateway
owns OAuth refresh; accounts, its encryption key and SQLite database live in
private mutable `~/.local/state/codex-lb`, outside Git and the store.

Add an account without the dashboard: log in fresh with a throwaway `CODEX_HOME`,
import its `auth.json`, then delete it. Never import `~/.codex/auth.json`: sharing
one refresh token between codex-lb and local Codex breaks whichever refreshes second.

```sh
d=$(mktemp -d); CODEX_HOME=$d codex login --device-auth
curl -F "auth_json=@$d/auth.json;type=application/json" http://127.0.0.1:18475/api/accounts/import
rm -rf "$d"
curl -s http://127.0.0.1:18475/api/accounts | jq '.accounts[] | {email, status}'
```

Codex still needs its own `codex login` for `requires_openai_auth`. A provider
change needs `codex app-server daemon restart`.

## Beeper self-hosted bridges

`hosts/spark/services/beeper-bridges.nix` runs mautrix bridges on spark through
`bbctl` (nixpkgs `beeper-bridge-manager`, source-overridden to the latest upstream
tag because Beeper's server refuses older clients at login with "Your client is
out of date"), registered against the owner's Beeper account. Self-hosted bridges are free and do not count toward Beeper's account
limits, which is the point: unlimited networks and unlimited accounts per network.
The `bridges` attrset maps a short name to the bridge package; `mkBridge` stamps
out one user unit per entry (`beeper-<name>`, bbctl bridge name `sh-<name>`,
bot `@sh-<name>bot:beeper.local`). `--custom-startup-command` points bbctl at
the Nix-packaged binary so it never downloads or updates bridges outside Nix.
Slack uses the hash-pinned upstream ARM64 release: nixpkgs' 26.05 aborts login
when Slack omits version metadata, while 26.09.1 continues successfully.
For source-built bridges, prefer `withGoolm = true` to avoid libolm's
insecure-package allowlist.

First-time setup is interactive: `bbctl login`, then `systemctl --user start
beeper-slack`, then DM `@sh-slackbot:beeper.local` in Beeper and `login` once per
Slack workspace (one bridge process holds every workspace). Units skip startup
until `~/.config/bbctl/config.json` exists. Credentials and bridge databases live
in private mutable `~/.config/bbctl` and `~/.local/share/bbctl/prod/<bridge>`;
preserve both across rebuilds and keep them out of Git and the Nix store.
Verify a real chat in Beeper before removing the equivalent cloud or on-device
connection. Signal stays on-device; iMessage needs the macbook, not spark.
