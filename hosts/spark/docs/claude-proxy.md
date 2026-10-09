# Personal Claude account proxy

CLIProxyAPI is built from pinned source by `pkgs/claude-proxy/upstream.nix`.
The existing nix flake exposes `claude-proxy` (the configured launcher) and
`cli-proxy-api` (the underlying binary). Spark runs the launcher as the owner's
systemd user service. MacBook receives the launcher for access over SSH.
`devin-codex` remains independent.

## Apply and sign in

After this change is in the desired checkout, run `just switch-spark` from the
Mac, or `just switch` on Spark. Run `just switch` on the Mac to put the launcher
on PATH there; before that, `nix run .#claude-proxy -- …` works from this flake.

On the Mac, connect to Spark with the OAuth callback forwarded:

```sh
ssh -t -o ExitOnForwardFailure=yes -L 127.0.0.1:54545:127.0.0.1:54545 spark
systemctl --user start claude-proxy
claude-proxy login
```

Open the printed URL in a Mac browser and sign in to the first Max account.
Then run `claude-proxy login` again and sign in to the second account using a
different browser profile/private window or the account chooser. Do not send
tokens or callback codes through chat. The proxy stores separate credential
files by account identity; signing into the same account twice does not add
capacity. OAuth callbacks bind only to loopback (a small package patch).

```sh
claude-proxy status
claude-proxy models
systemctl --user status claude-proxy
```

`status` should show `running: true` and two different account entries. A model
list proves that the gateway is available, not that inference with both accounts
has succeeded. Perform a short real request through each account before treating
the setup as fully verified; the automated checks use fake local accounts.

## Use

On Spark:

```sh
claude-proxy claude
claude-proxy claude -- --resume
```

On the Mac, running Claude Code locally against Spark's account pool:

```sh
claude-proxy remote spark
claude-proxy remote spark -- --resume
```

The remote launcher creates an SSH forward on an available local port, retrieves the
gateway key through that SSH connection, and passes it only to the child process.
It closes its tunnel when that process exits. Each launcher uses its own local
port and SSH control socket, so several local Claude sessions can share Spark's
account pool concurrently.

The launcher sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and gateway hint
headers for that Claude process only. Normal `claude`, `cc`, `devin-codex`,
`co`, `com`, and `coh` behavior is unchanged. It does not patch Claude Code,
change its saved login, or disable its permission checks. Existing managed
provider policies can still restrict which endpoint Claude accepts.

Other clients can use `http://127.0.0.1:18473` as the Anthropic base URL, or
`http://127.0.0.1:18473/v1` for supported OpenAI-compatible interfaces. Read the
gateway key from `~/.local/state/claude-proxy/client-key` locally, or use
`claude-proxy key` deliberately in your own terminal. Keep it out of source,
shell history and logs. Supply a stable `x-claude-code-session-id` per
conversation when the client can send custom headers. Translation compatibility
with arbitrary clients needs separate testing.

## Runtime state and behavior

All private state lives under `$XDG_STATE_HOME/claude-proxy`, defaulting to
`~/.local/state/claude-proxy`:

- `accounts/`: mutable OAuth credentials and persisted cooldown files.
- `client-key`: randomly generated local API credential.
- `config.json`: runtime config combining store-owned settings and private state.

The directory is mode 0700; the key and generated config are mode 0600. Nix owns
the executable and nonsecret policy; secrets never enter the Nix store. A rebuild
preserves the client key and account files. Deleting this directory removes the
logins and invalidates client access.

Settings live in `pkgs/claude-proxy/default.nix`. They enable round-robin selection
for new conversations, 24-hour sticky affinity, subagent affinity, persisted
cooldowns and bounded credential attempts. There are no extra whole-pool retry
rounds and no stream-bootstrap retries. Upstream can fail over when an assigned
credential becomes unavailable. Account affinity is in memory: after a service
restart it may select a different account and incur a cold cache. The 24-hour
binding TTL does not extend Anthropic's prompt-cache TTL.

The listener is only `127.0.0.1:18473`. There is no public hostname, firewall rule,
management API, downloadable admin UI, plugin loader, dynamic model catalog,
or request/response body logging. Application access/error logs remain in the
user journal:

```sh
journalctl --user -u claude-proxy -n 50
systemctl --user restart claude-proxy
```

Keeping a stable conversation on one account improves prefix-cache reuse.
There is no KV-cache transfer between Max accounts. Credential pooling does not
turn Max into an officially supported general-purpose API product; see
[Anthropic's credential rules](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use).

## Validation and upgrades

```sh
nix build .#claude-proxy
nix build .#checks.aarch64-linux.claude-proxy
```

The check starts the actual packaged gateway against a local fake Anthropic
server with two credentials. It checks client authentication, disabled management,
new-session distribution, repeated-turn affinity, quota failover, cache marker
preservation, SSE forwarding and no second upstream attempt after partial output.
It also checks key persistence, private file modes and credential override cleanup.
It does not exercise subscription OAuth, real quota reset behavior, or paid inference.

To upgrade, update the version/source hash/vendor hash in `upstream.nix`, build
and run the check on the target platform, then rebuild. The package uses CGO=0;
dynamic plugins are unavailable. Review upstream v8 config changes when upgrading.
