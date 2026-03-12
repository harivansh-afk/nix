# Machine Audit

This is the baseline inventory used to seed the first pass of this Nix config.

## Host Summary

- Machine: `hari-macbook-pro`
- Hostname: `hari-macbook-pro.local`
- Platform: `arm64-darwin`
- OS: macOS `26.3` (`25D5112c`)
- Nix: `2.34.1`
- `darwin-rebuild`: not installed yet

## Filesystem Roots Checked

Top-level roots on `/`:

- `Applications`
- `Library`
- `System`
- `Users`
- `nix`
- `opt`
- `private`
- `usr`

Large user-owned roots spotted during audit:

- `/Users/rathi`
- `/Users/rathi/Documents`
- `/Users/rathi/Library`
- `/Users/rathi/.config`
- `/Users/rathi/.local`
- `/opt/homebrew`

## Live Dotfiles Source Of Truth

The live machine is wired to `~/dots`, not `~/Documents/GitHub/dots`.

Confirmed symlinks:

- `~/.gitconfig -> ~/dots/git/.gitconfig`
- `~/.zshrc -> ~/dots/zsh/.zshrc`

There is also a duplicate clone at `~/Documents/GitHub/dots`. Content matched during the audit, but the active machine points at `~/dots`.

## Homebrew Inventory

This repo currently mirrors the top-level Homebrew inventory rather than every transitive dependency.

For a raw rerunnable dump, use `./scripts/snapshot-machine.sh`. The generated files go under `inventory/current/`.

### Taps

- `daytonaio/tap`
- `getcompanion-ai/tap`
- `hashicorp/tap`
- `homebrew/services`
- `humanlayer/humanlayer`
- `jnsahaj/lumen`
- `nicosuave/tap`
- `nikitabobko/tap`
- `opencode-ai/tap`
- `pantsbuild/tap`
- `pipedreamhq/pd-cli`
- `steipete/tap`
- `stripe/stripe-cli`
- `supabase/tap`
- `tallesborges/zdx`
- `withgraphite/tap`

### Brew Leaves

The current leaves were captured into [`modules/homebrew.nix`](../modules/homebrew.nix). A few noteworthy details:

- `python@3.13` was installed but `link: false` in the generated Brewfile
- `withgraphite/tap/graphite` was also `link: false`
- Go tools and one cargo tool were present in the generated Brewfile and are not yet expressed in the Nix module
- VS Code extension `anthropic.claude-code` was also present in the generated Brewfile and is not yet managed here

### Casks

Current casks were also captured into [`modules/homebrew.nix`](../modules/homebrew.nix), including:

- `aerospace`
- `codex`
- `companion`
- `gcloud-cli`
- `ghostty@tip`
- `warp`
- `virtualbox`

### Brew Services

Installed but not currently running:

- `cloudflared`
- `postgresql@14`
- `postgresql@16`
- `postgresql@17`
- `redis`
- `tailscale`
- `unbound`

## Apps Outside Current Brew Casks

The following apps were present in `/Applications` but did not match the current cask inventory during a rough audit, so they should be reviewed separately:

- `Amphetamine.app`
- `Cap.app`
- `ChatGPT.app`
- `Claude.app`
- `Cluely.app`
- `Conductor.app`
- `Dia.app`
- `Docker.app`
- `Granola.app`
- `Helium.app`
- `Karabiner-Elements.app`
- `Karabiner-EventViewer.app`
- `Klack.app`
- `Numbers.app`
- `PastePal.app`
- `Raycast.app`
- `Readout.app`
- `Rectangle.app`
- `Safari.app`
- `Screen Studio.app`
- `Signal.app`
- `Tailscale.app`
- `Telegram.app`
- `Typora.app`
- `Wispr Flow.app`
- `Zen.app`
- `kitty.app`
- `logioptionsplus.app`

Some of these may belong in:

- Mac App Store
- direct DMG installers
- manual vendor installers
- future Homebrew casks that were not part of the current audit

App Store apps confirmed by receipt search:

- `Amphetamine.app`
- `Klack.app`
- `Numbers.app`
- `PastePal.app`
- `Xcode.app`

## Launch Agents Found

These are current launch agents worth deciding on explicitly:

- `com.nanoclaw.plist`
- `com.thread-view.collector.plist`
- `com.thread-view.ngrok.plist`
- `pi.plist`
- `homebrew.mxcl.postgresql@16.plist`
- `org.virtualbox.vboxwebsrv.plist`
- Google updater agents
- iMazing mini agent

These are not yet represented in Nix.

Current login items:

- `Rectangle`
- `Raycast`
- `PastePal`

## Config Directories Found

Notable user config roots under `~/.config`:

- `agents`
- `amp`
- `gcloud`
- `gh`
- `gh-dash`
- `ghostty`
- `git`
- `graphite`
- `k9s`
- `karabiner`
- `kitty`
- `nanoclaw`
- `opencode`
- `raycast`
- `rpi`
- `stripe`
- `tmux`
- `worktrunk`
- `zed`

Notable app state under `~/Library/Application Support`:

- `Claude`
- `Codex`
- `Code`
- `Cursor`
- `Docker Desktop`
- `Ghostty`
- `Google`
- `LogiOptionsPlus`
- `OpenAI`
- `Raycast`
- `Screen Studio`
- `Signal`
- `Slack`
- `Telegram Desktop`
- `Warp`
- `Zed`

These paths are exactly why the first config keeps Homebrew and dotfile migration conservative.

## Additional Package Managers And Tool State

Global npm packages found:

- `@anthropic-ai/claude-code`
- `@augmentcode/auggie`
- `@companion-ai/cli`
- `@googleworkspace/cli`
- `@humanlayer/linear-cli`
- `@kubasync/cli`
- `agent-browser`
- `aws-cdk`
- `bun`
- `clawdbot`
- `markserv`
- `pnpm`
- `prisma`
- `vercel`
- `wscat`
- `yarn`

Other tool inventories found:

- `pipx`: `supabase-mcp-server`
- `uv tool`: `mistral-vibe`, `nano-pdf`
- `cargo install`: `lumen`
- Go bin tools: `agentikube`, `goimports`, `golangci-lint`, `gonew`
- Python user packages under `python3 -m pip list --user`

These are not represented in the first-pass Nix config yet.

## Codebase Summary

Code roots found:

- `~/Documents/GitHub` with `108` repos
- `~/code/symphony-workspaces`
- `~/dev/diffs.nvim`
- extra git repos outside those roots: `~/dots`, `~/meta-agent`, `~/Documents/College`, `~/Documents/better`, `~/.config/nvim.bak`, `~/.veetcode`, `~/.kubasync/clank-artifacts`, `~/.oh-my-zsh`

Repo manifest counts under `~/Documents/GitHub`:

- `package.json`: `56`
- `pnpm-workspace.yaml`: `7`
- `turbo.json`: `5`
- `pyproject.toml`: `6`
- `requirements.txt`: `7`
- `go.mod`: `3`
- `Cargo.toml`: `4`
- `flake.nix`: `4`
- `Dockerfile`: `10`
- `docker-compose.yml`: `7`

Practical implication:

- JavaScript/TypeScript is the dominant toolchain
- Python is the second major toolchain
- Go and Rust are both active enough to be first-class system runtimes
- Docker and local infra tooling belong in the baseline machine config

## Migration Boundaries

Safe to move into Nix now:

- core CLI packages
- current Homebrew taps, brews, and casks
- dotfiles already living in `~/dots`
- basic macOS defaults

Should stay manual or secret-managed for now:

- `~/.secrets`
- `~/.npmrc`
- `~/.yarnrc`
- `~/.claude.json`
- `~/.opencode.json`
- cloud credentials and tokens under `~/.config`
- app-internal state in `~/Library/Application Support`
- App Store apps and login items
- fonts installed directly under `~/Library/Fonts`
- global npm, pipx, uv, cargo, and Go-installed tools
- custom launch agents until they are rewritten declaratively

Recommended next steps:

1. Switch this host once with cleanup disabled.
2. Translate `git`, `zsh`, and `ghostty` from raw symlinks into pure Home Manager modules.
3. Decide whether `~/dots` should remain the source of truth or be folded into this repo.
4. Capture secrets explicitly instead of relying on ad hoc local files.
5. Review the unmanaged `/Applications` set and choose Homebrew cask, App Store, or manual buckets for each.
