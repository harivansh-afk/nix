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

Services: Forgejo (`git.harivan.sh`), Vaultwarden (`vault.harivan.sh`).

### Secrets

sops-nix with age encryption derived from each host's ed25519 SSH key. Secret files live under `secrets/hosts/<hostname>/` (plus per-admin secrets under `secrets/user/`). Edit with `just sops-edit secrets/hosts/spark/<file>`.

`.sops.yaml` recipient anchors are derived via `ssh-to-age`:

- `admin_macbook` — Hari's macbook SSH pubkey, edits everything.
- `host_spark` — Spark's `/etc/ssh/ssh_host_ed25519_key.pub`, decrypts at activation.

`secrets/hosts/spark/[^/]+$` encrypts secrets for `admin_macbook` and `host_spark`.

## Conventions

- No comments in `.nix` files. The code is the documentation. Agent guidance lives here.
- Use `just switch` for macbook rebuilds, `just switch-spark` for spark rebuilds.
- `just fmt` runs `nix fmt` (nixfmt-tree).
- Pull requests for this repo go to Forgejo (`origin`, git.harivan.sh), never GitHub. The `github` remote is a push-mirror target only; its redirect-pr workflow auto-closes PRs opened there. Create PRs with `tea pr create --login harivan --repo harivansh-afk/nix --base main --head <branch>`.
- For multiline PR bodies, pass a real file's contents to `tea pr create --description` (or `gh --body-file -` when working on actual GitHub repos). Do not pass escaped `\\n` text; it renders as literal backslash-n. After creating or editing a PR, verify the rendered body before calling it done.
- Install spark from scratch with `just spark-install user@host`.
- Prefer common package definitions across macbook and spark; keep only truly macOS-specific Homebrew and GUI integrations Darwin-only.
- Cursor CLI and `cursor-agent` come from the official installer: `curl https://cursor.com/install -fsS | bash`.
- Bugfix PRs keep the diff minimal and exclude unrelated changes.
- Berkeley Mono is installed out-of-band. The flake only provides nerd-fonts symbol glyphs.
- There is no home-manager. Per-user config is `modules/users/user-config.nix`: plain dotfiles in `dots/` symlinked into the home directory by an activation script that runs as the user. The repo owner's links point at the live checkout (`~/Documents/Git/nix/dots`), so dotfile edits apply without a rebuild; other users get the nix-store copy. Configs that need store paths (zsh plugins, git credential helpers, theme renders) are store-generated shims that defer to the live dots file.
- Ghostty is installed via Homebrew cask, not nixpkgs. The flake owns its config files and its terminfo: `xterm-ghostty` is declarative in `modules/common.nix` (`pkgs.ghostty-bin.terminfo` on darwin, `pkgs.ghostty.terminfo` on linux) so env-scrubbed shells resolve it without `TERMINFO`. Never fix terminfo imperatively via `tic` into `~/.terminfo`.
- Neovim treesitter is nix-delivered: `lib/nvim-pack.nix` builds the nvim-treesitter plugin plus grammar+query envs from the nixpkgs `vimPlugins.nvim-treesitter-parsers` set (one pin, so a parser and its queries never drift apart), and user activation symlinks them at `~/.local/share/nvim/site/` (`pack/nix/start/nvim-treesitter`, `parser`, `queries`). Workstations get every grammar (`treesitter.full`); the ix VM gets the curated list. vim.pack never manages nvim-treesitter — activation clears a stale pack copy on every switch — and runtime parser installs are dead paths: `auto_install` is a master-branch option the main rewrite ignores silently, which is how the setup ran regex highlighting for months without an error.
- Karabiner config is a directory symlink to `dots/karabiner/` so Karabiner can write freely.
- Cursor-agent, Claude, and Codex are curl-installed binaries. On NixOS they need nix-ld.
- Devin config is seeded as a mutable copy since Devin rewrites it.

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
| `coding.md` | Claude Code, Codex, omp | tooling, git conventions, the `unslop` skill, spark CLI tools |
| `claude.md` | Claude Code | Claude-only steering (prose questions, outcome-first replies, delegation) |

Rendered outputs: `~/.claude/CLAUDE.md` (core + coding + claude), `~/.codex/AGENTS.md` (core + coding). A fact that is true for two parts moves up to `core.md`; a repo-specific fact belongs in that repo's `AGENTS.md` (this file), which `CLAUDE.md` imports with `@AGENTS.md`.

Skills come from the `mattpocock-skills` flake input. `modules/users/user-config/agents.nix` builds the selected skills into one link farm and the activation script links it to `~/.agents/skills` (Codex, and anything agentskills.io-compatible) and `~/.claude/skills` (Claude Code). Upgrade them with `nix flake update mattpocock-skills`.

## Module layout

```
flake.nix              Inputs + flake-parts structure
flake/
  args.nix             Host records (the two machines) + shared builders (mkPkgs, mkSpecialArgs)
  devshell.nix         Dev tools + formatter
  hosts.nix            macbook darwin configuration
  nixos.nix            spark NixOS configuration + nixosConfigurations.ix (the dev VM template)
  packages.nix         packages.<system> output: portable scripts (ga, ghpr, connectors) + tool wrappers
lib/
  remotes.nix          Remote server registry: hosts for the per-remote connector commands
  theme.nix            Cozybox theme: colors, renderers for ghostty/fzf/lazygit/pure-prompt/bat/zsh-highlights
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
    mux/               Mux.app built from source at activation (default.nix + build.sh + Info.plist)
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
      hermes.nix       Hermes agent gateway + dashboard
      inference.nix    Local llama.cpp inference server (GPU)
      mosh.nix         Mosh UDP server config
      vaultwarden.nix  Vaultwarden password manager
      website.nix      harivan.sh static site + page counter (counter code lives in the website repo, counter/counter.py)
      kb/              Knowledge base: postgres + pgvector, embedding server, connectors/*.sh, kb_vec.py indexer, kb-search
      whisper/         GPU speech-to-text server (default.nix + setup.sh + server.py)
      forgejo/         Forgejo server, cozybox css in assets/, mirror manifest, Actions runner, run-by-hand scripts/
  ix/
    default.nix        The entire ix dev VM: root dotfiles, agents, nothing else
pkgs/
  sets.nix             Shared package sets (core, extras, darwinExtras, fonts) for modules/common.nix
  jj-ix/               Patched jj with the ix store backend
  scripts/
    default.nix        Full script set for user profiles (portable + theme, wallpaper-gen)
    portable.nix       Home-independent scripts (ga, ghpr, iosrun, remote connectors)
    bin/               Script sources wired by default.nix
    lib/               Helpers (wallpaper-gen.py)
terraform/
  cloudflare/          Declarative Cloudflare DNS for harivan.sh via terranix
scripts/               Repo tooling: pr-smoke.sh, nvim-pack-sources.sh
assets/                Readme artwork + the static wallpapers
dots/                  Dotfile sources (nvim, karabiner, lazygit, agents/ instructions + skills, etc.)
```

## Theme system

The "cozybox" theme has dark and light variants defined in `lib/theme.nix`. A runtime state file at `~/.local/state/theme/current` holds `dark` or `light`. The `theme` script (from `pkgs/scripts/bin/theme.sh`) switches mode by updating symlinks for fzf, ghostty, lazygit, and the wallpaper, then pokes live nvim servers. Shell hooks in `dots/zsh/zshrc` re-apply prompt colors, zsh syntax highlights, and bat theme on every `precmd`.

Accent constraint for agent-facing TUI roles (omp markdown headings/inline code/links): no yellow, green, or pink hues. Stay in the neutral-bright / Claude-coral (`#d97757` dark, `#af3a03` light) / muted-blue (`#5b84de` dark, `#4261a5` light) lane. Status colors (success/error/warning, diffs) keep their conventional hues.


## omp

omp runs stock upstream: no extensions and no hooks, by policy. The extension monkey-patches (diffs.nvim-style edit rendering, purple tool dots, the /mode command, the Claude agent-def bridge) were removed in #535 after auditing 18.0.11 - do not re-add them by reflex; if upstream grows a native knob for one of these, use the knob. The activation script clears any symlink from `~/.omp/agent/extensions/` on every switch, so a stray extension link does not quietly resurrect the pattern. No agent harness has hooks configured, and none should be created.

Nix seeds omp from `modules/users/user-config/agents.nix`: the cozybox theme JSONs, `models.yml` (the spark-local llama.cpp provider), `mcp.json` (the index MCP server, spark only), `config.yml` (xattr-tracked reseed - omp rewrites it at runtime, so it is a writable copy, not a symlink), and `local.yml`, a session overlay that puts both model roles on local Qwen: `omp --config ~/.omp/agent/local.yml`.

`config.yml`'s `setupVersion` must track upstream's `CURRENT_SETUP_VERSION`: omp's cold-launch gate eagerly imports the whole setup-wizard barrel whenever the stored version is lower, before `startup.setupWizard` is consulted, so a stale pin taxes every launch. Check the constant in `src/modes/setup-version.ts` when bumping omp majors.

## Remote sessions

Terminal sessions, panes, and persistence are the job of Mux.app and muxd (`~/Documents/Git/mux`); spark runs the daemon via `hosts/spark/services/muxd.nix`. Nothing in this repo multiplexes terminals.

The portable scripts (`ga`, `ghpr`, `iosrun`, the remote connectors) build without a home directory (`pkgs/scripts/portable.nix`) and are exposed as flake `packages`, so hosts not managed by this flake can install them with `nix profile add git+https://git.harivan.sh/harivansh-afk/nix#<name>`.

`lib/remotes.nix` maps a command name to the remote hostname. `pkgs/scripts/portable.nix` renders each entry into a connector command (via `pkgs/scripts/bin/remote.sh`) that lands in every user's profile: `spark`, `macbook`, or `dev6` opens a shell over `mosh <host>`; `--ssh` forces `ssh -t` for UDP-hostile networks. Transport config (hostnames, keys, ControlMaster) stays in the live-edited `dots/ssh/config`; ssh, scp, and git are never wrapped. To add a server: one entry in `lib/remotes.nix` plus its `Host` block in `dots/ssh/config`.

## Key dependencies

- `nixpkgs-nushell`: Separate nixpkgs pin for nushell on darwin (avoids EPERM test failures in the darwin sandbox without invalidating the spark NVIDIA kernel hash).
- `dgx-spark`: Upstream NixOS module for DGX Spark hardware. Do not set `inputs.nixpkgs.follows` - the upstream pins nixpkgs to a known-good revision for the NVIDIA kernel build. It also makes podman the machine's only container runtime and serves the Docker-compatible API at `/run/podman/podman.sock` (`dockerCompat`, `dockerSocket.enable`, socket group `podman`); anything speaking the Docker API (dockerode, docker CLI) uses that socket. Never set `virtualisation.docker.enable` - it conflicts with the podman socket, and enabling it rewired the CI runner's unit and aborted the #479 deploy mid-switch.
- `determinate`: Manages the Nix installation, daemon, and `/etc/nix/nix.conf`. On darwin, use `determinateNix.customSettings` instead of `nix.settings`.
- `neovim-nightly`: Overlay applied only on darwin (no aarch64-linux binary cache).

## Adding a new service on spark

1. Create `hosts/spark/services/<name>.nix`.
2. Add the sops secret: create `secrets/hosts/spark/<name>.env`, encrypt with `just sops-edit`, and register it in `secrets/registry.nix`.
3. Use `loopbackVhost` from caddy.nix: `services.caddy.virtualHosts."http://<domain>" = loopbackVhost <port>;`.
4. Import the new module in `hosts/spark/default.nix`.
5. Add the DNS record in Cloudflare pointing to the tunnel.

## Adding a new user on spark

1. Create `users/<name>.nix` with `sshKeys`, `shell`, and `extraGroups`.
2. The user is automatically picked up by `hosts/spark/users.nix` (account) and `modules/users/nixos.nix` (dotfiles, packages; symlinks point at the nix-store copy of `dots/`).
3. For user-specific system config (services, slices), add a module under `hosts/spark/<name>/` and import it from `hosts/spark/default.nix`.

## ix dev VM template

`ix new github:harivansh-afk/nix#ix` boots `nixosConfigurations.ix` as a throwaway x86_64-linux VM. `hosts/ix/default.nix` is the whole VM and imports nothing from `hosts/spark/`. It lists `users.users.root.packages` literally instead of taking `mkUserConfig`'s set, and uses `mkUserConfig` only for the dotfile activation script over `dots/` (plus `nvimAliases`). To add or remove something from the VM, edit that one list. `installMutableTools = false` suppresses the curl installs of omp and cursor-agent, which have no place in a cached image.

The literal list exists because the VM builds inside itself on 2 vCPU / 1 GiB, so every uncached derivation is compiled on the smallest machine ix hands out and there is no build timeout to stop it. `mkUserConfig`'s workstation set costs 1253 source builds and 8.6 GiB unpacked; this list costs 58 and 1.7 GiB, and the 58 are all rendered config files plus omp, claude-code and NixOS plumbing. Anything added here is paid for on every cold template build, so weigh it against that. Measure a candidate before adding it:

```
nix eval .#nixosConfigurations.ix.config.system.build.toplevel.drvPath
nix build --dry-run <drv>^* --substituters https://cache.nixos.org
```

What was deliberately left out, and why, so it does not get re-added by reflex: `elixir_1_19` + `elixir-ls` (erlang twice, 248 MiB, and erlang's wx support drags in wxwidgets then webkitgtk), `clang` + `clang-tools` (1.4 GiB of clang and llvm libs), `pyright` + `python3` (389 MiB), `go_1_26` + `gopls` (248 MiB), `k9s` (168 MiB, no cluster to point it at), `tea` (its logins come from sops, which the VM has none of), and every `customScripts` entry (the remote connectors dial hosts a throwaway VM cannot reach, and `wallpaper-gen` pulls python + pillow for a machine with no display). `zoxide` is in the list because `dots/zsh/zshrc` runs `zoxide init zsh` unconditionally.

`environment.systemPackages` holds one entry, `pkgs.ghostty.terminfo`, and it has to be there rather than in the root package list: NixOS builds `TERMINFO_DIRS` from `environment.pathsToLink`, which only covers the system profile. Ghostty exports `TERM=xterm-ghostty`, `ix shell` carries that value into the guest, and a guest with no matching terminfo entry gives you `can't find terminal definition for xterm-ghostty`, a zsh line editor that cannot position the cursor (keystrokes echo doubled) and a `clear` that refuses to run. The cost is 2.2 KiB: `terminfo` is a separate output of the ghostty derivation and cache.nixos.org has it, so nothing builds ghostty itself. Any other terminal that sets an exotic `TERM` needs its own entry here, or `environment.enableAllTerminfo = true` if the list ever grows past a couple.

Neovim plugins and treesitter parsers are materialised into the image because they cannot arrive any other way. `ix-closure-manifest assemble-closure` chunks only the store paths of the system closure plus a bare FHS skeleton, `/root` ships empty, and activation runs *after* the image is published, so anything `vim.pack` clones into `/root/.local/share/nvim/` at runtime is outside the image and re-downloaded by every VM. `lib/nvim-pack.nix` turns `dots/nvim/pack-sources.json` into one `fetchgit` per plugin; the `nvimPack` activation script copies plugins into `site/pack/core/opt/`. Treesitter (plugin, curated grammars, matched queries) arrives through the shared user activation (see Conventions), pinned to `parserNames`; its payload is ~14 MiB (plugin 2.1 MiB self plus ~12 MiB grammars+queries, measured with `nix path-info -S`; the rest of the closure is coreutils/bash the base system already carries).

Two behaviours of `vim.pack` are load-bearing here, both verified against a live VM rather than assumed. It accepts a plain writable directory and leaves it alone, so plugins ship without `.git` and at half the size. It deletes anything read-only or symlinked at the plugin path and re-clones it, logging `Removed corrupted lock data`, so the activation script must `cp -r` and `chmod -R u+w` rather than symlink — which is also why nvim-treesitter lives in `pack/nix/start/`, outside vim.pack's `pack/core/opt/`, where a store symlink survives.

`dots/nvim/pack-sources.json` is generated, committed, and the only plugin list nix can see. It cannot read `nvim-pack-lock.json`: that file is gitignored (`dots/nvim/.gitignore:14`), so it is absent from the flake source and never reaches a VM, and `vim.pack` rewrites it destructively anyway (a VM booted before this change had a lock containing one plugin, because only the eagerly-loaded `plugin/git.lua` had registered by the time it was written). After bumping plugins, run `just nvim-pack-sources`, which reads your local lock and re-prefetches every hash. Skipping that step leaves the VM on the old revisions with no error, because nothing else reads the lock.

`parserNames` in `lib/nvim-pack.nix` is the ix VM's curated grammar list; workstations take every grammar instead. It deliberately omits `c`, `lua`, `query`, `vim` and `vimdoc`: neovim already ships those in `${pkgs.neovim-unwrapped}/lib/nvim/parser`, listing them again would pay for them twice, and the pin's queries run fine against the bundled parsers (verified headless on 0.12.3).

`IS_SANDBOX = "1"` is what lets Claude Code run as root. Without it `claude` refuses with `--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons`; with it the same invocation reaches `Not logged in`. `ix shell` has no `--user` flag and always lands you as root, so the alternative would be adding a non-root account purely to satisfy that check.

Constraints that shaped it, all of them load-bearing:

- **`nixosConfigurations.ix`, not `ix.default`.** `ix new` first probes `ix.<attr>` and, only if that misses, builds `nixosConfigurations.<attr>.extendModules` with ix's machine profile. The probe has a hard 300s cap and must evaluate the full toplevel, which this flake's ~20 inputs cannot do cold. Exposing no `ix` output at all makes the probe miss in seconds on a missing attribute and puts the build on the `extendModules` path, which has no such timer.
- **No `index.lib.mkDev`.** It returns a fleet result whose nodes are `{ config = ...; }` with no `extendModules`, so `ix new` cannot wrap it. Dropping it also drops an import-from-derivation (`cargo-units.nix`) that made the config impossible to evaluate on aarch64. It now evaluates locally: `nix eval .#nixosConfigurations.ix.config.system.build.toplevel.drvPath`.
- **`boot.isContainer = true`.** ix owns the kernel, root device and console; the machine profile force-sets this in-guest. Setting it here too (same value, no conflict) is what lets the config evaluate standalone without a bootloader or `fileSystems."/"`.
- **`#spark` is not bootable.** Wrong architecture (aarch64 vs x86_64 guests), the dgx-spark NVIDIA module, and disko's `fileSystems` by UUID, which hangs boot in systemd device timeouts. Keep the two configs separate.

`ix new` resolves `github:`, `gitlab:` and `sourcehut:` only, never `git+https://git.harivan.sh/...`, so it builds the GitHub push mirror and not `origin`. Push the mirror before booting, or pin the sha (`ix new github:harivansh-afk/nix/<sha>#ix`), or you will silently get an older tree.

The VM has no secrets. sops-nix on spark derives its age key from the host ed25519 key, which a fresh VM cannot have, and a template image is cached per rev and shared, so nothing secret may enter the closure. Delivering sops here means minting a separate age identity, storing the private key with `ix secret set`, and attaching it at create time with `ix new --secret-file`. Not done yet.

## CI deploys

`deploy.yml` runs `nixos-rebuild switch` on spark's own Actions runner, so the switch must never restart that runner: `gitea-runner-spark.service` is pinned `restartIfChanged = false` in `hosts/spark/services/forgejo/default.nix`. Without it, any config change that touches the runner unit (enabling docker did, via the gitea-actions-runner module's docker-label wiring) makes activation restart the runner mid-deploy; the runner's `shutdown_timeout=0s` kills its own jobs, including the nixos-rebuild driving the switch, and `switch-to-configuration` dies with its pty, leaving the system half-switched (the #479 deploy stopped postgresql and the runner this way and restarted neither). The cost: a changed runner unit lands on disk at switch but only applies on the next manual `systemctl restart gitea-runner-spark` or reboot. A cancelled sibling job on the same runner reads as a spurious failure (that is what "quality / Nix Format Check: failing after 0s" was), so check the runner journal before trusting a red X that raced a deploy.

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

## indexable-inc/ix mirroring

Source of truth is the jj-native ix forge (RPC `https://forge.ix.dev:8447/rpc`, UI `https://forge.ix.dev:8448/`, tailnet), not GitHub: github.com/indexable-inc/ix is archived and is never synced from. Clone with `jj-ix ix clone --server https://forge.ix.dev:8447/rpc --repo ix <dir>` and pass `--config 'signing.behavior=drop'` (the ix backend rejects commit signing). The forge has no whole-repo git egress, so `git.harivan.sh/indexable-inc/ix` is a regular repo kept current by pushing snapshot commits of forge `main` (tree from a jj-ix clone, parent = previous snapshot, message carries the forge commit id).

## Hermes

Hermes runs through upstream's NixOS module in `hosts/spark/services/hermes.nix`.
The gateway and dashboard share `~/.local/state/hermes/.hermes`; the `~/.hermes`
symlink keeps existing CLI state reachable. Astra uses Codex OAuth at medium
reasoning. Native browser, CUA, delegation, memory and skills are enabled for CLI
and Photon iMessage. The knowledge-base plugin remains read-only.

Chromium's existing Default profile is private mutable state; Hermes uses its
native snapshot feature. Never commit browser profiles or put their credentials
in the store. For browser identity, Sway/CUA diagnostics, Photon recovery or
post-deployment acceptance, read `hosts/spark/docs/hermes.md`.

Nix owns runtimes, settings and the assistant guidance in `dots/hermes/`. Memory,
learned skills and conversation state persist across rebuilds. Scheduled work is
created only on request; the old scanners, graph and automatic loops remain absent.
