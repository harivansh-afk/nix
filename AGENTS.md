# AGENTS.md

## Architecture

Two hosts, one flake:

| Host | Platform | System | Role |
|------|----------|--------|------|
| `macbook` | nix-darwin | aarch64-darwin | Dev workstation |
| `spark` | NixOS | aarch64-linux | NVIDIA DGX Spark server |

Both are declared in `inventory/nodes/` and assembled in `flake/hosts.nix` (darwin) and `flake/nixos.nix` (nixos). The `flake/args.nix` module wires shared args (`hosts`, `mkSpecialArgs`) consumed by both host builders; each host's primary `username` comes from its inventory record.

### Host topology

- `macbook`: nix-darwin + Homebrew casks + Determinate Nix
- `spark`: NixOS + disko + sops-nix + dgx-spark upstream module + Caddy + cloudflared tunnel + Tailscale

### Service routing on spark

Internet traffic hits Cloudflare edge (TLS termination), then cloudflared tunnel delivers plain HTTP to Caddy on 127.0.0.1:80. Caddy dispatches by Host header to backend services, each bound to 127.0.0.1 on their own port. No ACME, no public firewall ports for web traffic.

Services: Forgejo (`git.harivan.sh`), Vaultwarden (`vault.harivan.sh`), Delta (`delta.harivan.sh`).

### Secrets

sops-nix with age encryption derived from each host's ed25519 SSH key. Secret files live under `secrets/hosts/<hostname>/` (plus per-admin secrets under `secrets/user/`). Edit with `just sops-edit secrets/hosts/spark/<file>`.

`.sops.yaml` recipient anchors are derived via `ssh-to-age`:

- `admin_macbook` — Hari's macbook SSH pubkey, edits everything.
- `admin_laptop_barrett` — Barrett's laptop SSH pubkey, edits only `secrets/hosts/spark/barrett-*`.
- `host_spark` — Spark's `/etc/ssh/ssh_host_ed25519_key.pub`, decrypts at activation.

Path-regex split:

- `secrets/hosts/spark/barrett-[^/]+$` → `admin_macbook` + `admin_laptop_barrett` + `host_spark`. Used for secrets Barrett owns and rotates from his side (currently `barrett-forgejo-runner-token`).
- `secrets/hosts/spark/[^/]+$` → `admin_macbook` + `host_spark`. Default for everything else.

To add a Barrett-owned secret: drop the file at `secrets/hosts/spark/barrett-<name>`; the `barrett-` prefix routes it through the 3-recipient rule automatically. No `.sops.yaml` edit needed.

## Conventions

- No comments in `.nix` files. The code is the documentation. Agent guidance lives here.
- Use `just switch` for macbook rebuilds, `just switch-spark` for spark rebuilds.
- `just fmt` runs `nix fmt` (nixfmt-tree).
- Pull requests for this repo go to Forgejo (`origin`, git.harivan.sh), never GitHub. The `github` remote is a push-mirror target only; its redirect-pr workflow auto-closes PRs opened there. Create PRs with `tea pr create --login harivan --repo harivansh-afk/nix --base main --head <branch>`.
- For multiline PR bodies, pass a real file's contents to `tea pr create --description` (or `gh --body-file -` when working on actual GitHub repos). Do not pass escaped `\\n` text; it renders as literal backslash-n. After creating or editing a PR, verify the rendered body before calling it done.
- Install spark from scratch with `just spark-install user@host`.
- The `tmp/` directory is gitignored local scratch space. Nothing there is tracked or load-bearing.
- Berkeley Mono is installed out-of-band. The flake only provides nerd-fonts symbol glyphs.
- There is no home-manager. Per-user config is `modules/users/user-config.nix`: plain dotfiles in `dots/` symlinked into the home directory by an activation script that runs as the user. The repo owner's links point at the live checkout (`~/Documents/Git/nix/dots`), so dotfile edits apply without a rebuild; other users get the nix-store copy. Configs that need store paths (zsh plugins, git credential helpers, theme renders) are store-generated shims that defer to the live dots file.
- Ghostty is installed via Homebrew cask, not nixpkgs. The flake owns only its config files.
- Karabiner config is a directory symlink to `dots/karabiner/` so Karabiner can write freely.
- Cursor-agent, Claude, and Codex are curl-installed binaries. On NixOS they need nix-ld.
- Devin config is seeded as a mutable copy since Devin rewrites it.

## Worktrees

- Always create task worktrees under the repo-local `.worktrees/<topic>` directory. For this repo, that means paths like `/home/rathi/Documents/Git/nix/.worktrees/<topic>`.
- Do not create sibling worktree directories such as `/home/rathi/Documents/Git/nix-<topic>` or global worktree directories such as `~/wt/<repo>/<topic>`.
- Create worktrees with plain Git from the main checkout: `git worktree add .worktrees/<topic> -b <branch> main`.
- Keep the main checkout on `main` unless the user explicitly asks otherwise.

## Module layout

```
flake.nix              Inputs + flake-parts structure
flake/
  args.nix             Shared args: host records, builders
  devshell.nix         Dev tools + formatter
  hosts.nix            macbook darwin configuration
  nixos.nix            spark NixOS configuration
  scripts.nix          packages.<system> output: portable scripts (mux, ga, ghpr, connectors)
lib/
  remotes.nix          Remote server registry: hosts for the per-remote connector commands
  theme.nix            Cozybox theme: colors, renderers for ghostty/fzf/lazygit/pure-prompt/bat/zsh-highlights
system/
  common.nix           Shared nix settings, overlays, base packages
  packages.nix         Extra packages + fonts
hosts/
  macbook/
    default.nix        Homebrew casks, user setup
    macos.nix          System defaults (dock, finder, keyboard, screenshots, login items, tailscale)
  spark/
    default.nix        Base NixOS config, nix-ld, kernel hardening
    hardware.nix       DGX Spark module + disko disk layout
    networking.nix     Wi-Fi (NetworkManager), Tailscale, firewall, zram
    users.nix          User accounts from users/ directory, SSH, sudo
    barrett/           Barrett's forgejo runners + spark-build slice (user units via activation)
modules/
  users/
    user-config.nix    Shared per-user dotfile/symlink/package builder (no home-manager)
    nixos.nix          NixOS adapter: every user in users/, owner gets live dots
    darwin.nix         nix-darwin adapter: primary user, live dots
  security/
    sops.nix           sops-nix setup, age key from SSH host key
    user-isolation.nix Per-user cgroup memory caps for shared accounts on spark
  services/
    caddy.nix          Reverse proxy on loopback, loopbackVhost helper
    cloudflared.nix    Cloudflare tunnel to Caddy
    delta.nix          Delta todo app service
    inference.nix      Local llama.cpp inference server (GPU)
    mosh.nix           Mosh UDP server config
    parakeet.nix       GPU speech-to-text server (parakeet.harivan.sh)
    vaultwarden.nix    Vaultwarden password manager
    website.nix        Static site for harivan.sh served via Caddy
    forgejo/           Forgejo server, cozybox themes, mirror manifest, Actions runner
inventory/
  default.nix          Typed host inventory via evalModules
  schema.nix           Host record schema
  nodes/               Per-host records (macbook, spark)
terraform/
  cloudflare/          Declarative Cloudflare DNS for harivan.sh via terranix
scripts/
  default.nix          Full script set for user profiles (portable + theme, wallpaper-gen)
  portable.nix         Home-independent scripts (mux, ga, ghpr, iosrun, remote connectors)
  bin/                 Script sources wired by default.nix
  lib/                 Helpers (wallpaper-gen.py)
  forgejo-mirror/      Mirror reconciliation against /etc/forgejo-mirror/manifest.json (run on demand)
users/
  default.nix          User registry
  rathi.nix            SSH keys + groups for rathi
  barrett.nix          SSH keys + groups for barrett
dots/                  Dotfile sources (nvim, karabiner, lazygit, claude commands, etc.)
```

## Theme system

The "cozybox" theme has dark and light variants defined in `lib/theme.nix`. A runtime state file at `~/.local/state/theme/current` holds `dark` or `light`. The `theme` script (from `scripts/bin/theme.sh`) switches mode by updating symlinks for fzf, ghostty, lazygit, and the wallpaper, then pokes live nvim servers. Shell hooks in `dots/zsh/zshrc` re-apply prompt colors, zsh syntax highlights, and bat theme on every `precmd`.

Accent constraint for agent-facing TUI roles (omp markdown headings/inline code/links): no yellow, green, or pink hues. Stay in the neutral-bright / Claude-coral (`#d97757` dark, `#af3a03` light) / muted-blue (`#5b84de` dark, `#4261a5` light) lane. Status colors (success/error/warning, diffs) keep their conventional hues.

## omp extensions

`dots/omp/extensions/` holds omp extension entries; each entry file is symlinked individually into `~/.omp/agent/extensions/` by the activation script. The `diffs/` package (diffs.nvim-style edit diffs) splits into the discovered entry (`diffs/diffs.ts`) and lazy business logic (`diffs/core/`): value-importing `@oh-my-pi/pi-coding-agent` during omp's loadExtensions triggers the bundled-registry cascade and costs ~850ms of every startup, so the entry defers it to `session_start` via a relative dynamic import that omp's permanent extension-graph hook rewrites at import time. Never symlink `diffs/core/` files into `~/.omp/agent/extensions/` - discovery would load them eagerly and put the cost back on startup. Edits to `core/` files need an omp restart; the entry's `?mtime` cache-buster does not reach runtime imports.

`claude-purple/` follows the same entry + lazy `core/` split. Tool-call headings use the separate `toolTitle` token (claude-purple); `accent` stays coral for header descriptions, paths, and grep's per-file result headers. The extension patches the Theme prototype (and `DEFAULT_SHIMMER_PALETTE`) so the tool dots, the search dots, and the loader spinner/shimmer crest also render claude-purple, read live from `getColorHex("statusLinePath")` (the prompting-bar path shares that lane in `lib/theme.nix`).

## Remote sessions (mux)

tmux is gone. Its three jobs (persistence, panes/windows, session switching) live in Neovim: `scripts/bin/mux.sh` packages the `mux` command, which runs one detached `nvim --headless --listen <socket>` server per project (git/jj root) and attaches thin `nvim --remote-ui` clients to it. The in-editor layer is `dots/nvim/lua/mux/` (activated only when the launcher sets `MUX=1`): tagged view tabpages (edit/vcs/ai/zsh; ai runs `omp`), untagged tabs as plain tmux-style windows (auto-renamed to the shell's live cwd basename via OSC 7 emitted from zshrc), a tabline status bar (visible by default; `<c-b>\` toggles it), mksession snapshots (5-minute autosave + save-on-exit, restored on next start), and `:connect`-based project switching. Bindings mirror the old tmux config: `<c-b>` prefix, `h/j/k/l` panes, `-`/`'` splits, `c` new window, `x` kill pane, `z` zoom pane, `[` copy mode (terminal normal mode; `<Esc>` is never mapped and always reaches the program, `G` jumps to the tail and resumes typing), `n`/`p` window cycle, `y` last buffer, `H/J/K/L` session cycling, `f` project picker, `d` detach, `\` toggle tab bar. `mux stop` keeps a session resumable; `mux kill` deletes it; `mux restore` revives marked sessions after a reboot. Servers on spark need `users.users.<name>.linger = true` so they survive logout.

The portable scripts (`mux`, `ga`, `ghpr`, `iosrun`, the remote connectors) build without a home directory (`scripts/portable.nix`) and are exposed as flake `packages`, so hosts not managed by this flake install mux directly: `nix profile add git+https://git.harivan.sh/harivansh-afk/nix#mux` (or reference `packages.<system>.mux` from a consuming flake). Never shim `scripts/bin/mux.sh` into `~/.local/bin` by hand: the raw file has no shebang and none of its runtime dependencies; only the wrapped package works.

`lib/remotes.nix` maps a command name to `{ host }` per server. `scripts/default.nix` renders each entry into a connector command (via `scripts/bin/remote.sh`) that lands in every user's profile: `spark`, `macbook`, or `hari1` runs `mosh <host> -- mux`; an optional project arg (`spark ix`) is forwarded and resolved on the remote against its `mux list` (live/stopped sessions + zoxide dirs), jumping straight into that project's session; `--ssh` forces `ssh -t` for UDP-hostile networks. The same catalog is baked into the `mux` package for `mux list --all` and the in-nvim `<c-b>F` federated picker (local rows use `:connect`; remote rows write a hop file and detach so the client shell execs the connector). Bare `ssh <host>` / `mosh <host>` from zsh also auto-run the remote `mux`. Transport config (hostnames, keys, ControlMaster) stays in the live-edited `dots/ssh/config`; scp and git are never wrapped. To add a server: one entry in `lib/remotes.nix` plus its `Host` block in `dots/ssh/config`.

## Key dependencies

- `nixpkgs-nushell`: Separate nixpkgs pin for nushell on darwin (avoids EPERM test failures in the darwin sandbox without invalidating the spark NVIDIA kernel hash).
- `dgx-spark`: Upstream NixOS module for DGX Spark hardware. Do not set `inputs.nixpkgs.follows` - the upstream pins nixpkgs to a known-good revision for the NVIDIA kernel build.
- `determinate`: Manages the Nix installation, daemon, and `/etc/nix/nix.conf`. On darwin, use `determinateNix.customSettings` instead of `nix.settings`.
- `neovim-nightly`: Overlay applied only on darwin (no aarch64-linux binary cache).

## Adding a new service on spark

1. Create `modules/services/<name>.nix`.
2. Add the sops secret: create `secrets/hosts/spark/<name>.env`, encrypt with `just sops-edit`, and register it in `secrets/registry.nix`.
3. Use `loopbackVhost` from caddy.nix: `services.caddy.virtualHosts."http://<domain>" = loopbackVhost <port>;`.
4. Import the new module in `hosts/spark/default.nix`.
5. Add the DNS record in Cloudflare pointing to the tunnel.

## Adding a new user on spark

1. Create `users/<name>.nix` with `sshKeys`, `shell`, and `extraGroups`.
2. The user is automatically picked up by `hosts/spark/users.nix` (account) and `modules/users/nixos.nix` (dotfiles, packages; symlinks point at the nix-store copy of `dots/`).
3. For user-specific system config (services, slices), add a module under `hosts/spark/<name>/` and import it from `hosts/spark/default.nix`.

## Forgejo mirroring

The legacy gitea-mirror Bun service has been removed. Forgejo's native mirror tables (`mirror` for inbound pulls, `push_mirror` for outbound pushes) are the source of truth. Two files drive the system:

- `modules/services/forgejo/mirror-manifest.nix`: policy-only config (intervals, `owned_owner`, the small `no_mirror` set, the `actions_enabled_repos` allowlist). No repo inventory is checked into nix; the actual list of repos to mirror is discovered at runtime by querying forgejo's own database. Rendered to `/etc/forgejo-mirror/manifest.json` at activation.
- `scripts/forgejo-mirror/reconcile.sh`: idempotent script that reads the manifest, deletes pull-mirror rows on push-mirror targets, creates missing push-mirrors with `use_ssh=true sync_on_commit=true interval=15m`, registers the forgejo-generated public key as a github deploy key, and flips `has_actions` per the allowlist. Run as root: `sudo FORGEJO_MIRROR_MANIFEST=/etc/forgejo-mirror/manifest.json bash scripts/forgejo-mirror/reconcile.sh [--dry-run]`.
- `scripts/forgejo-mirror/github-ux.sh`: optional, applies the barrettruth full treatment (github description/homepage/has_* metadata, `.github/README.md` banner, redirect-pr workflow) to every push-mirror. Run on demand: `bash scripts/forgejo-mirror/github-ux.sh [--dry-run] [--only owner/name]`.

Forgejo's own `[mirror] DEFAULT_INTERVAL` is `15m` and `[queue.mirror] MAX_WORKERS` is capped at `1`. The pre-start hook in `modules/services/forgejo/default.nix` uniformly jitters every pull-mirror's `next_update_unix` to `now + (repo_id % 900s)` on each forgejo start, so 100+ mirrors never bunch into a single hour the way they did under the old gitea-mirror scheduler.
