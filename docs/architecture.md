# Architecture

## Goal

This repo should read like a steady-state machine configuration, not a diary of
whatever was necessary to survive the first migration.

The structure is intentionally split into three layers:

- `modules/`: host-wide `nix-darwin` policy
- `home/`: user-facing Home Manager config
- `config/`: raw config payloads consumed by Home Manager

## Host Layer

- [modules/base.nix](/Users/rathi/Documents/GitHub/nix/modules/base.nix) owns
  baseline Nix settings, shells, and common packages
- [modules/packages.nix](/Users/rathi/Documents/GitHub/nix/modules/packages.nix)
  owns the heavier developer tooling and fonts
- [modules/homebrew.nix](/Users/rathi/Documents/GitHub/nix/modules/homebrew.nix)
  is the explicitly narrow Brew escape hatch for GUI casks, including Codex
  because the Homebrew-distributed app is a better fit here than a source build
- [modules/macos.nix](/Users/rathi/Documents/GitHub/nix/modules/macos.nix)
  owns system defaults and macOS-specific integration

## Home Layer

- each app/tool gets its own module under `home/`
- raw config trees live under `config/` and are linked by Home Manager
- [home/migration.nix](/Users/rathi/Documents/GitHub/nix/home/migration.nix)
  is the only place where takeover logic for old `~/dots` symlinks lives

That separation matters. Steady-state modules should describe how the machine
works today. Migration-only ownership cleanup belongs in one place and should be
easy to delete later.

## Package Sources

Default rule:

- use `nixpkgs` for stable everyday tooling

Exceptions:

- use dedicated flake inputs for fast-moving product CLIs whose release cadence
  matters to the machine owner

Current dedicated inputs:

- `googleworkspace-cli`
- `claudeCode`

## Intentional Pragmatism

Some pieces are still pragmatic compatibility shims rather than ideal upstream
state:

- [modules/macos.nix](/Users/rathi/Documents/GitHub/nix/modules/macos.nix)
  carries a Karabiner launch-agent override because current nix-darwin still
  points at the older Karabiner bundle layout
- [home/claude.nix](/Users/rathi/Documents/GitHub/nix/home/claude.nix) manages
  `~/.local/bin/claude` so the Nix package cleanly replaces the old manual path
  that was already first in shell PATH

Those are acceptable as long as they are explicit and documented.
