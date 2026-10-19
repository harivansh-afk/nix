import asyncio
import json
import os
import tempfile
import time

from mcp.server.fastmcp import Context, FastMCP

STALL_SECONDS = int(os.environ.get("CODEX_MCP_STALL_SECONDS", "1200"))
HEARTBEAT_SECONDS = 30

mcp = FastMCP(
    "codex",
    instructions=(
        "Codex is a capable coding agent that shares this machine and checkout. "
        "Delegate substantial work with `codex`: implementation, debugging, research, "
        "a second opinion. Codex starts with none of your context, so the prompt states "
        "the goal, relevant paths, constraints, what done looks like, and what to report. "
        "Long calls move to the background and their result arrives as a task "
        "notification, so start parallel tasks in one message and keep working. "
        "Continue a thread with `codex_reply`. Verify Codex's claims before relying on them."
    ),
)


def describe(event):
    item = event.get("item") or {}
    kind = item.get("type")
    if kind == "command_execution":
        return f"ran {item.get('command', '')}"[:200]
    if kind == "file_change":
        return "edited " + ", ".join(c.get("path", "") for c in item.get("changes", []))
    if kind == "agent_message":
        return item.get("text", "")[:200]
    return event.get("type", "")


async def run_codex(args, prompt, ctx):
    with tempfile.NamedTemporaryFile(prefix="codex-mcp-", suffix=".txt", delete=False) as f:
        last_message = f.name
    proc = await asyncio.create_subprocess_exec(
        "codex", "exec", *args, "--json", "--skip-git-repo-check", "-o", last_message, "-",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        limit=16 * 1024 * 1024,
    )
    proc.stdin.write(prompt.encode())
    proc.stdin.close()
    stderr = asyncio.create_task(proc.stderr.read())

    thread_id, status, errors = None, "failed", []
    files, commands, events = set(), 0, 0
    last_event = time.monotonic()
    try:
        while True:
            try:
                line = await asyncio.wait_for(proc.stdout.readline(), HEARTBEAT_SECONDS)
            except asyncio.TimeoutError:
                idle = time.monotonic() - last_event
                if idle > STALL_SECONDS:
                    status = "stalled"
                    errors.append(f"no Codex events for {int(idle)}s; stopped")
                    break
                await ctx.report_progress(events, message=f"working, quiet for {int(idle)}s")
                continue
            if not line:
                break
            last_event = time.monotonic()
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            events += 1
            kind = event.get("type")
            item = event.get("item") or {}
            if kind == "thread.started":
                thread_id = event.get("thread_id")
            elif kind == "turn.completed":
                status = "completed"
            elif kind in ("turn.failed", "error"):
                errors.append(json.dumps(event.get("error") or event.get("message") or event)[:500])
            if kind == "item.completed":
                if item.get("type") == "file_change":
                    files.update(c.get("path", "") for c in item.get("changes", []))
                elif item.get("type") == "command_execution":
                    commands += 1
            await ctx.report_progress(events, message=describe(event))
    finally:
        if proc.returncode is None:
            proc.terminate()
            try:
                await asyncio.wait_for(proc.wait(), 10)
            except asyncio.TimeoutError:
                proc.kill()
                await proc.wait()

    err = (await stderr).decode(errors="replace").strip()
    if status != "completed" and err:
        errors.append(err[-2000:])
    try:
        with open(last_message) as f:
            final = f.read().strip()
    finally:
        os.unlink(last_message)

    lines = [f"status: {status}", f"thread_id: {thread_id}", f"commands run: {commands}"]
    if files:
        lines.append("files changed: " + ", ".join(sorted(files)))
    lines += [f"error: {e}" for e in errors]
    lines += ["", final or "(Codex returned no final message)"]
    return "\n".join(lines)


@mcp.tool()
async def codex(prompt: str, ctx: Context) -> str:
    """Start a Codex agent on a task in the current checkout and return its final report."""
    return await run_codex([], prompt, ctx)


@mcp.tool()
async def codex_reply(thread_id: str, prompt: str, ctx: Context) -> str:
    """Send a follow-up to an earlier Codex thread and return its final report."""
    return await run_codex(["resume", thread_id], prompt, ctx)


if __name__ == "__main__":
    mcp.run()
