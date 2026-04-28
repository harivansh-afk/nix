# AGENTS.md

## Architecture

Two hosts, one flake:

| Host | Platform | System | Role |
|------|----------|--------|------|
| `macbook` | nix-darwin | aarch64-darwin | Dev workstation |
| `spark` | NixOS | aarch64-linux | NVIDIA DGX Spark server |

Both are declared in `lib/hosts.nix` and assembled in `flake/hosts.nix` (darwin) and `flake/nixos.nix` (nixos). The `flake/args.nix` module wires shared args (`username`, `mkSpecialArgs`, `mkHomeManagerModule`) consumed by both host builders.

### Host topology

- `macbook`: nix-darwin + home-manager + Homebrew casks + Determinate Nix
- `spark`: NixOS + disko + sops-nix + dgx-spark upstream module + Caddy + cloudflared tunnel + Tailscale

### Service routing on spark

Internet traffic hits Cloudflare edge (TLS termination), then cloudflared tunnel delivers plain HTTP to Caddy on 127.0.0.1:80. Caddy dispatches by Host header to backend services, each bound to 127.0.0.1 on their own port. No ACME, no public firewall ports for web traffic.

Services: Forgejo (`git.harivan.sh`), Vaultwarden (`vault.harivan.sh`), Delta (`delta.harivan.sh`).

### Secrets

sops-nix with age encryption derived from the host's ed25519 SSH key. Secret files live under `secrets/<hostname>/`. Edit with `just sops-edit secrets/spark/<file>`.

## Conventions

- No comments in `.nix` files. The code is the documentation. Agent guidance lives here.
- Use `just switch` for macbook rebuilds, `just switch-spark` for spark rebuilds.
- `just fmt` runs `nix fmt` (nixfmt-tree).
- Install spark from scratch with `just spark-install user@host`.
- The `tmp/` directory contains archived/reference configs - do not modify.
- Berkeley Mono is installed out-of-band. The flake only provides nerd-fonts symbol glyphs.
- Ghostty is installed via Homebrew cask, not nixpkgs. home-manager owns only its config files.
- Karabiner config is a directory symlink to `dots/karabiner/` so Karabiner can write freely.
- Cursor-agent, Claude, and Codex are curl-installed binaries. On NixOS they need nix-ld.
- Devin config is seeded as a mutable copy since Devin rewrites it.

## Module layout

```
flake.nix              Inputs + flake-parts structure
flake/
  args.nix             Shared args: username, host records, builders
  devshell.nix         Dev tools + formatter
  hosts.nix            macbook darwin configuration
  nixos.nix            spark NixOS configuration
lib/
  hosts.nix            Host records (name, system, features)
  theme.nix            Cozybox theme: colors, renderers for ghostty/tmux/fzf/lazygit/pure-prompt/bat/zsh-highlights
system/
  common.nix           Shared nix settings, overlays, base packages
  packages.nix         Extra packages + fonts
  buck2.nix            Pinned buck2 binary derivation
home/
  default.nix          Import hub for all home-manager modules
  common.nix           Platform-conditional imports (darwin: ghostty/aerospace/karabiner/helium; linux: worktree)
  zsh.nix              Shell config, aliases, PATH, theme hooks
  prompt.nix           Pure prompt with dynamic dark/light theming
  git.nix              Git config with diff-so-fancy
  tmux.nix             Tmux config with session-list statusline
  claude.nix           Claude Code binary + settings + commands
  codex.nix            Codex CLI + AGENTS.md
  skills.nix           Global Claude skills auto-install
  scripts.nix          Theme activation + wallpaper seeding
  ...                  One file per tool (bat, fzf, eza, gh, k9s, ssh, etc.)
hosts/
  macbook/
    default.nix        Homebrew casks, user setup
    macos.nix          System defaults (dock, finder, keyboard, screenshots, login items, tailscale)
  spark/
    default.nix        Base NixOS config, nix-ld, kernel hardening
    hardware.nix       DGX Spark module + disko disk layout
    networking.nix     Wi-Fi (NetworkManager), Tailscale, firewall, zram
    users.nix          User accounts from users/ directory, SSH, sudo
    rathi/default.nix  Home-manager for rathi on spark
    barrett/default.nix Home-manager for barrett on spark
modules/
  security/sops.nix    sops-nix setup, age key from SSH host key
  services/
    caddy.nix          Reverse proxy on loopback, loopbackVhost helper
    cloudflared.nix    Cloudflare tunnel to Caddy
    delta.nix          Delta todo app service
    forgejo.nix        Forgejo + GitHub mirror sync + heatmap reconciliation + Actions runner
    vaultwarden.nix    Vaultwarden password manager
scripts/
  default.nix          Script builder (theme, ga, ghpr, iosrun, wallpaper-gen, wt)
users/
  default.nix          User registry
  rathi.nix            SSH keys + groups for rathi
  barrett.nix          SSH keys + groups for barrett
dots/                  Dotfile sources (nvim, karabiner, lazygit, claude commands, etc.)
```

## Theme system

The "cozybox" theme has dark and light variants defined in `lib/theme.nix`. A runtime state file at `~/.local/state/theme/current` holds `dark` or `light`. The `theme` script (from `scripts/bin/theme.sh`) switches mode by updating symlinks for fzf, ghostty, tmux, lazygit, and the wallpaper, then reloading tmux. Shell hooks in `zsh.nix` re-apply prompt colors, zsh syntax highlights, and bat theme on every `precmd`.

## Key dependencies

- `nixpkgs-nushell`: Separate nixpkgs pin for nushell on darwin (avoids EPERM test failures in the darwin sandbox without invalidating the spark NVIDIA kernel hash).
- `dgx-spark`: Upstream NixOS module for DGX Spark hardware. Do not set `inputs.nixpkgs.follows` - the upstream pins nixpkgs to a known-good revision for the NVIDIA kernel build.
- `determinate`: Manages the Nix installation, daemon, and `/etc/nix/nix.conf`. On darwin, use `determinateNix.customSettings` instead of `nix.settings`.
- `neovim-nightly`: Overlay applied only on darwin (no aarch64-linux binary cache).

## Adding a new service on spark

1. Create `modules/services/<name>.nix`.
2. Add the sops secret: create `secrets/spark/<name>.env`, encrypt with `just sops-edit`.
3. Use `loopbackVhost` from caddy.nix: `services.caddy.virtualHosts."http://<domain>" = loopbackVhost <port>;`.
4. Import the new module in `hosts/spark/default.nix`.
5. Add the DNS record in Cloudflare pointing to the tunnel.

## Adding a new user on spark

1. Create `users/<name>.nix` with `sshKeys`, `shell`, and `extraGroups`.
2. Create `hosts/spark/<name>/default.nix` for their home-manager config.
3. The user is automatically picked up by `hosts/spark/users.nix`.
