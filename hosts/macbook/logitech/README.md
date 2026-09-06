Logi Options+ mappings recovered from this Mac's Trash on September 5, 2026.
The original `settings.db` record was dated December 9, 2025 (UTC). It contains
MX Master 3 and MX Master 3S assignments, pointer and wheel settings, and a
radial menu. `macros.json` preserves the named `screen shot` macro, including
the original key press/release events and timing.

`settings.json` retains the original profile records without account data,
device serial numbers, analytics, or the installed-app inventory. The profile's
desktop application record and schema version are retained for Options+.

Nix seeds writable SQLite databases before Homebrew installs Options+ on a
fresh setup. Existing databases are preserved: Options+ owns their migrations
and runtime writes. These are recovery defaults, not an enforcement loop;
changing the JSON does not overwrite an existing live profile.

The Homebrew cask installs the vendor launchd services. Their names are allowed
in `../startup/default.nix`; no competing Nix agent starts the same backend.
macOS Accessibility/Input Monitoring approval remains an interactive OS step.

The complete original folder and preference files are also archived locally
under `~/Documents/logitech-recovery-20260905.P9tWh1`. They are not committed.
