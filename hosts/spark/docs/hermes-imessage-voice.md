# iMessage voice research

## Scope

The voice rules live in `dots/hermes/SOUL.md`. They apply only to replies to
Hari on Photon / iMessage. Markdown remains appropriate inside repository
files, PR descriptions and other document artifacts. The existing Nix service
already installs SOUL.md and includes it in its restart triggers; no new
plugin, formatter, service or scheduled work is needed.

## Public evidence

Researched September 6, 2026. There is no established benchmark here that proves
a particular iMessage prompt is state of the art. Product descriptions are not
system prompts, and a third-party prompt dump is not an authenticated release.

- [Poke's official site](https://poke.com/) presents an assistant reached through
  messaging, with integrations and scheduled tasks. This supports the choice of
  a conversational surface, not any claim about its private implementation.
- [Publicly attributed Poke guidelines](https://github.com/EliFuzz/awesome-system-prompts/blob/main/leaks/poke/2025-09-15_prompt_guidelines.md)
  describe adapting to a user's texting style, brief replies, avoiding preambles
  and generic help offers, and warmth and humor without forced slang or jokes.
  The filename dates the artifact to 2025-09-15. Authenticity and current use
  are unverified. These are design ideas, not instructions to execute or text
  to transplant wholesale.
- [Instinct's official site](https://instinct.com/) describes a personal
  assistant reached by text or calls, connected to applications and devices.
  It emphasizes understanding ongoing work and handling tasks without a new
  interface. Searches for an Instinct system prompt did not yield a verifiable
  public prompt. Continuity and result-first replies are our design inference,
  not a quotation of hidden Instinct instructions.
- [TechCrunch's reporting on Instinct](https://techcrunch.com/2026/08/24/instincts-powerful-ai-assistant-is-raising-privacy-and-security-concerns/)
  includes reports of unapproved email and data-retention concerns. Borrowing
  a conversational feel must not broaden authority or hide uncertainty.
- [Hermes personality documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/personality)
  identifies SOUL.md as the primary identity loaded from HERMES_HOME. It
  distinguishes voice from AGENTS.md's project and tool workflows.

The no-Markdown rule comes directly from Hari's report that formatting does
not render in his iMessage client, not from a claim about all Apple Messages
clients. It remains the desired style even if the adapter advertises Markdown
support. Do not patch upstream platform hints just to express this preference.

## Decisions

Use plain text, bare URLs, short paragraphs, contractions and a casual register.
Adapt without copying typos or adding performative slang. Keep ordinary replies
short, but allow detail when requested or necessary. Preserve exact technical
strings and attachment transport syntax. Put long artifacts in files or PRs.
Avoid helpdesk closers, formal correction speeches and per-tool narration.

Do not adopt the attributed Poke prompt's identity, private tool names, message
tags, concealment of internal agents, pronoun persona, or unlimited-capability
assumption. Do not copy Instinct's advertised proactive scope. Existing
verification, privacy, approval and request-only scheduling rules still apply.
Native approval polls remain governed by AGENTS.md; this change does not alter
the merge policy.

## Persistent approval preference

At Hari's explicit request, the same PR sets `approvals.mode = "off"` and
`security.protected_instruction_files = false` in the shared Hermes service
settings. This affects both Photon gateway and backend sessions using that
configuration, not just iMessage or one write. The first setting skips ordinary
command approvals; the second disables the separate always-ask gate for project
instruction files such as SOUL.md and AGENTS.md, which otherwise survives YOLO.
Neither setting is applied to the running agent while preparing this PR.

This trades approval friction for greater exposure to unintended commands and
persistent prompt-injection writes. The existing repo PR workflow, explicit
merge authorization, request scope, secret redaction, sensitive-path denies and
other hard guards are not removed. Approval-off is not blanket permission for
unrelated external actions. To restore the previous behavior, set the mode to
`"smart"` and the protected-instruction flag to `true` through a Nix PR.

References: [Hermes security documentation](https://hermes-agent.nousresearch.com/docs/user-guide/security)
and the pinned upstream `tools/approval_context.py` and
`tools/file_tools_write_guards.py`. The latter explicitly distinguishes the
normal approval gate from protected-instruction and sensitive-path guards.

## Acceptance examples

These are authored style fixtures, not captured model outputs or evidence that
a live deployment passed. Facts in them are hypothetical and must be verified
before an actual reply uses them.

| Situation | Desired reply shape |
| --- | --- |
| Greeting: "yo" | "yo"; no unsolicited offer of services |
| A corrected capability claim | "yeah, I missed that. the poll support is already there." |
| Finished PR | "opened the PR. checks passed; not merged yet." followed by its bare URL |
| Failed check | "the check failed on the Nix evaluation. I left the PR open." |
| Research uncertainty | "I found a public Poke prompt dump, but couldn't verify it's current. no verified Instinct prompt." |
| Technical command | A command on its own line, no backticks; preserve capitalization and symbols |
| Detailed explanation requested | Enough plain-text paragraphs to answer it; no arbitrary sentence cap |
| A document requested | Format the document normally; send a short plain-text attachment message |
| Approval needed | Existing native clarification poll, with the exact PR/head identified |

Pre-PR validation passed: `nix fmt -- --ci` (no changes), `git diff --check`,
Spark evaluation of the two approval settings and the SOUL.md delivery path,
and isolated Python assertions against the flake-pinned Hermes source. The
assertions loaded SOUL.md without alteration or truncation, read approval mode
as `off`, recognized the instruction-write opt-out and retained the `/etc/`
sensitive-path deny. The system Python environment's older installed Hermes did
not expose the pinned approval modules; validation used the pinned source on
PYTHONPATH with that environment's dependencies instead. No live configuration
was changed and no dangerous command was executed to test bypass behavior.

Before deployment: recheck the diff and Nix evaluation, and verify that the
pinned Hermes SOUL loader accepts the complete candidate in isolated state.
After deployment: try a greeting, a correction, a PR report with a URL, a
command containing underscores and a request for a detailed answer through
Photon. Inspect the actual iPhone rendering. Prompt-loading and static checks
do not prove model adherence or client rendering; do not report them as such.
