# files.harivan.sh

FileBrowser Quantum serves existing files on Spark. The `share` command prints
one URL to stdout. A normal share points at the original file; it does not
upload, copy or move it, and the publishing terminal can close immediately.

```sh
share ./notes.md
share ./notes.md --edit
share ./photos/ --expires 7d
share ./notes.md --edit --password
share list
share revoke <id-or-url>
```

Read-only is the default. `--edit` lets a recipient save changes to the original
file. It does not grant upload, creation, replacement or deletion permissions.
Browser editing applies to formats Quantum can edit, such as text and Markdown.
Quantum provides Markdown/HTML, PDF, image and media viewers. Share a folder
when a document needs relative images or other assets.

A fresh read follows the current file at the same path, including an editor's
atomic replacement. An already-open view may need reloading. Quantum's text
editor saves the whole file without a revision precondition: simultaneous
browser/local edits can overwrite each other. This is not collaborative typing
or conflict-aware synchronization. Moving or deleting the original makes its
share unavailable; it does not retain a detached copy.

Links are unlisted, accessible to anyone holding the URL, and do not expire by
default. `--password` prompts without echo. Expiration and revocation remove
access, not the source data. Revocation cannot retract previous downloads.
Anonymous visitors cannot browse the private source inventory.

## Sources and copies

Live sharing is available under `/home/rathi/Documents` and
`/home/rathi/Downloads`. Quantum reads these paths directly; adding shares
inside them does not require a service restart or rebuild. Its systemd
namespace hides the rest of the home directory. Hidden paths and symlinks are
excluded; `node_modules` is viewable but excluded from the search index.

Files outside those sources, including files that exist only on the Mac,
require an explicit copy:

```sh
share ./report.pdf --copy
share ./draft.md --copy --edit
```

Copies go to `/var/lib/filebrowser-quantum/uploads/<id>/`. Editing a copied
share changes that copy, leaving the original alone. The Mac uploads over SSH,
so Cloudflare request-body limits do not apply to CLI uploads. This is a
snapshot, not continuous synchronization with the Mac. Folder copies exclude
hidden entries and reject symlinks/special files. Interrupted uploads can leave
private incomplete copies in the Uploads source; inspect those in the file
manager before removing them.

To add a source, change `hosts/spark/services/filebrowser.nix`, including its
systemd filesystem access, then rebuild. Do not edit the running config.

## Authentication and storage

The owner account is `rathi`. The password is supplied from SOPS through
`/run/secrets/filebrowser-password` and systemd credentials; it never enters the
Nix store. The CLI reads it locally on Spark or obtains it through existing
SSH access from the Mac. No additional CLI login is required. The password is
the same credential previously used for Copyparty, renamed during migration.

Quantum's database is `/var/lib/filebrowser-quantum/database.db`; its cache is
`/var/cache/filebrowser-quantum`. Share metadata survives restarts. The NixOS
service runs as `rathi` with filesystem access restricted to its sources,
state and cache. Save permissions therefore match the owner of local files.

Advanced instance overrides are `SHARE_SERVER`, `SHARE_PASSWORD_FILE`,
`SHARE_USER` and `SHARE_SSH_HOST`. Custom servers require an explicitly readable
credential file. Only HTTPS or loopback HTTP is accepted, and authentication
requests do not follow redirects. Remote copy destinations must identify their
SSH host explicitly when using a custom server.

The command is part of the shared user package set and is also available as
`nix run .#share -- ./notes.md`. Spark receives it with deployment; switch the
Mac to update its installed command, or use the portable flake package.

## Deployment and migration

The package pins the official Quantum `v1.5.6-stable` binaries by SHA-256.
Cloudflare Tunnel forwards to Caddy, then Quantum on `127.0.0.1:39473`.
No DNS change is needed. Merge/deployment and live verification are separate
steps; a passing local test does not prove the production switch succeeded.

Copyparty's service is removed. Its files, share database and cache are left on
disk untouched. Old `/s/` URLs return HTTP 410 with a message requesting a new
link; they are not automatically translated into Quantum shares. Data cleanup
requires a separate decision.

Run the real-server integration check after building both packages:

```sh
nix build .#filebrowser-quantum --out-link /tmp/quantum-server
nix build .#share --out-link /tmp/quantum-cli
uv run --no-project python scripts/share-smoke.py /tmp/quantum-server/bin/filebrowser-quantum /tmp/quantum-cli/bin/share
```

It exercises no-copy reads, guest edits, read-only/deletion denial, atomic local
saves, sibling and symlink containment, private inventory, copies, password
protection, expiration and revocation against isolated temporary test data.
Also verify the rendered guest editor/viewers and repeat an original-file edit
through the actual public domain after deployment.
