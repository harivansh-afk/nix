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
read. Links survive restarts. There is no share registry or individual
revocation; rotating `sharefs-signing-key` invalidates all links.

The UI supports upload, download, content editing and rename. Rename stays in
the same directory and cannot replace an existing file. Deletion is disabled
on the server. Search and ZIP downloads remain disabled.

## Deployment

`hosts/spark/services/sharefs.nix` owns the service and Caddy route. The server
listens on `127.0.0.1:39473`. The local CLI uses `/run/sharefs/control.sock`,
accessible only to the service owner. Mount mappings come from the same Nix
attribute set as the service's bind mounts.

Password and signing key are SOPS secrets loaded through systemd credentials.
The signing key is 32 random bytes, outside the Nix store and served tree.
The service is sandboxed and the rest of the home directory is hidden.

File responses are not cached; versioned static assets retain immutable caching.
Scripts in served files are blocked. Both application and proxy logs redact
share tokens.
