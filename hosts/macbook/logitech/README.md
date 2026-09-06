Options+ is installed through Homebrew and runs its vendor launchd jobs.
`mappings.json` owns copy/paste and the thumb gestures for MX Master 3 and 3S.
Browser history gestures are scoped to Helium, Dia, Zen and Safari. Screenshot,
wheel, pointer and unrelated application settings are preserved.

`apply.py` runs before Homebrew activation. It seeds missing databases, compares
current mappings, and changes only the owned controls. Updates pause the vendor
agent and create a SQLite backup in `~/Library/Application Support/LogiOptionsPlus-backups`.
Matching settings do not cause a write or restart. macOS permissions still
require interactive approval.

`defaults.json.gz` is a data artifact, not editable configuration. It losslessly
stores the recovered profiles (`settings`), original screenshot macro (`macros`),
and vendor action definitions (`cards`). It excludes account data, serial numbers
and analytics. To inspect it: `gzip -dc hosts/macbook/logitech/defaults.json.gz | jq`.
The uncompressed originals are also in Git history and the private recovery
archive at `~/Documents/logitech-recovery-20260905.P9tWh1`.

Run tests with `uv run --no-project python hosts/macbook/logitech/test_apply.py`
or `nix build .#checks.aarch64-darwin.logitech`.
