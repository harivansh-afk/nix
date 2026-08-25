# pkgs/scripts

Packaged scripts: shell sources in `bin/` built into derivations with
`pkgs.writeShellApplication`.

## Wiring

`default.nix` exposes the full set as `commonPackages`;
`modules/users/user-config.nix` adds them to each user's packages, so they
land on `PATH` on every host. `portable.nix` is the home-independent subset
(no theme, no homeDirectory), exposed as flake packages by
`flake/packages.nix` so unmanaged hosts can
`nix profile add git+https://git.harivan.sh/harivansh-afk/nix#<name>`.

| Command        | Source                | Purpose                                      |
|----------------|-----------------------|----------------------------------------------|
| `theme`        | `bin/theme.sh`        | Switch cozybox dark/light, relink theme assets |
| `ga`           | `bin/ga.sh`           | Git add helper                               |
| `ghpr`         | `bin/ghpr.sh`         | Open/create GitHub PR                        |
| `iosrun`       | `bin/iosrun.sh`       | iOS simulator run helper                     |
| `wallpaper-gen`| `bin/wallpaper-gen.sh`| Generate themed wallpapers (uses `lib/wallpaper-gen.py`) |

Each entry in `lib/remotes.nix` additionally renders `bin/remote.sh` into a
per-remote connector command (`spark`, `macbook`, `dev6`, `dev1`, `dev2`,
`dev3`, `hil1`, `hil2`, `vin1`, `vin2`) that opens a shell on the remote over
mosh (`--ssh` for ssh).

`default.nix` also exports `themeAssetsText`, consumed by the theme-activation
block in `modules/users/user-config/`.

## Helpers (`lib/`)

Not standalone commands. Referenced by other config:

- `wallpaper-gen.py` - Python backing the `wallpaper-gen` command.

## Adding a packaged script

1. Drop the source in `bin/`.
2. Add an `mkScript` entry to `commonPackages` (or `darwinPackages` /
   `linuxPackages`) in `default.nix`.
