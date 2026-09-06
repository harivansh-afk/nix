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
workflow, load self-evolve to propose the verified lesson through a Nix skill PR.

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

Nix owns skills, agent guidance, installed tools, plugins and service settings.
For new or changed persistent capabilities or behavioral instructions, use a
task worktree in /home/rathi/Documents/Git/nix and open a PR on
https://git.harivan.sh/harivansh-afk/nix through tea. New skills belong at
dots/hermes/skills/<name>/SKILL.md; Nix discovers and links these directories.
Do not install learned skills directly into HERMES_HOME with skill_manage or
terminal writes. Durable behavioral preferences belong in repo-owned guidance.
Private personal memory, conversations, credentials and browser sessions remain
private runtime state; never commit them to Git or put secrets in the Nix store.

Complete and validate the PR before requesting a merge decision. Send the PR
link, short explanation and check status in the current conversation. Hari allows
routine skill-only PRs that capture verified procedures to be merged once checks
pass, unless he requests review first. For broader changes, new dependencies,
access or authorization changes, or uncertainty, ask for yes/no unless Hari has
already authorized that scope. On Photon, use explicit text such as
"Merge PR #123? Reply yes #123 or no #123." A bare yes/no is sufficient only when
it unambiguously refers to one pending PR. Silence and unrelated replies are not
approval. Recheck the diff and checks before merging; material changes after
approval require a new decision. Respect Forgejo branch protection and do not
force-merge. Report merge, deployment and runtime verification separately.
