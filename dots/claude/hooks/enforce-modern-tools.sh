#!/usr/bin/env python3
"""PreToolUse(Bash) guard: steer toward rg/fd, without false positives.

Ported from indexable-inc/ix .claude/hooks/enforce-modern-tools.sh (the
tokenizing version), trimmed to the global rules (grep -> rg, find -> fd);
repo-specific policies (cargo, git checkout) belong to repo hooks.

The previous regex version substring-matched the whole command string, so the
word `find` inside a heredoc, a quoted pattern, or a commit message was denied
as if it were the command being run. Transcript analysis across 916 sessions
counted 833 modern-tools denials with ~26% false positives of exactly that
shape; each one burns a full model round trip.

Detection tokenizes the command with shlex (quote- and operator-aware) and
inspects only tokens in "command position": the first word, the word after a
shell separator (| || & && ; ( ), and the word a wrapper (sudo/env/xargs/...)
defers to. Heredoc bodies are stripped first: they are data, and their
punctuation would otherwise fabricate command positions.

A repo that ships its own enforce-modern-tools hook owns this policy; defer to
it so a single (better-scoped) denial is issued instead of two.
"""

import json
import os
import re
import shlex
import sys

PUNCT = set("();<>|&")
WRAPPERS = {
    "sudo", "doas", "env", "xargs", "time", "nice",
    "nohup", "command", "stdbuf", "setsid", "ionice", "chrt",
}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC = re.compile(r"<<-?\s*(?:'(\w+)'|\"(\w+)\"|\\?(\w+))")


def deny(reason: str) -> None:
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    sys.exit(0)


def strip_heredocs(cmd: str) -> str:
    """Drop heredoc bodies (and their delimiter lines) from the command text."""
    out_lines = []
    pending = []  # (delimiter, allows_tab_indent), in body order
    for line in cmd.split("\n"):
        if pending:
            delim, dash = pending[0]
            candidate = line.lstrip("\t") if dash else line
            if candidate == delim:
                pending.pop(0)
            continue
        for m in HEREDOC.finditer(line):
            delim = next(g for g in m.groups() if g)
            dash = line[m.start() : m.end()].startswith("<<-")
            pending.append((delim, dash))
        out_lines.append(line)
    return "\n".join(out_lines)


def op_kind(tok: str):
    """'sep' introduces a new command; 'redir' is followed by a filename."""
    if tok and all(c in PUNCT for c in tok):
        return "redir" if ("<" in tok or ">" in tok) else "sep"
    return None


def command_indices(tokens):
    """Indices of tokens that are in command position."""
    out, expect = [], True
    for i, tok in enumerate(tokens):
        kind = op_kind(tok)
        if kind == "sep":
            expect = True
            continue
        if kind == "redir":
            expect = False  # next token is a redirect target, not a command
            continue
        if not expect:
            continue
        if ASSIGN.match(tok):  # leading FOO=bar env assignment
            continue
        if tok.startswith("-"):  # option to a wrapper (e.g. sudo -u foo)
            continue
        out.append(i)
        base = tok.rsplit("/", 1)[-1]
        expect = base in WRAPPERS  # keep scanning past sudo/env/xargs/...
    return out


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)
    cmd = payload.get("tool_input", {}).get("command", "")
    if not cmd:
        sys.exit(0)

    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if project_dir and os.access(
        os.path.join(project_dir, ".claude", "hooks", "enforce-modern-tools.sh"),
        os.X_OK,
    ):
        sys.exit(0)

    cmd = strip_heredocs(cmd)

    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        # Unbalanced quotes etc. -- the shell would reject it too; allow.
        sys.exit(0)

    for i in command_indices(tokens):
        base = tokens[i].rsplit("/", 1)[-1]
        if base == "grep":
            deny("Use rg (ripgrep) instead of grep.")
        if base == "find":
            deny("Use fd instead of find.")

    sys.exit(0)


if __name__ == "__main__":
    main()
