# com-computer

`com-computer` runs the existing `com` workflow with a separate Linux desktop.
Codex and Devin inference stay on Spark. The desktop runs in a rootless Podman
container; Cua Spaces on the Mac is its viewer.

## Use

On Spark, from the project you want to work on:

```sh
com-computer
com-computer --name website
com-computer --name website -- resume
com-computer --name website -- exec "Check the homepage in the task browser"
```

Without `--name`, each invocation creates a new name and prints it. Reusing a
name reopens its desktop and original project directory. Codex arguments follow
`--`; `-C`/`--cd` selects the project on first creation. A saved desktop remains
bound to that project. `resume` is Codex's conversation picker; desktop names
and Codex conversation IDs are separate.

On the Mac:

```sh
com-computer list
com-computer view website
```

The viewer command opens an SSH tunnel over the existing Spark connection,
registers `com/website` in Cua Spaces, and opens the app. Select that entry to
watch or control it. Closing the viewer does not stop Codex. If the Mac was off
when the task started, run the same command when it comes back online.

On Spark:

```sh
com-computer list
com-computer stop website
com-computer delete website
```

Closing Codex stops the container and retains its files and browser profiles.
`stop` handles a desktop left running after an interrupted launcher; it refuses
while another launcher owns the desktop. `delete` removes a stopped desktop,
including its browser logins and downloaded files. It leaves the host project
and Codex history alone. After a host reboot, reopen the named desktop normally.
There is no automatic deletion of old desktops.

## Accounts and files

Each desktop starts with the apps in the pinned Cua Linux image, including
Chromium and Firefox. It has its own home directory. It does not inherit the
personal Spark browser's cookies, passwords, extensions or keyring.

The session guidance tells Codex to use the persistent Cua browser profile
named `work`. Sign into that browser through Spaces when needed. Reopening the
same desktop preserves that profile. Its credentials stay in private runtime
storage and the container, outside Git and the Nix store.

The selected host project is mounted read/write at `/workspace`. Files edited
there are the same files Codex edits on Spark. Two desktops pointed at the same
project therefore share those project files; use separate Git worktrees for
independent code changes. Other host home directories and credentials are not
mounted. A web server bound to Spark's localhost is reachable from the task
browser at `http://host.containers.internal:PORT`.
Starting from the host home directory or one of its ancestors is refused;
choose a project directory, or pass `-C /path/to/project`.

## Isolation and lifetime

Each desktop has a separate X11 display, application state, authenticated MCP
endpoint and loopback port. An exclusive file lock prevents two launchers from
using the same named desktop. Different names can run concurrently; subagents
within one Codex session share that session's desktop and must coordinate GUI
input. This is desktop isolation, not a sandbox for Codex's host shell/files.
Pause Codex before taking over through the viewer: you and the agent share
focus within that desktop. Saved files and persistent profiles survive a stop;
unsaved application buffers do not.

Each container is limited to two CPU cores and 4 GiB RAM, with 1 GiB of shared
memory for browsers. The pinned image is approximately 1.2 GB to download and
3 GB unpacked; its base layers are shared between desktops. Stopped desktops
retain disk state but do not run background processes. Abruptly killing the
launcher with SIGKILL can leave a container running: use `list` and `stop`.

The launcher invokes `devin-codex run --reasoning-effort medium` with the same
Git common-directory trust rule as `com`. Its supported `--codex` option selects
a small shim. Model-catalog queries pass through unchanged; the actual Codex
launch gets a private process and a task-specific HTTP MCP configuration. The
ordinary host `computer` MCP is disabled only for this invocation. Devin
provider/model configuration, its mutable profile, and normal `com` remain in
place. No Devin or Codex credentials are copied into the desktop.

Task state lives under `$XDG_STATE_HOME/com-computer` (normally
`~/.local/state/com-computer`), with private permissions. The Mac stores its
SSH tunnel metadata there and Cua stores the registered connection credentials
in its own private runtime state. The Mac app is pinned by Nix. No hosted relay
or Cua account is required.

## Implementation and validation

- `pkgs/com-computer/`: launcher, per-session guidance and lifecycle tests.
- `pkgs/cua-cli/`: pinned upstream CLI, used for readiness checks.
- `pkgs/cua-spaces/` and `hosts/macbook/cua-spaces.nix`: Mac app packaging.
- `hosts/spark/services/desktop.nix`: installs the launcher alongside the
  existing Sway/VNC desktop. Its compositor, browser and services are unchanged.

```sh
uv run --no-project python pkgs/com-computer/test_computer.py
nix build .#checks.aarch64-linux.com-computer
nix build .#com-computer
```

Live acceptance additionally checks a real Devin/Codex MCP screenshot, two
concurrent desktop targets, refusal of a second owner for one name, project
file ownership, localhost preview access, browser-profile persistence, exit
cleanup, and the Mac viewer. Unit tests do not prove those runtime paths.

References: [Codex MCP configuration](https://developers.openai.com/codex/mcp),
[Cua agent connections](https://cua.ai/docs/spaces/guides/use-from-an-agent),
[Cua Spaces](https://spaces.cua.ai/). The companion uses the same SSH host
configuration declared in `dots/ssh/config`.
