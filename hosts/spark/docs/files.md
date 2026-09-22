# files.harivan.sh

sharefs provides the private browser at the domain root. Log in as `rathi`
with the existing files password. Documents, Downloads and Uploads are bind
mounts of the original Spark directories; browsing does not copy files.

The Nix config is `hosts/spark/services/sharefs.nix`. The server listens on
`127.0.0.1:39473`; metadata lives in `/var/lib/sharefs/shares.db`, outside the
served root. Credentials come from SOPS through systemd, outside the Nix store.
The rest of the home directory is hidden from the service.

The owner API at `/__sharefs__/api/shares` creates, lists and revokes metadata.
Public-link serving and the new CLI/web Share controls are still being wired.

Quantum temporarily remains on `127.0.0.1:39476` for existing `/public/` links,
its API and the current `share` CLI. Both servers use the same original files
and password. The CLI still supports `--edit`, `--copy`, `--list`, `--revoke`,
passwords and expiry through Quantum. Remove this compatibility service once
sharefs replaces that complete flow.

Static assets retain their cache headers. File and API responses are private
and not stored by caches. Scripts in served files are blocked; the sharefs UI
loads its script from its dedicated asset path.

Existing Quantum and Copyparty data is retained. Retired Copyparty `/s/` links
continue to return 410. No data cleanup is part of this deployment.
