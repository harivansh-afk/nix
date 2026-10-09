# Claude account bridge

`cbridge` launches Claude Code through the private CLIProxyAPI gateway on Spark
and reports account usage. The interactive zsh alias `cc` points to `cbridge`;
`command cc` still invokes the C compiler, and build scripts are unaffected.
Plain `claude` continues to use its normal login. The old `claude-proxy` executable
and `remote HOST` command remain available for compatibility.

## Daily use

```sh
cc claude
cc claude --resume
cc claude --model claude-opus-5-5
cc ls
cc usage
cc usage --json
cc status
cc models
watch -n 60 cbridge ls
```

`ls` prints each account with ASCII five-hour and weekly usage bars, reset times,
active cooldowns, and the time the usage was checked. Times include the selected
host's timezone. `usage` additionally shows
any model-specific windows returned by Anthropic and whether extra usage is
enabled. Percentages are **used**, not remaining. These come from Anthropic's
OAuth usage endpoint, not estimated token counts. A missing percentage is
`unknown`; failed refreshes retain previous data with an explicit `stale` label.
Usage snapshots and failed attempts are cached for 60 seconds. Use `--refresh`
to bypass this cache. No prompt or response content is collected.

Account states:

- `eligible`: no known quota block; this does not guarantee inference will work.
- `cooling`: the gateway has an active account-wide cooldown.
- `limited`: one or more models have active cooldowns.
- `exhausted`: a current five-hour or weekly allowance is exhausted, without
  confirmed extra usage enabled.
- `unknown`: usage or cooldown information could not be read reliably.
- `disabled`: the credential is disabled; usage is not fetched.

`status` also probes the gateway. A running gateway and a nonempty model list do
not prove that any account has capacity. Changing models cannot bypass an
account-wide limit. A pool with one account has no fallback account.

Commands print a snapshot and exit, with no terminal control sequences or color.
`ls`, `usage`, `status`, and `models` accept `--json`; diagnostics go to stderr.
Exit codes are 0 for a successful query (including known exhausted accounts),
1 for unavailable/incomplete data or an unreachable gateway, and 2 for invalid
arguments. Claude's exit status is preserved; signal exits use 128 + signal.
Global options precede the subcommand. Everything after `claude` is passed to
Claude verbatim (an optional leading `--` is removed).

## Host selection

On macOS, the default host is `spark`; on Linux it is `local`. Override with
`CBRIDGE_HOST` or `--host`:

```sh
cbridge --host spark ls
cbridge --host spark usage --json
cbridge --host local status
cbridge --host spark claude --resume
```

The Mac runs Claude locally through its own SSH tunnel to Spark's
`127.0.0.1:18473`. The launcher retrieves the gateway key over SSH, puts it only
in the child environment, and closes the tunnel when Claude exits. Concurrent
launches use separate local ports and SSH control sockets. Read commands run on
the selected host over SSH, so OAuth tokens remain on that host. Both hosts need
the updated package for remote account commands.

`--state-dir PATH` selects a different state directory on the selected host.
The service uses the default state directory and always runs locally; `serve`
rejects a remote host override. The gateway port is fixed at 18473 by Nix.

## Install and sign in

After merging, run `just switch-spark` on the Mac to deploy Spark and `just switch`
to install the Mac launcher. Start a new shell for the updated `cc` alias. Before
installation, `nix run .#cbridge -- --help` runs the new command from this flake.

From the Mac:

```sh
cbridge login
```

This opens an SSH session and forwards the OAuth callback at
`127.0.0.1:54545`. Open the printed URL in your browser and complete login. Repeat
with a different account to add capacity; logging into the same account again
does not add capacity. Do not send tokens or callback codes through chat.

On Spark directly:

```sh
systemctl --user start claude-proxy
cbridge login
```

When using a browser on another machine, forward port 54545 over SSH. The
packaged upstream has a small patch binding its OAuth callback to loopback.
After login, check `cc ls --refresh`. Perform a real request before treating a
new account as verified; the automated tests use fake credentials.

## Runtime and routing

CLIProxyAPI is pinned in `pkgs/claude-proxy/upstream.nix`. The flake exposes
`cbridge`, its compatibility alias `claude-proxy`, and the underlying
`cli-proxy-api` package. Spark runs `claude-proxy.service` as the owner's systemd
user service. `devin-codex` is independent.

Private state remains under `$XDG_STATE_HOME/claude-proxy`, defaulting to
`~/.local/state/claude-proxy`:

- `accounts/`: OAuth credentials and upstream `.cds` cooldown records.
- `client-key`: gateway API credential.
- `config.json`: generated nonsecret policy combined with private state.
- `usage/`: sanitized usage cache and lock files (no OAuth tokens).

Private directories are mode 0700; key, config, and usage-cache files are mode
0600. Rebuilds preserve this state. The upstream owns token refresh; the usage
reader never rewrites credentials. `key` deliberately prints the gateway key for
manual integrations. Keep it out of source, shell history, and logs.

The launcher sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and gateway hint
headers only for its Claude child and removes conflicting provider credentials.
It does not patch Claude Code or change its login or permission settings. The
Nix-owned Claude settings remain read-only; `/model` can select a model for a
session but cannot save that selection as the default.

Routing policy in `pkgs/claude-proxy/default.nix` retains round-robin selection
for new conversations, 24-hour conversation/subagent affinity, persisted
cooldowns, and bounded credential attempts. No extra whole-pool retry rounds or
stream-bootstrap retries are added. Upstream can fail over when a credential
becomes unavailable. Affinity is in memory and can change after a restart; its
24-hour binding does not extend Anthropic's prompt-cache lifetime. There is no
KV-cache transfer between accounts.

The gateway remains loopback-only, with no public hostname, management API,
admin UI, plugin loader, dynamic model catalog, or request/response body logging.
Application access/error logs are in the user journal:

```sh
journalctl --user -u claude-proxy -n 50
systemctl --user restart claude-proxy
```

Other clients can use `http://127.0.0.1:18473` as their Anthropic base URL or
`http://127.0.0.1:18473/v1` for supported OpenAI-compatible interfaces, with the
gateway key. Supply a stable `x-claude-code-session-id` per conversation when
possible. Compatibility with arbitrary clients needs separate testing.
Credential pooling does not turn Max into an officially supported general API;
see [Anthropic's credential rules](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use).

## Validation and upgrades

```sh
nix build .#cbridge
nix build .#checks.aarch64-linux.claude-proxy
```

The check exercises the packaged gateway against a fake Anthropic server:
client authentication, disabled management, new-session distribution, repeated
turn affinity, quota failover, cache markers, SSE forwarding, and no retry after
partial output. CLI tests cover usage parsing, private caching, stale and unknown
usage, cooldown scopes, argument forwarding, SSH quoting, exit codes, and cleanup.
They do not exercise real subscription login, inference, or quota reset behavior.

To upgrade, update the version/source hash/vendor hash in `upstream.nix`, run the
check on the target platform, then rebuild. Review upstream v8 config changes.
