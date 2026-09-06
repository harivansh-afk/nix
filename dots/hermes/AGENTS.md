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

Share the PR link, short summary and check status. Routine skill-only PRs may
merge after green checks unless Hari requests review. Broader changes need scoped
authorization. When asking, use `clarify` with Merge / Keep open choices: Photon
renders them as native iMessage polls. Include the PR number and short head SHA
in each choice so a delayed vote identifies its change. Allow one pending merge
question at a time. If clarification is unavailable, expires or fails, leave the
PR open and share its link for review; never treat a timeout as approval or ask
Hari to type approval codes. Recheck the approved head and CI before merging;
a changed head needs a fresh decision. Respect branch protection, never force
merge, and report merge, deployment and runtime proof separately.
