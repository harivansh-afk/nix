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
- The `tmp/` directory is gitignored local scratch space. Nothing there is tracked or load-bearing.
- Berkeley Mono is installed out-of-band. The flake only provides nerd-fonts symbol glyphs.
- There is no home-manager. Per-user config is `modules/users/user-config.nix`: plain dotfiles in `dots/` symlinked into the home directory by an activation script that runs as the user. The repo owner's links point at the live checkout (`~/Documents/Git/nix/dots`), so dotfile edits apply without a rebuild; other users get the nix-store copy. Configs that need store paths (zsh plugins, git credential helpers, theme renders) are store-generated shims that defer to the live dots file.
- Ghostty is installed via Homebrew cask, not nixpkgs. The flake owns its config files and its terminfo: `xterm-ghostty` is declarative in `system/common.nix` (`pkgs.ghostty-bin.terminfo` on darwin, `pkgs.ghostty.terminfo` on linux) so env-scrubbed shells resolve it without `TERMINFO`. Never fix terminfo imperatively via `tic` into `~/.terminfo`.
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
| `hermes.md` | Hermes | the concierge role, loops, model, native KB tools |

Rendered outputs: `~/.claude/CLAUDE.md` (core + coding + claude), `~/.codex/AGENTS.md` (core + coding), `~/.hermes/AGENTS.md` (core + hermes). A fact that is true for two parts moves up to `core.md`; a repo-specific fact belongs in that repo's `AGENTS.md` (this file), which `CLAUDE.md` imports with `@AGENTS.md`.

Skills: `dots/agents/skills/<name>/SKILL.md` are repo-owned (`unslop`); the `mattpocock-skills` flake input supplies the engineering and productivity buckets. `modules/users/user-config/agents.nix` builds one link farm from both and the activation script links it to `~/.agents/skills` (Codex, and anything agentskills.io-compatible) and `~/.claude/skills` (Claude Code). Add a skill by dropping a directory into `dots/agents/skills/`; upgrade upstream with `nix flake update mattpocock-skills`. Hermes keeps its own skills under `dots/hermes/skills/`.

Hooks live in `dots/claude/hooks/` and are registered in `agents.nix`; omp reuses them through `dots/omp/extensions/claude-hooks.ts`.

## Module layout

```
flake.nix              Inputs + flake-parts structure
flake/
  args.nix             Shared args: host records, builders
  devshell.nix         Dev tools + formatter
  hosts.nix            macbook darwin configuration
  nixos.nix            spark NixOS configuration
  ix.nix               nixosConfigurations.ix: the ix dev VM template
  scripts.nix          packages.<system> output: portable scripts (ga, ghpr, connectors)
lib/
  remotes.nix          Remote server registry: hosts for the per-remote connector commands
  theme.nix            Cozybox theme: colors, renderers for ghostty/fzf/lazygit/pure-prompt/bat/zsh-highlights
system/
  common.nix           Shared nix settings, overlays, base packages
  packages.nix         Extra packages + fonts
hosts/
  macbook/
    default.nix        Facts + imports only (hostname, user, stateVersion)
    apps.nix           GUI apps nix launches at login (apps with their own launch-at-login are NOT duplicated here)
    defaults.nix       System defaults (dock, finder, keyboard, screenshots, loginwindow)
    homebrew.nix       Taps, formulae, casks (every cask on the machine is declared)
    services.nix       Every launchd unit (aerospace, sketchybar, limit.maxfiles); the only service manager
    startup-guard.nix  Enforces login-item allowlist, warns on undeclared launchd plists (daily + login + switch)
  spark/
    default.nix        Base NixOS config, nix-ld, kernel hardening
    hardware.nix       DGX Spark module + disko disk layout
    networking.nix     Wi-Fi (NetworkManager), Tailscale, firewall, zram
    users.nix          User accounts from users/ directory, SSH, sudo
  ix/
    default.nix        The entire ix dev VM: root dotfiles, agents, nothing else
modules/
  users/
    user-config.nix    Shared per-user dotfile/symlink/package builder (no home-manager)
    nixos.nix          NixOS adapter: every user in users/, owner gets live dots
    darwin.nix         nix-darwin adapter: primary user, live dots
  security/
    sops.nix           sops-nix setup, age key from SSH host key
  services/
    caddy.nix          Reverse proxy on loopback, loopbackVhost helper
    cloudflared.nix    Cloudflare tunnel to Caddy
    delta.nix          Delta todo app service
    inference.nix      Local llama.cpp inference server (GPU)
    mosh.nix           Mosh UDP server config
    whisper.nix        GPU speech-to-text server
    vaultwarden.nix    Vaultwarden password manager
    website.nix        Static site for harivan.sh served via Caddy
    forgejo/           Forgejo server, cozybox themes, mirror manifest, Actions runner
inventory/
  default.nix          Typed host inventory via evalModules
  schema.nix           Host record schema
  nodes/               Per-host records (macbook, spark)
pkgs/
  leaf/                leaf (terminal markdown viewer) built from the pinned upstream tag
terraform/
  cloudflare/          Declarative Cloudflare DNS for harivan.sh via terranix
scripts/
  default.nix          Full script set for user profiles (portable + theme, wallpaper-gen)
  portable.nix         Home-independent scripts (ga, ghpr, iosrun, remote connectors)
  bin/                 Script sources wired by default.nix
  lib/                 Helpers (wallpaper-gen.py)
  forgejo-mirror/      Mirror reconciliation against /etc/forgejo-mirror/manifest.json (run on demand)
users/
  default.nix          User registry
  rathi.nix            SSH keys + groups for rathi
dots/                  Dotfile sources (nvim, karabiner, lazygit, agents/ instructions + skills, etc.)
```

## Theme system

The "cozybox" theme has dark and light variants defined in `lib/theme.nix`. A runtime state file at `~/.local/state/theme/current` holds `dark` or `light`. The `theme` script (from `scripts/bin/theme.sh`) switches mode by updating symlinks for fzf, ghostty, lazygit, leaf, and the wallpaper, then pokes live nvim servers. Shell hooks in `dots/zsh/zshrc` re-apply prompt colors, zsh syntax highlights, and bat theme on every `precmd`.

Accent constraint for agent-facing TUI roles (omp markdown headings/inline code/links): no yellow, green, or pink hues. Stay in the neutral-bright / Claude-coral (`#d97757` dark, `#af3a03` light) / muted-blue (`#5b84de` dark, `#4261a5` light) lane. Status colors (success/error/warning, diffs) keep their conventional hues.

`renderLeaf` writes leaf's custom-theme TOML (every `[ui]` + `[markdown]` key upstream defines, checked against `src/theme/serde.rs`; unknown keys are silently ignored by leaf, so the set must stay exhaustive). Surfaces are `"reset"` (ratatui `Color::Reset`, i.e. the terminal's own background) so leaf paints text only; the only painted regions are the TOC selection and the search highlights. leaf deliberately departs from the omp accent lane above: it is a document reader, not an agent surface, so hue carries the heading hierarchy. H1 is yellow (`#fabd2f` dark, `#b57614` light) as the single "top of document" accent, H2 is blue, H3/H4 fall back to the neutral ramp, and coral is reserved for inline code alone. That blue is gruvbox's desaturated `#83a598` (`#076678` light), never the saturated omp link blue `#5b84de`: cozybox is a warm palette and a pure cool blue sits near coral's complement, so the two vibrate wherever a heading meets inline code. Code-block tokens are the one thing the palette cannot drive: leaf takes a syntect theme *name* from its 7 bundled themes, so dark uses `base16-mocha.dark` (warmest match) and light uses `InspiredGitHub`.

## omp extensions

`dots/omp/extensions/` holds omp extension entries; each entry file is symlinked individually into `~/.omp/agent/extensions/` by the activation script. The `diffs/` package (diffs.nvim-style edit diffs) splits into the discovered entry (`diffs/diffs.ts`) and lazy business logic (`diffs/core/`): value-importing `@oh-my-pi/pi-coding-agent` during omp's loadExtensions triggers the bundled-registry cascade and costs ~850ms of every startup, so the entry defers it to `session_start` via a relative dynamic import that omp's permanent extension-graph hook rewrites at import time. Never symlink `diffs/core/` files into `~/.omp/agent/extensions/` - discovery would load them eagerly and put the cost back on startup. Edits to `core/` files need an omp restart; the entry's `?mtime` cache-buster does not reach runtime imports.

`claude-purple/` follows the same entry + lazy `core/` split. Tool-call headings use the separate `toolTitle` token (claude-purple); `accent` stays coral for header descriptions, paths, and grep's per-file result headers. The extension patches the Theme prototype (and `DEFAULT_SHIMMER_PALETTE`) so the tool dots, the search dots, and the loader spinner/shimmer crest also render claude-purple, read live from `getColorHex("statusLinePath")` (the prompting-bar path shares that lane in `lib/theme.nix`).

## Remote sessions

Terminal sessions, panes, and persistence are the job of Mux.app and muxd (`~/Documents/Git/mux`); spark runs the daemon via `modules/services/muxd.nix`. Nothing in this repo multiplexes terminals.

The portable scripts (`ga`, `ghpr`, `iosrun`, the remote connectors) build without a home directory (`scripts/portable.nix`) and are exposed as flake `packages`, so hosts not managed by this flake can install them with `nix profile add git+https://git.harivan.sh/harivansh-afk/nix#<name>`.

`lib/remotes.nix` maps a command name to `{ host }` per server. `scripts/portable.nix` renders each entry into a connector command (via `scripts/bin/remote.sh`) that lands in every user's profile: `spark`, `macbook`, or `dev6` opens a shell over `mosh <host>`; `--ssh` forces `ssh -t` for UDP-hostile networks. Transport config (hostnames, keys, ControlMaster) stays in the live-edited `dots/ssh/config`; ssh, scp, and git are never wrapped. To add a server: one entry in `lib/remotes.nix` plus its `Host` block in `dots/ssh/config`.

## Hermes loops

`modules/services/hermes-loops.nix` deliberately forbids autonomous internet-to-agent paths. The old X, Hacker News, dependency-release, and ix morning-brief cron jobs are removed so untrusted network content cannot be injected into the privileged Hermes prompt. The deterministic scanner binaries remain inert local building blocks for a future quarantined ingestion pipeline; they are not scheduled and do not write to the KB.

Finance splits judgment off because the raw data is local-only: the gateway masks `/var/lib/kb/staging/finance` via `InaccessiblePaths`, and hermes' cron scheduler runs in the gateway process, so no cron job - whatever model it is pinned to - can read it. `finance-anomaly-judge.service` (daily timer, outside that sandbox, `IPAddressDeny=any` + `IPAddressAllow=localhost` so it provably cannot exfiltrate) runs the scanner and has the local qwen brain (`127.0.0.1:18080`, `qwen3.6-35b-a3b`) write a judged briefing into `staging/loops/finance-anomaly-watch/` - the brain annotates and ranks but never drops a candidate (an earlier LLM skeptic dropped legitimate subscriptions as "normal spending", which is the one failure mode this loop must not have). The `finance-anomaly-watch` cron job then relays new verdicts with the `finance-relay` skill: hermes sees only the local model's result, never the raw transactions, and the pings still come from the agent like everything else.

Job installation is declarative. `hermes-loops.nix` renders a manifest (jobs + script store paths); `hermes-cron-jobs.service` runs `dots/hermes/cron/reconcile.py` under hermes' own python env (`hermesVenv` passthru), driving hermes' `cron.jobs` module directly - create/update/remove with first-party locking, schedule parsing, and `next_run_at`; the gateway re-reads `jobs.json` every scheduler tick, so changes land without a restart. The reconciler owns only the names it installed (tracked in `~/.hermes/cron/.nix-managed.json`): jobs Hari creates via `/cron` in chat survive rebuilds, and a same-name pre-existing job is adopted. Scripts are copied (not symlinked) into `~/.hermes/scripts/` because hermes resolves script paths and rejects anything outside that directory. `deliver: "photon"` is resolved at reconcile time from `~/.hermes/channel_directory.json` to `photon:<chat_id>` (the id is a phone number; this repo is mirrored publicly), falling back to `local` with a warning until the first DM is seen.

Sandbox interplay to keep in mind: the finance relay executes inside `hermes-gateway.service`, while the local judge runs outside it with raw finance access, loopback-only networking, and no internet route. Inspect the job with `hermes cron list`; trigger the judge with `sudo systemctl start finance-anomaly-judge`.

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

## ix dev VM template

`ix new github:harivansh-afk/nix#ix` boots `nixosConfigurations.ix` as a throwaway x86_64-linux VM. `hosts/ix/default.nix` is the whole VM and imports nothing from `hosts/spark/`. It lists `users.users.root.packages` literally instead of taking `mkUserConfig`'s set, and uses `mkUserConfig` only for the dotfile activation script over `dots/` (plus `nvimAliases`). To add or remove something from the VM, edit that one list. `installMutableTools = false` suppresses the curl installs of omp and cursor-agent, which have no place in a cached image.

The literal list exists because the VM builds inside itself on 2 vCPU / 1 GiB, so every uncached derivation is compiled on the smallest machine ix hands out and there is no build timeout to stop it. `mkUserConfig`'s workstation set costs 1253 source builds and 8.6 GiB unpacked; this list costs 58 and 1.7 GiB, and the 58 are all rendered config files plus omp, claude-code and NixOS plumbing. Anything added here is paid for on every cold template build, so weigh it against that. Measure a candidate before adding it:

```
nix eval .#nixosConfigurations.ix.config.system.build.toplevel.drvPath
nix build --dry-run <drv>^* --substituters https://cache.nixos.org
```

What was deliberately left out, and why, so it does not get re-added by reflex: `hermes-agent` (1170 source builds on its own, an uncached uv2nix tree pulling ffmpeg, ctranslate2 and onnxruntime), `leaf` (builds from source, so the VM fetches 1.6 GiB of rustc to compile one markdown viewer), `elixir_1_19` + `elixir-ls` (erlang twice, 248 MiB, and erlang's wx support drags in wxwidgets then webkitgtk), `clang` + `clang-tools` (1.4 GiB of clang and llvm libs), `pyright` + `python3` (389 MiB), `go_1_26` + `gopls` (248 MiB), `k9s` (168 MiB, no cluster to point it at), `tea` (its logins come from sops, which the VM has none of), and every `customScripts` entry (the remote connectors dial hosts a throwaway VM cannot reach, and `wallpaper-gen` pulls python + pillow for a machine with no display). `zoxide` is in the list because `dots/zsh/zshrc` runs `zoxide init zsh` unconditionally.

`environment.systemPackages` holds one entry, `pkgs.ghostty.terminfo`, and it has to be there rather than in the root package list: NixOS builds `TERMINFO_DIRS` from `environment.pathsToLink`, which only covers the system profile. Ghostty exports `TERM=xterm-ghostty`, `ix shell` carries that value into the guest, and a guest with no matching terminfo entry gives you `can't find terminal definition for xterm-ghostty`, a zsh line editor that cannot position the cursor (keystrokes echo doubled) and a `clear` that refuses to run. The cost is 2.2 KiB: `terminfo` is a separate output of the ghostty derivation and cache.nixos.org has it, so nothing builds ghostty itself. Any other terminal that sets an exotic `TERM` needs its own entry here, or `environment.enableAllTerminfo = true` if the list ever grows past a couple.

Neovim plugins and treesitter parsers are materialised into the image because they cannot arrive any other way. `ix-closure-manifest assemble-closure` chunks only the store paths of the system closure plus a bare FHS skeleton, `/root` ships empty, and activation runs *after* the image is published, so anything `vim.pack` clones into `/root/.local/share/nvim/` at runtime is outside the image and re-downloaded by every VM. `lib/nvim-pack.nix` turns `dots/nvim/pack-sources.json` into one `fetchgit` per plugin and picks the treesitter grammars out of `pkgs.tree-sitter-grammars`; the `nvimPack` activation script copies plugins into `site/pack/core/opt/` and symlinks `${grammar}/parser` to `site/parser/<lang>.so`. Cost is 25 MiB.

Three behaviours of `vim.pack` are load-bearing here, all verified against a live VM rather than assumed. It accepts a plain writable directory and leaves it alone, so plugins ship without `.git` and at half the size. It deletes anything read-only or symlinked at the plugin path and re-clones it, logging `Removed corrupted lock data`, so the activation script must `cp -r` and `chmod -R u+w` rather than symlink. And nvim-treesitter honours a parser already present at `site/parser/<lang>.so` and skips its download, which is what makes the grammar symlinks work despite `auto_install = true` in `dots/nvim/lua/plugins/treesitter.lua`.

`dots/nvim/pack-sources.json` is generated, committed, and the only plugin list nix can see. It cannot read `nvim-pack-lock.json`: that file is gitignored (`dots/nvim/.gitignore:14`), so it is absent from the flake source and never reaches a VM, and `vim.pack` rewrites it destructively anyway (a VM booted before this change had a lock containing one plugin, because only the eagerly-loaded `plugin/git.lua` had registered by the time it was written). After bumping plugins, run `just nvim-pack-sources`, which reads your local lock and re-prefetches every hash. Skipping that step leaves the VM on the old revisions with no error, because nothing else reads the lock.

`parserNames` in `lib/nvim-pack.nix` deliberately omits `c`, `lua`, `markdown`, `markdown_inline`, `query`, `vim` and `vimdoc`: neovim already ships those in `${pkgs.neovim-unwrapped}/lib/nvim/parser`, so listing them again would pay for them twice.

`IS_SANDBOX = "1"` is what lets Claude Code run as root. Without it `claude` refuses with `--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons`; with it the same invocation reaches `Not logged in`. `ix shell` has no `--user` flag and always lands you as root, so the alternative would be adding a non-root account purely to satisfy that check.

Constraints that shaped it, all of them load-bearing:

- **`nixosConfigurations.ix`, not `ix.default`.** `ix new` first probes `ix.<attr>` and, only if that misses, builds `nixosConfigurations.<attr>.extendModules` with ix's machine profile. The probe has a hard 300s cap and must evaluate the full toplevel, which this flake's ~20 inputs cannot do cold. Exposing no `ix` output at all makes the probe miss in seconds on a missing attribute and puts the build on the `extendModules` path, which has no such timer.
- **No `index.lib.mkDev`.** It returns a fleet result whose nodes are `{ config = ...; }` with no `extendModules`, so `ix new` cannot wrap it. Dropping it also drops an import-from-derivation (`cargo-units.nix`) that made the config impossible to evaluate on aarch64. It now evaluates locally: `nix eval .#nixosConfigurations.ix.config.system.build.toplevel.drvPath`.
- **`boot.isContainer = true`.** ix owns the kernel, root device and console; the machine profile force-sets this in-guest. Setting it here too (same value, no conflict) is what lets the config evaluate standalone without a bootloader or `fileSystems."/"`.
- **`#spark` is not bootable.** Wrong architecture (aarch64 vs x86_64 guests), the dgx-spark NVIDIA module, and disko's `fileSystems` by UUID, which hangs boot in systemd device timeouts. Keep the two configs separate.

`ix new` resolves `github:`, `gitlab:` and `sourcehut:` only, never `git+https://git.harivan.sh/...`, so it builds the GitHub push mirror and not `origin`. Push the mirror before booting, or pin the sha (`ix new github:harivansh-afk/nix/<sha>#ix`), or you will silently get an older tree.

The VM has no secrets. sops-nix on spark derives its age key from the host ed25519 key, which a fresh VM cannot have, and a template image is cached per rev and shared, so nothing secret may enter the closure. Delivering sops here means minting a separate age identity, storing the private key with `ix secret set`, and attaching it at create time with `ix new --secret-file`. Not done yet.

## Forgejo mirroring

The legacy gitea-mirror Bun service has been removed. Forgejo's native mirror tables (`mirror` for inbound pulls, `push_mirror` for outbound pushes) are the source of truth. Two files drive the system:

- `modules/services/forgejo/mirror-manifest.nix`: policy-only config (intervals, `owned_owner`, the small `no_mirror` set, the `actions_enabled_repos` allowlist). No repo inventory is checked into nix; the actual list of repos to mirror is discovered at runtime by querying forgejo's own database. Rendered to `/etc/forgejo-mirror/manifest.json` at activation.
- `scripts/forgejo-mirror/reconcile.sh`: idempotent script that reads the manifest, deletes pull-mirror rows on push-mirror targets, creates missing push-mirrors with `use_ssh=true sync_on_commit=true interval=15m`, registers the forgejo-generated public key as a github deploy key, and flips `has_actions` per the allowlist. Run as root: `sudo FORGEJO_MIRROR_MANIFEST=/etc/forgejo-mirror/manifest.json bash scripts/forgejo-mirror/reconcile.sh [--dry-run]`.
- `scripts/forgejo-mirror/github-ux.sh`: optional, applies the barrettruth full treatment (github description/homepage/has_* metadata, `.github/README.md` banner, redirect-pr workflow) to every push-mirror. Run on demand: `bash scripts/forgejo-mirror/github-ux.sh [--dry-run] [--only owner/name]`.

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

Forgejo's own `[mirror] DEFAULT_INTERVAL` is `15m` and `[queue.mirror] MAX_WORKERS` is capped at `1`. The pre-start hook in `modules/services/forgejo/default.nix` uniformly jitters every pull-mirror's `next_update_unix` to `now + (repo_id % 900s)` on each forgejo start, so 100+ mirrors never bunch into a single hour the way they did under the old gitea-mirror scheduler.

## indexable-inc/ix mirroring

Source of truth is the jj-native ix forge (RPC `https://forge.ix.dev:8447/rpc`, UI `https://forge.ix.dev:8448/`, tailnet), not GitHub: github.com/indexable-inc/ix is archived and is never synced from. Clone with `jj-ix ix clone --server https://forge.ix.dev:8447/rpc --repo ix <dir>` and pass `--config 'signing.behavior=drop'` (the ix backend rejects commit signing). The forge has no whole-repo git egress, so `git.harivan.sh/indexable-inc/ix` is a regular repo kept current by pushing snapshot commits of forge `main` (tree from a jj-ix clone, parent = previous snapshot, message carries the forge commit id).

## Hermes agent

Hermes is the local-brain life concierge (`modules/services/hermes.nix`). Optimize its setup for the fewest non-overlapping tools and recall surfaces; when two features overlap in role, cut one. Recall is exactly three surfaces: built-in `memory` (injected identity and preferences, write-only), `kb_search` (Hari's own data), and `session_search` (past conversations). A second agent-authored memory store (`holographic`, `fact_store`) overlaps the first two and confuses the model.

## Knowledge base and ingestion

PostgreSQL + pgvector (`kb_vec`) for fast vector search plus a Cognee knowledge graph (Kuzu) rebuilt off-hours and rendered to `/var/lib/kb/graph/index.html` (not network-exposed; view via tunnel). Connectors stage normalized markdown into `/var/lib/kb/staging/<source>/`; the hourly `kb-ingest` embeds staging into pgvector. New sources are connectors following that pattern. Current sources: gmail, calendar, forgejo, `~/Documents/Downloads` (denylist-enforced), scheduled research missions (HN now, X gated on browser-use).

## Privacy and finance

Bank transactions (SimpleFIN, read-only token via sops) and charge or receipt emails feed one local-only finance namespace so a transaction links to its receipt in the graph (merchant, amount, date). It never leaves the machine. The ingestion denylist is enforced in code: `~/Documents/Downloads/{security, documents/finance-tax, documents/travel-identity, documents/legal-business}`. The finance carve-out covers transaction and charge data only; tax documents stay excluded.
