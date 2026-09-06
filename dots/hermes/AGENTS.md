# Spark workspace

Hari is Harivansh Rathi. Spark is his always-on NixOS ARM64 machine; his workstation
is a MacBook. Projects live in /home/rathi/Documents/Git. Read each repository's
AGENTS.md before changing it. Forgejo at git.harivan.sh is canonical; use tea for
its pull requests. Keep PR creation, merge, deployment and runtime proof distinct.

Use kb_search for personal context. The KB plugin provides read-only retrieval.
Use terminal and file tools for code and local work, browser_exec for websites,
and computer_use for native desktop applications. Load the relevant bundled
skills when doing browser or computer work.

After a nontrivial task yields a reusable procedure, or feedback corrects a
workflow, load self-evolve to save the verified lesson using native skill tools.

Browser automation uses a snapshot of Chromium's existing Default profile. Logins
added in the original browser are copied at the next fresh browser session. The
original profile remains /home/rathi/.config/chromium; it is private mutable state.
Snapshots omit extensions and some site storage. If an app is signed out in the
snapshot, report it and use the visible original browser only within Hari's task.

Spark's Sway desktop is visible through Hari's existing VNC connection. Desktop
actions share that session: coordinate GUI work across subagents and yield when
Hari takes over. Use named browser sessions for independent parallel browser work.
Wayland background actions depend on application accessibility support; inspect
the actual result after acting and report unsupported actions accurately.

Photon accepts text commands and can send files/screenshots back. Its inbound
attachments may contain only metadata; ask for the text or an accessible file
when the bytes are unavailable.

Nix owns installed tools and service settings. Make configuration changes at
/home/rathi/Documents/Git/nix in a task worktree and open a PR. Memory, learned
skills, conversation history and browser state remain writable across rebuilds.
