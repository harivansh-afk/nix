"""Run production Hermes/model turns against isolated, deterministic workspace tools."""

import argparse
import atexit
import hashlib
import json
import os
import shutil
import sys
import threading
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--settings",
        type=Path,
        required=True,
        help="Nix-evaluated Hermes settings JSON",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="New private directory outside the repository",
    )
    parser.add_argument(
        "--auth",
        type=Path,
        required=True,
        help="Existing Hermes auth.json; copied without logging",
    )
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument(
        "--scenario",
        choices=[
            "greeting",
            "handoff",
            "long-history",
            "summary",
            "correction",
            "capacity",
        ],
        default="handoff",
    )
    args = parser.parse_args()
    if args.baseline and args.scenario == "summary":
        parser.error("The summary scenario requires the conversation plugin")
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    if output.is_relative_to(root):
        parser.error(
            "Evaluation state and credentials must stay outside the repository"
        )
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    home = output / "home"
    home.mkdir(mode=0o700)
    shutil.copyfile(args.auth, home / "auth.json")
    (home / "auth.json").chmod(0o600)
    atexit.register((home / "auth.json").unlink, missing_ok=True)
    (home / ".no-bundled-skills").touch()
    workspace = output / "workspace"
    workspace.mkdir()
    for name in ("SOUL.md", "AGENTS.md"):
        shutil.copyfile(
            root / "dots/hermes" / name,
            (home if name == "SOUL.md" else workspace) / name,
        )
    config = json.loads(args.settings.read_text())
    config.update(
        {
            "mcp_servers": {},
            "gateway": {},
            "platforms": {},
            "terminal": {"cwd": str(workspace)},
            "memory": {"memory_enabled": False, "user_profile_enabled": False},
            "skills": {
                "external_dirs": [],
                "project_discovery": False,
                "creation_nudge_interval": 0,
            },
            "platform_toolsets": {"photon": ["delegation", "evaluation"]},
        }
    )
    if args.baseline:
        config["plugins"] = {"enabled": []}
        config["context"] = {"engine": "compressor"}
    else:
        plugins = home / "plugins"
        plugins.mkdir()
        (plugins / "nix-managed-hermes-conversation").symlink_to(
            Path(__file__).resolve().parent / "hermes_conversation"
        )
    (home / "config.yaml").write_text(json.dumps(config))
    os.environ["HERMES_HOME"] = str(home)
    os.environ["HERMES_DISABLE_TELEMETRY"] = "1"
    os.chdir(workspace)

    from hermes_cli.plugins import PluginContext, PluginManifest, get_plugin_manager
    from hermes_cli.runtime_provider import resolve_runtime_provider
    from hermes_state import SessionDB
    from run_agent import AIAgent
    from tools.registry import registry

    started = threading.Event()
    release = threading.Event()
    effects = []
    calls = []
    records = {
        "courses": ["physics-quiz", "writing-draft", "math-exam"],
        "physics-quiz": {"due": "2026-09-08", "topic": "momentum", "submitted": False},
        "writing-draft": {
            "due": "2026-09-07",
            "topic": "argument outline",
            "submitted": False,
        },
        "math-exam": {"due": "2026-09-11", "topic": "derivatives", "submitted": False},
    }

    def read_workspace(arguments, **kwargs):
        path = arguments["path"]
        effects.append({"path": path, "time": time.monotonic()})
        if args.scenario in {"handoff", "correction"}:
            started.set()
            release.wait(timeout=75)
        data = records.get(path)
        if path in ("AGENTS.md", str(workspace / "AGENTS.md")):
            data = (workspace / "AGENTS.md").read_text()
        return json.dumps({"path": path, "data": data, "read_only": True})

    registry.register(
        name="workspace_read",
        toolset="evaluation",
        schema={
            "name": "workspace_read",
            "description": "Read the course workspace. Start with path 'courses', then read each returned record ID. Read-only.",
            "parameters": {
                "type": "object",
                "properties": {"path": {"type": "string"}},
                "required": ["path"],
            },
        },
        handler=read_workspace,
    )
    manager = get_plugin_manager()
    manager.discover_and_load()

    def observe(request, next_call, **context):
        entry = {
            "platform": context.get("platform"),
            "model": request.get("model"),
            "reasoning": request.get("reasoning", request.get("reasoning_effort")),
            "tool_choice": request.get("tool_choice"),
            "tools": [
                t.get("function", t).get("name") for t in request.get("tools", [])
            ],
            "input_chars": len(
                json.dumps(request.get("input", request.get("messages", [])))
            ),
            "instructions_chars": len(request.get("instructions", "")),
        }
        calls.append(entry)
        began = time.monotonic()
        response = next_call(request)
        entry["seconds"] = round(time.monotonic() - began, 3)
        usage = getattr(response, "usage", None)
        entry["usage"] = usage.model_dump() if hasattr(usage, "model_dump") else usage
        return response

    observer = PluginContext(
        PluginManifest(
            name="evaluation", version="0.1", description="Evaluation observer"
        ),
        manager,
    )
    observer.register_middleware("llm_execution", observe)
    model = config["model"]["default"]
    runtime = resolve_runtime_provider(
        requested=config["model"]["provider"], target_model=model
    )
    db = SessionDB(home / "state.db")
    agent = AIAgent(
        model=model,
        provider=runtime["provider"],
        api_key=runtime.get("api_key"),
        base_url=runtime.get("base_url"),
        api_mode="codex_responses",
        reasoning_config={
            "enabled": True,
            "effort": config["agent"]["reasoning_effort"],
        },
        enabled_toolsets=["delegation", "evaluation"],
        session_db=db,
        platform="photon",
        quiet_mode=True,
        max_iterations=12,
        skip_background_review=True,
    )
    assert agent.context_compressor.name == (
        "compressor" if args.baseline else "conversation"
    )
    turns = []
    history = []
    checks = {}

    def turn(text):
        nonlocal history
        from gateway.session_context import clear_session_vars, set_session_vars

        began = time.monotonic()
        tokens = set_session_vars(
            platform="photon",
            chat_id="evaluation",
            session_key=agent.session_id,
            session_id=agent.session_id,
            cwd=str(workspace),
            async_delivery=True,
        )
        try:
            result = agent.run_conversation(text, conversation_history=history)
        finally:
            clear_session_vars(tokens)
        history = result.get("messages", history)
        item = {
            "input": text,
            "seconds": round(time.monotonic() - began, 3),
            "response": result.get("final_response"),
            "failed": result.get("failed", False),
        }
        turns.append(item)
        print(
            json.dumps({key: value for key, value in item.items() if key != "input"}),
            flush=True,
        )
        return result

    try:
        if args.scenario == "capacity":
            from tools.async_delegation import dispatch_async_delegation

            def occupied():
                release.wait(timeout=75)
                return {"result": "Fixture finished"}

            for number in range(config["delegation"]["max_concurrent_children"]):
                handle = dispatch_async_delegation(
                    goal=f"Existing fixture task {number}",
                    context="",
                    toolsets=[],
                    role="leaf",
                    model=None,
                    session_key=f"fixture-{number}",
                    parent_session_id=f"fixture-{number}",
                    runner=occupied,
                    max_async_children=config["delegation"]["max_concurrent_children"],
                )
                assert handle["status"] == "dispatched"
            turn(
                "Use a worker to review the course workspace and report due dates. Read only."
            )
        elif args.scenario == "greeting":
            turn("yo")
        elif args.scenario == "summary":
            history = [
                {
                    "role": "user",
                    "content": "Our release code name is Juniper. Approval is pending; do not deploy.",
                },
                {"role": "assistant", "content": "I will keep deployment pending."},
            ]
            for n in range(20):
                history += [
                    {"role": "user", "content": f"Unrelated topic {n}"},
                    {"role": "assistant", "content": f"Discussed topic {n}."},
                ]
            turn("yo")
            store = agent.context_compressor.summaries
            if not store.busy.acquire(timeout=40):
                raise TimeoutError("Background summary did not finish")
            store.busy.release()
            from hermes_conversation.context import dialogue

            assert store.read(agent.session_id, dialogue(history)).covered > 0
            turn("What's the release code name, and can you deploy it yet?")
        elif args.scenario == "long-history":
            for n in range(80):
                history += [
                    {"role": "user", "content": f"Previous request {n}"},
                    {
                        "role": "assistant",
                        "content": "Completed workspace investigation. " * 100,
                    },
                ]
            history += [
                {
                    "role": "user",
                    "content": "The current project is called Lantern. Keep that exact name.",
                },
                {"role": "assistant", "content": "Understood."},
            ]
            turn("what's the project called? just the name")
        else:
            turn(
                "Use a worker to review the course workspace and tell me what is due on or before September 8, 2026. Read only; don't submit anything."
            )
            busy = started.wait(timeout=5) and not release.is_set()
            turn(
                "unrelated quick question: what's the difference between a draft PR and a merged PR? keep it short"
            )
            if args.scenario == "correction":
                turn(
                    "Correction to the course review: only physics, please. Ignore the other courses."
                )
            release.set()
            from tools.process_registry import process_registry

            completion = process_registry.completion_queue.get(timeout=75)
            turn(
                "Result from the previously requested course review:\n"
                + json.dumps(completion)
            )
        response = str(turns[-1]["response"] or "").lower()
        checks = {"no_failed_turns": all(not t["failed"] for t in turns)}
        if args.scenario == "capacity":
            checks["no_new_worker"] = not effects and not any(
                c["platform"] == "subagent" for c in calls
            )
            checks["admission_rejected"] = any(
                m.get("role") == "tool"
                and '"status": "rejected"' in str(m.get("content"))
                for m in history
            )
        if args.scenario in {"handoff", "correction"}:
            checks.update(
                {
                    "worker_was_busy": busy,
                    "worker_completed": completion.get("status") == "completed",
                    "physics_reported": "physics" in response
                    and "momentum" in response,
                    "worker_effort_low": any(c["platform"] == "subagent" for c in calls)
                    and all(
                        c["reasoning"]["effort"] == "low"
                        for c in calls
                        if c["platform"] == "subagent"
                    ),
                }
            )
        if args.scenario == "correction":
            checks["corrected_scope"] = (
                not any(
                    effect["path"] in {"writing-draft", "math-exam"}
                    for effect in effects
                )
                and "writing" not in response
            )
        if args.scenario == "long-history":
            checks["recall"] = response.strip().strip(".") == "lantern"
        if args.scenario == "summary":
            checks["recall"] = "juniper" in response
        if not all(checks.values()):
            raise RuntimeError("Evaluation checks failed; inspect report.json")
    finally:
        release.set()
        store = getattr(agent.context_compressor, "summaries", None)
        if store and store.busy.acquire(timeout=40):
            store.busy.release()
        report = {
            "scenario": args.scenario,
            "baseline": args.baseline,
            "turns": turns,
            "requests": calls,
            "effects": effects,
            "context_engine": agent.context_compressor.name,
            "checks": checks,
            "error": type(sys.exception()).__name__ if sys.exception() else None,
            "config_sha256": hashlib.sha256(
                json.dumps(config, sort_keys=True).encode()
            ).hexdigest(),
            "source_sha256": hashlib.sha256(
                b"".join(
                    path.read_bytes()
                    for path in sorted(
                        (Path(__file__).parent / "hermes_conversation").iterdir()
                    )
                    if path.is_file()
                )
                + (home / "SOUL.md").read_bytes()
                + (workspace / "AGENTS.md").read_bytes()
            ).hexdigest(),
        }
        (output / "report.json").write_text(json.dumps(report, indent=2))
        agent.close()
        db.close()
        (home / "auth.json").unlink(missing_ok=True)


if __name__ == "__main__":
    main()
