# files.harivan.sh

FileBrowser Quantum serves files from Spark's `~/Documents` and `~/Downloads`.
Links point to the original file and are read-only unless `--edit` is given.

```sh
share notes.md
share --edit notes.md
share --expires=7d --password notes.md
share --copy report.pdf
share --list
share --revoke=ID
```

`--copy` uploads a snapshot, including from the Mac. Copies live in
`/var/lib/filebrowser-quantum/uploads/`; Mac transfers use SSH. Hidden files and
symlinks are excluded. Revocation removes access without deleting files.

Browser saves overwrite the shared file. Concurrent local/browser edits can
lose changes; Quantum does not merge them. Local changes appear on reload.
Share a folder when HTML or Markdown needs relative assets.

The owner account is `rathi`. The CLI uses `/run/secrets/filebrowser-password`
locally or retrieves it over SSH. Overrides: `SHARE_SERVER`,
`SHARE_PASSWORD_FILE`, `SHARE_USER`, `SHARE_SSH_HOST`. Custom servers require a
credential file; remote copies also require the matching SSH host.

The service config is `hosts/spark/services/filebrowser.nix`. State lives in
`/var/lib/filebrowser-quantum`, cache in `/var/cache/filebrowser-quantum`.
Caddy proxies `files.harivan.sh` to `127.0.0.1:39473`.

Copyparty's data remains on disk. Old `/s/` links return 410 and need replacing.
The Mac gets the CLI on its next switch; `nix run .#share -- FILE` also works.
