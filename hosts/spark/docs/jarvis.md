# Jarvis on Spark

Jarvis runs as `rathi`, binds to `127.0.0.1:19743`, and uses the same Mux
package as `muxd.service`. Mux remains the PTY owner. Jarvis reads its current
screens and sends input through its checked-write API; it does not attach a
second terminal reader or restart terminals.

State lives in `/var/lib/jarvis` with mode 0700. The browser login token is
`/var/lib/jarvis/access-token` (0600). Open localhost on Spark, or forward it
from the Mac with `ssh -L 19743:127.0.0.1:19743 spark` and open
`http://localhost:19743`. This also gives the browser a secure localhost
context for microphone access. Phone use needs a separate HTTPS access path.

Local inspection, following terminals, Linux load/memory/pressure observations
and explicit input work without an OpenAI key. Voice is disabled until a project
key is configured with `services.jarvis.openaiKeyFile` or a runtime environment
file. Keep that key outside Git and the Nix store. The default voice model is
`gpt-live-1`, with managed `gpt-6-astra` reasoning at low effort. Actual model
access and a spoken tool round trip still need testing against the project.

The private Jarvis flake is fetched through a repository-scoped, read-only SSH
deploy key encrypted in SOPS. Only root and the Actions runner select it through
the `jarvis-source` alias; interactive user fetches retain the user's identity.
The alias pins Spark's SSH host key. A fresh machine needs its secret activated
before fetching private source; a pinned source already copied into the Nix
store can bootstrap the first switch. Jarvis is also in the declarative Actions
allowlist.

Validate with `nix flake check`, then merge through Forgejo and inspect the
`deploy` workflow. After activation, check `systemctl status jarvis`,
`curl http://127.0.0.1:19743/healthz`, authenticated terminal inventory, and a
disposable terminal input round trip. Mux upgrades must use its normal reload
handoff; restarting `muxd` loses its live PTYs.
