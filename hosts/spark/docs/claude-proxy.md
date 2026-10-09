# Claude account gateway

The CLI and pinned CLIProxyAPI now live in
[cc-proxy](https://git.harivan.sh/harivansh-afk/cc-proxy). This flake imports its
package and checks; the Spark user service remains `claude-proxy.service`.

```sh
cc                     # launch Claude
cc --resume
cc claude --model opus # explicit form
cc ls                  # accounts, including Fable, with usage bars
cc usage --refresh
cc usage --json
cc login
cc status
```

`cc` is an interactive alias for `cc-proxy`; `command cc` still invokes the C
compiler. Mac commands default to Spark over SSH; Linux commands default to
local. Override with `--host` or `CC_PROXY_HOST`. The `cbridge` and `claude-proxy`
executables remain compatibility aliases.

Spark listens only on `127.0.0.1:18473`. The Mac launcher opens a private SSH
tunnel and runs Claude locally. Account commands retrieve sanitized JSON and
render it on the calling machine. Login forwards OAuth callback port 54545.
Credentials stay in `~/.local/state/claude-proxy/accounts`; rebuilds and this
migration preserve them, the client key, and cooldown records.

The upstream gateway owns OAuth refresh, sticky account routing and streaming.
An existing Claude process already using the gateway can fail over between
accounts without restarting. Transparent failover ends when response output
begins; partial streams are never replayed. Restarting the gateway itself can
interrupt an active response. A Fable-specific limit does not exhaust other
models. Details and tests live in the source repo's
[usage notes](https://git.harivan.sh/harivansh-afk/cc-proxy/src/branch/main/docs/usage-semantics.md).

## Deploy and update

```sh
nix flake update cc-proxy
nix build .#cc-proxy .#checks.aarch64-linux.claude-proxy
just switch-spark
just switch
```

Run the rebuilds on the Mac; restart the shell to pick up its alias. Both machines
need the new package for remote commands. Nix owns the package and service,
never the account credentials. Claude's own Nix-generated settings remain
read-only; `/model` changes the current session but cannot save a new default.

```sh
systemctl --user status claude-proxy
journalctl --user -u claude-proxy -n 50
```

A running service or successful model list proves reachability, not available
quota. `cc ls` shows quota; a real request establishes inference for that account.
