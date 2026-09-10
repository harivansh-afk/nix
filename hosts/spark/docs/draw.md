# draw

`https://draw.harivan.sh` runs draw, the self-hosted Excalidraw+ from
`git.harivan.sh/harivansh-afk/draw`: excalidraw.com's own editor (a fork of the
excalidraw monorepo, kept current with `git merge upstream/master`) plus a Go
backend that owns accounts, scenes, live collaboration, share links and the
dashboard. One binary, one SQLite database, no containers.

Cloudflare terminates HTTPS, cloudflared forwards to Caddy, Caddy forwards to
`127.0.0.1:34729`. Caddy supplies the HTTPS scheme and Cloudflare's client IP;
the server trusts one proxy hop (`DRAW_TRUST_PROXY=1`). WebSockets for
collaboration ride the same `reverse_proxy`.

The flake input `draw` follows this repo's nixpkgs. `hosts/spark/services/draw.nix`
imports the module the draw repo ships (`services.draw`) and adds the Caddy
vhost and the backup timer. Upgrading is `nix flake update draw` in a PR.

## Google sign-in

The Google Cloud project `hari-495022` has a web client named `draw.harivan.sh`
with the sole redirect URI `https://draw.harivan.sh/api/auth/oidc/callback`. Its
client ID and secret are encrypted in `secrets/hosts/spark/draw-google-oauth.env`
as `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` and injected through the service's
`EnvironmentFile`. This is the same client and the same file ExcaliDash used,
renamed; nothing changed in the Google console.

Google must attest that the email is verified. `services.draw.allowedEmails` is
empty, so the first account that signs in is recorded as the only allowed
account; any other Google identity is refused with `?error=not_allowed`. To let
more people in, list them in `allowedEmails` and rebuild.

Share links do not need an account: a scene set to "anyone with the link can
view" or "can edit" is reachable at its `/s/<id>` URL, with the permission
enforced by the server on both HTTP and the WebSocket relay. `/local` is
excalidraw.com's local-only editor and needs no account either.

## Storage and backups

- `/var/lib/draw/draw.db`: SQLite (WAL). Users, sessions, scenes, room payloads
  (encrypted client-side with the per-scene room key, which the server also
  stores), room version history, snapshots, libraries.
- `/var/lib/draw/files/`, `/var/lib/draw/thumbs/`: encrypted image files and
  scene thumbnails.
- `/var/lib/draw/session.key`: cookie signing key, generated on first start.
- `/var/backup/draw`: nightly `draw backup` (SQLite `VACUUM INTO`) at 04:00 UTC,
  14-day retention, integrity-checked. The files directory is not in the
  backup; back it up with the rest of `/var/lib/draw` if it matters.

Restore: stop `draw.service`, replace `draw.db` (delete stale `-wal`/`-shm`),
fix ownership to `draw:draw`, start the service.

## Importing from ExcaliDash

The old ExcaliDash state directory `/var/lib/excalidash` is kept on disk until
the import has been verified. Run as root:

```
sudo -u draw draw import-excalidash \
  --db /var/lib/excalidash/prisma/dev.db \
  --uploads /var/lib/excalidash/uploads \
  --owner rathiharivansh@gmail.com --dry-run
```

Drop `--dry-run` to write. Drawings become scenes with their names, timestamps
and collections; embedded images are re-wrapped in Excalidraw's file envelope.
After verifying scene counts and a few canvases, delete `/var/lib/excalidash`
and `/var/backup/excalidash`.

## Dashboard

The dashboard is draw's own code (`excalidraw-app/dashboard/` in the draw
repo); the editor is upstream Excalidraw and is never patched. It follows
harivan.sh's look (Berkeley Mono, three colours per theme, dotted underlines)
and is keyboard-driven: vim motions over the scene grid, `cmd+k` for a command
palette, `?` for the key sheet. One document-level key engine owns every
binding; the registry in `dashboard/keyboard/commands.ts` is where a shortcut
is added or changed. The right-hand rail is the owner's activity timeline,
served by `GET /api/activity` from the `activity` table (rows outlive their
scene, purged after 90 days; autosaves fold into one entry per session).

## Verification after a deploy

- `curl -s https://draw.harivan.sh/api/health` returns `{"ok":true,...}`.
- Sign in with Google and land on the dashboard; `j` outlines the first card,
  `cmd+k` opens the palette, `?` the key sheet, and the activity rail shows
  the last actions.
- Open a scene in two tabs: cursors and edits sync live.
- Set a scene to "can view", open it in a private window: renders read-only.
- `journalctl -u draw --since -10m` shows one line per request and no panics.
