# files.harivan.sh

Open `https://files.harivan.sh/` and log in as `rathi`. The password is unchanged;
read it on Spark with `cat /run/secrets/sharefs-password`. To change it, edit
`secrets/hosts/spark/sharefs-password` with SOPS and deploy the Nix configuration.

Documents, Downloads and Uploads map to `~/Documents`, `~/Downloads` and
`~/Uploads`. These are the original files. Editing changes them on disk.
The activation moves the previous upload directory to `~/Uploads`; it refuses
to overwrite an existing destination. The old SQLite database is retained but
unused.

## Share a file on Spark

```sh
share ~/Documents/notes.md
share --expires=2h ~/Downloads/report.pdf
share --help
```

The Rust client prints one URL and defaults to seven days. Durations accept
`s`, `m`, `h`, `d` and `w`. Files must be inside a served directory. The browser's
Share control uses the same signer and lets you select an expiry.

Recipients need no login. Links grant read-only access to one live file path;
renaming it breaks the link, and edits at the same path change what recipients
read. Links survive restarts. Rotating `sharefs-signing-key` invalidates all
links; individual revocation is not supported.

The **Shares** link on the right of the header opens a table of active links,
with file paths, creation and expiration times, and copy/open actions. It
includes links created by the browser and CLI. The private index lives in
`/var/lib/sharefs/shares`, outside the served folders, and survives restarts.
Expired links and links signed with an old key do not appear. Links created
before tracking was enabled still work but cannot be reconstructed in this list.
The index is only used to record and list shares; public reads still validate
signed tokens directly.

The UI exposes share, edit, download and rename as icons in the Actions column.
The share form contains an expiry selector and copy button. Rename stays in
the same directory and cannot replace an existing file. Deletion is disabled
on the server. Search and ZIP downloads remain disabled.

## Deployment

`hosts/spark/services/sharefs.nix` owns the service and Caddy route. The server
listens on `127.0.0.1:39473`. The local CLI uses `/run/sharefs/control.sock`,
accessible only to the service owner. Mount mappings come from the same Nix
attribute set as the service's bind mounts.

The password is a SOPS secret loaded through systemd credentials. The signing
key is read directly from its owner-only SOPS runtime file, since sharefs
requires private file permissions. It is 32 random bytes, outside the Nix store
and served tree.
The service is sandboxed and the rest of the home directory is hidden.

File responses are not cached; versioned static assets retain immutable caching.
Scripts in served files are blocked. Both application and proxy logs redact
share tokens.

`RestrictSUIDSGID` must remain disabled for this service: systemd blocks
`openat2` when it is enabled. sharefs uses that syscall to open shared files
beneath its root safely and checks support at startup. `NoNewPrivileges` and
an empty capability set remain enabled.
