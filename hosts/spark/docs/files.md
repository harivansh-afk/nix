# files.harivan.sh

Copyparty serves a private directory on Spark. The `share` command uploads a
copy, creates a public link, and prints only that URL to stdout. Recipients use
the browser; Hari can manage files and revoke links through the web control
panel's shares page. Nothing requires the publishing terminal to remain open.

```sh
share ./notes.md
share ./notes.md --edit
share ./photos/ --expires 7d
share ./notes.md --edit --password
```

`--edit` allows Markdown/plain-text saves; on folder links it also permits
uploads. Recipients cannot delete files. Copyparty checks modification times
when saving Markdown; this is not simultaneous collaborative editing.
The original local file is unchanged. Download the edited copy from the browser
when you want to bring it back. Share the containing folder when a Markdown
document needs relative images or other linked files.

Links are unlisted, accessible to anyone holding the URL, and do not expire by
default. `--password` prompts without echo. Expiry and revocation remove access,
not the uploaded data. The domain root never exposes the private file inventory
to anonymous visitors. Revocation cannot retract a recipient's previous download.

Files live under `/var/lib/copyparty/files/published/<id>/`. Directory publication
excludes dotfiles and hidden subdirectories; an explicitly selected dotfile can
be published. Symlinks and special files are rejected. The command uses upstream
`u2c` for bounded, chunked uploads (32 MiB maximum POST) and in-process retries.
After a terminated command, retrying creates a new copy; unfinished uploads stay
private and can be removed through the authenticated file manager.

## Authentication

On Spark, `share` automatically reads the owner-readable SOPS credential at
`/run/secrets/copyparty-password` and uploads directly to the loopback backend;
the returned share URL still uses the public domain. For web login, retrieve that password locally
and use copyparty's login form (account: `rathi`). Do not paste it into chat or
commit a decrypted copy.

On the Mac, `share` retrieves the credential through your existing SSH access
to Spark, without prompting or saving another password. There is no CLI login.
The command is included in
the shared user package set on the next switch and is also a standalone flake
package, `nix run .#share -- ./notes.md`. Successful commands print only the URL;
the upstream uploader's diagnostics are shown only if it fails. No OAuth provider is required. For
explicit alternate instances, set both `SHARE_SERVER` and `SHARE_PASSWORD_FILE`;
the latter is a file path, never a password argument.

## Deployment

The PR declares the service, encrypted credential, CLI and DNS record; it does
not itself activate anything. After merge, Spark's normal deployment applies
the NixOS configuration. Run `just dns-plan` and review the result before
`just dns-apply`; DNS uses a separate OpenTofu workflow and requires an
edit-capable Cloudflare credential. Switch the Mac to install its CLI.

Cloudflare Tunnel forwards to Caddy, then loopback port 39473. Copyparty runs
as its own user with upstream's filesystem sandbox, restricted to its state,
cache, credential and served directory. The account secret remains outside the
Nix store. Package and uploader are pinned to 1.20.24; the source input supplies
the matching upstream NixOS module. Update both pins together.

After activation, verify a guest read, a guest Markdown edit, a password link,
revocation, and an upload larger than 100 MB through the real domain. Local
validation does not prove Cloudflare settings or the live deployment.
