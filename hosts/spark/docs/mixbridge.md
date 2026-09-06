# Mixbridge streaming API

The web app authenticates users through their existing SoundCloud or Spotify
login and issues signed app sessions. A browser sends its HttpOnly session
cookie to `POST https://mixbridge.app/api/stream-token`; a native client sends
its session as a Bearer header. The response contains a five-minute stream token.
Clients send that token as `Authorization: Bearer <token>` to Spark's public
`https://mixbridge.harivan.sh` endpoint. This works per user across devices;
there is no shared client secret, machine account, or new authentication service.

Spark verifies RS256 signatures against the public keys at
`https://mixbridge.app/api/stream-jwks`. It requires `typ=at+jwt`, issuer
`https://mixbridge.app`, audience `mixbridge-stream`, scope `stream`, a subject
of `soundcloud:<id>` or `spotify:<id>`, and integer issuance/expiry timestamps
at most 300 seconds apart (15 seconds of clock tolerance). Unknown key IDs do
not force cache refreshes. Keys are cached for five minutes; an unavailable
issuer fails closed when no cached keys remain. Only `/health` is unauthenticated.

The signing private key and session secret belong only on the web host. Spark
needs no authentication secret; `mixbridge.env` still contains the existing
Spotify application credentials. CORS allows the two production web origins;
native clients use the same Bearer protocol. CORS is not the access control.

The API accepts public `https://soundcloud.com/<artist>/<track>` URLs (also
`www.soundcloud.com`), strips query/fragment data, and explicitly selects the
SoundCloud extractor. Short links, private tracks, playlists, arbitrary hosts,
HTTP, credentials, and nonstandard ports are rejected. Spotify accepts exact
track URLs or `spotify:track:<id>` identifiers; its audio search stays on YouTube.

One worker enforces 60 accepted requests per user per minute, two concurrent
requests per user, and four overall. These are conservative initial limits,
not measured capacity. Keep one worker unless the limiter is replaced. Downloads
are capped at 50 MiB before conversion and before returning the result; individual
network operations time out after 15 seconds with two retries. This does not
provide a total extraction deadline. The systemd unit runs as a dynamic user
with a private temporary directory, 1 GiB memory cap, and 128-task cap.

## Rollout

1. Deploy [web PR #1](https://git.harivan.sh/harivansh-afk/mixbridge-web/pulls/1)
   with the private environment values described in its `docs/stream-auth.md`.
   Verify JWKS contains only public RSA fields. A browser session must be signed;
   old unsigned cookies require login again.
2. Release [iOS PR #3](https://git.harivan.sh/harivansh-afk/mixbridge-ios/pulls/3).
   Old Spotify marker sessions require login again. Verify a real SoundCloud
   and Spotify login, token exchange, and playback with the updated client.
3. Merge and deploy this API change only once updated clients are available.
   Confirm anonymous extraction returns 401, authenticated extraction works,
   and the service has `DynamicUser=yes`. Old clients will receive 401.

The current JWKS endpoint publishes one key. Replacing it can interrupt requests
until caches refresh and clients obtain new tokens. Seamless rotation would
require overlapping public keys; do not claim this single-key version supports it.
App sessions last up to 30 days and lack per-session server revocation. Rotating
the session secret signs everyone out; existing stream tokens survive for their
remaining five-minute lifetime. Broader Convex authorization is a separate audit:
this change protects the extraction API, not every public backend action.

`nix build .#checks.aarch64-linux.mixbridge` tests authentication, URL validation,
CORS, rate/concurrency limits and download bounds without network calls. The
same tests can run with the pinned runtime dependencies from `setup.sh` through
`uv run --with ... python hosts/spark/services/mixbridge/test_api.py`.
