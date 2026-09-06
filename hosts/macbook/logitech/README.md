Logi Options+ mappings recovered from this Mac's Trash on September 5, 2026.
The original `settings.db` record was dated December 9, 2025 (UTC). It contains
MX Master 3 and MX Master 3S assignments, pointer and wheel settings, and a
radial menu. `macros.json` preserves the named `screen shot` macro, including
the original key press/release events and timing.

`settings.json` retains the original profile records without account data,
device serial numbers, analytics, or the installed-app inventory. The profile's
desktop application record and schema version are retained for Options+.

`mappings.json` defines the current controls for both mice: forward button
pastes, thumb-click copies, and thumb-up/down adjusts volume. Thumb-left/right
navigates back/forward only in Helium, Dia, Zen and Safari; elsewhere these
gestures do nothing. Screenshot buttons, wheels and pointer settings retain
their existing assignments.

Before Homebrew installation, Nix seeds missing databases from the recovered
records and applies the current controls to existing installations. The apply
step merges only the two owned button assignments per mouse and the browser
profiles. Other settings and the original screenshot macro are retained.
When changes are needed, it stops the vendor agent, saves a SQLite backup in
`~/Library/Application Support/LogiOptionsPlus-backups`, updates the database,
and restarts the agent. An unchanged configuration does not restart it.

The Homebrew cask installs the vendor launchd services. Their names are allowed
in `../startup/default.nix`; no competing Nix agent starts the same backend.
macOS Accessibility/Input Monitoring approval remains an interactive OS step.

The complete original folder and preference files are also archived locally
under `~/Documents/logitech-recovery-20260905.P9tWh1`. They are not committed.
