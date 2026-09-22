# files.harivan.sh

Open `https://files.harivan.sh/` and enter `rathi` in the browser's login prompt.
The password is unchanged. On Spark, display it with:

```sh
cat /run/secrets/sharefs-password
```

Documents and Downloads are bind mounts of the original Spark directories.
Uploads lives at `/var/lib/sharefs/uploads`. Browsing does not copy files.
Use the browser to upload, download, edit and delete files.

The Nix config is `hosts/spark/services/sharefs.nix`. The server listens on
`127.0.0.1:39473`; metadata lives in `/var/lib/sharefs/shares.db`, outside the
served root. Credentials come from SOPS through systemd, outside the Nix store.
The rest of the home directory is hidden from the service.

The owner API at `/__sharefs__/api/shares` creates, lists and revokes metadata.
Public-link serving and the new CLI/web Share controls are still being wired.
The previous `share` command and public links are retired. All requests to
the domain now go to sharefs; use the root URL instead of old bookmarks.

Static assets retain their cache headers. File and API responses are private
and not stored by caches. Scripts in served files are blocked; the sharefs UI
loads its script from its dedicated asset path.

Previous server databases and upload directories remain on disk. No data
cleanup is part of this deployment.
