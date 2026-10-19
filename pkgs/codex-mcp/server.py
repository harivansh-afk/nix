import asyncio
import json
import os
import signal

from mcp.server.fastmcp import Context, FastMCP

STALL_SECONDS = int(os.environ.get("CODEX_MCP_STALL_SECONDS", "1200"))

mcp = FastMCP(
    "codex",
    instructions=(
        "Codex is a capable coding agent on this machine, working in this checkout. "
        "Delegate substantial work to it with `codex`. It starts with none of your "
        "context: state the goal, relevant paths, constraints, what done looks like, "
        "and what to report. Calls run in the background and return as task "
        "notifications, so start parallel tasks in one message and keep working. "
        "Continue a thread with `codex_reply`. Verify its claims before relying on them."
    ),
)


async def run_codex(args, prompt, ctx):
    proc = await asyncio.create_subprocess_exec(
        "codex", "exec", *args, "--json", "--skip-git-repo-check", "-",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
        limit=16 * 1024 * 1024,
        start_new_session=True,
    )
    proc.stdin.write(prompt.encode())
    proc.stdin.close()

    thread_id, status, message, events = None, "failed", "", 0
    try:
        while True:
            try:
                line = await asyncio.wait_for(proc.stdout.readline(), STALL_SECONDS)
            except asyncio.TimeoutError:
                status = f"stalled: no Codex events for {STALL_SECONDS}s"
                break
            if not line:
                break
            event = json.loads(line)
            item = event.get("item", {})
            thread_id = event.get("thread_id", thread_id)
            if item.get("type") == "agent_message":
                message = item["text"]
            if event["type"] == "turn.completed":
                status = "completed"
            if event["type"] in ("turn.failed", "error"):
                message = json.dumps(event)
            events += 1
            await ctx.report_progress(events, message=item.get("type") or event["type"])
    finally:
        if proc.returncode is None:
            os.killpg(proc.pid, signal.SIGKILL)
            await proc.wait()

    return f"status: {status}\nthread_id: {thread_id}\n\n{message}"


@mcp.tool()
async def codex(prompt: str, ctx: Context) -> str:
    """Start a Codex agent on a task and return its final report."""
    return await run_codex([], prompt, ctx)


@mcp.tool()
async def codex_reply(thread_id: str, prompt: str, ctx: Context) -> str:
    """Send a follow-up to an earlier Codex thread and return its final report."""
    return await run_codex(["resume", thread_id], prompt, ctx)


if __name__ == "__main__":
    mcp.run()
