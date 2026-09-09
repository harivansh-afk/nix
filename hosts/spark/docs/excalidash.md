# ExcaliDash

`https://draw.harivan.sh` runs upstream ExcaliDash 0.6.0, using its official
Excalidraw editor dependency. Both ARM64 container images are pinned by digest
in `../services/excalidash/default.nix`. NixOS manages the Podman containers and
network; only the frontend is published, on `127.0.0.1:19462`.

Cloudflare terminates HTTPS, cloudflared forwards to Caddy, and Caddy forwards
to the frontend Nginx proxy. Caddy supplies the HTTPS scheme and Cloudflare's
client IP; the backend trusts the two proxy hops (Nginx and Caddy).

## Google sign-in

ExcaliDash uses its native OIDC integration with Google in hybrid mode, keeping
local password login available as a fallback. The Google Cloud project
`hari-495022` has a dedicated web client named `draw.harivan.sh`, with the sole
redirect URI `https://draw.harivan.sh/api/auth/oidc/callback`. Its client ID and
secret are encrypted in `secrets/hosts/spark/excalidash-google-oauth.env` and
injected through the backend container's environment file at runtime.

Google must attest that the email is verified. The first Google login for
`rathiharivansh@gmail.com` links to the existing owner account by email, preserving
its drawings and collections. The requested scopes are `openid profile email`.
Local registration stays disabled, and `OIDC_JIT_PROVISIONING=false` prevents
unknown Google identities from creating accounts. The admin UI can override
that provisioning default; keep its auto-provisioning toggle off as well.

Shared links retain their individual view/edit permissions and expiry. Guests
can use an enabled public link without an account; signing in with Google does
not grant access to the owner's library. Additional named users must be created
deliberately before they can use Google sign-in.

After deployment, verify `/api/auth/status` advertises Google, both registration
and OIDC auto-provisioning are disabled, and a Google login returns to the same
owner account with the existing drawings. Never put OAuth tokens or client
secrets in diagnostic output.

## First deployment

Merge the Forgejo PR and verify the Spark deploy job. Before publishing DNS
or importing drawings, complete upstream's one-time setup over the local
frontend at `127.0.0.1:19462`: enable authentication with
`POST /api/auth/onboarding-choice` (`{"enableAuth":true}`), then register the
owner with `POST /api/auth/register`. These are one-time application operations,
not startup hooks. API requests need the CSRF token and cookie from
`/api/csrf-token`, `Origin: https://draw.harivan.sh`, and
`X-Forwarded-Proto: https`, matching the production proxy context.

Initial admin registration requires the single-use setup code, available
locally with:

```sh
sudo journalctl -u podman-excalidash-backend --since '15 minutes ago' | rg 'BOOTSTRAP SETUP'
```

Use the code to register the owner's account. Do not
copy the setup code or passwords into commits, PRs, or agent output. Expired
codes are renewed by the upstream bootstrap flow. Confirm authentication is
enabled, public registration is disabled, and anonymous drawing access returns
401. Then apply the DNS change with `just dns-plan` and `just dns-apply`.
System activation does not apply Terraform records.

## Storage and backups

- `/var/lib/excalidash/prisma`: SQLite database, migrations, and upstream-generated
  persistent JWT/CSRF secrets. No application credentials enter the Nix store.
- `/var/lib/excalidash/uploads`: upload staging.
- `/var/backup/excalidash`: NixOS timer using SQLite's native online backup, daily at 04:00 UTC,
  retained for 14 days, with a quick integrity check after each backup. The
  upstream 0.6.0 scheduler fails on its Prisma checkpoint call and is disabled. Image bytes are stored in the database when S3 is unset.

These backups are on Spark's disk; they do not protect against loss of Spark.
Keep an additional exported archive elsewhere. Preserve the entire prisma
state directory when moving the installation, including the hidden secrets.

For database recovery, stop both containers, preserve the existing state,
restore a selected backup as `prisma/dev.db` with UID/GID 1001 ownership, and
remove stale `dev.db-wal`/`dev.db-shm` files from the restored copy before
starting the backend and frontend. Keep the old database and journals together
until recovery is verified. Do not copy a live SQLite main file by itself.

## Excalidraw+ migration

In Plus, open Workspace settings > Workspace export > Export accessible scenes.
The resulting ZIP contains the accessible workspace scenes, including the
owner's private scenes. Other members' inaccessible private scenes are outside
that export. Check each workspace separately.

Keep the original ZIP outside Git. Preserve existing collections and titles;
organize unfiled drawings into topic-based collections after inspecting them.
Use editable `.excalidraw` scene data, not PNG/SVG previews. Plus metadata and
share links are not guaranteed to transfer. Verify scene counts, embedded
images, and representative canvases before treating the migration as complete.
