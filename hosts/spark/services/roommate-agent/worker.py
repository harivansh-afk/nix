"""One sandboxed TV turn. Credentials arrive on stdin, never in argv or files."""

import json
import sys
from pathlib import Path

ALLOWED = {"search", "play", "status", "control", "seek", "sources", "browse"}


def main():
    payload = json.load(sys.stdin)
    from run_agent import AIAgent
    from tools.mcp_tool_discovery import discover_mcp_tools

    discover_mcp_tools()
    agent = AIAgent(
        **payload["runtime"],
        model=payload["model"],
        enabled_toolsets=["roomcast"],
        max_iterations=20,
        max_tokens=1200,
        quiet_mode=True,
        skip_context_files=True,
        skip_memory=True,
        skip_background_review=True,
        reasoning_config={"effort": "medium"},
    )
    from tools.mcp_tool import _mcp_tool_server_names

    names = {tool["function"]["name"] for tool in agent.tools}
    if names != {"mcp__roomcast__" + name for name in ALLOWED} or any(
        _mcp_tool_server_names.get(name) != "roomcast" for name in names
    ):
        raise RuntimeError(
            "TV worker tool boundary failed: " + ", ".join(sorted(names))
        )
    if payload.get("check"):
        print(
            json.dumps(
                {
                    "tools": sorted(names),
                    "personal_home_visible": Path("/home/rathi").exists(),
                }
            )
        )
        return
    result = agent.run_conversation(
        payload["text"],
        system_message=Path("/instructions.md").read_text(),
        conversation_history=payload.get("history", []),
    )
    if not result.get("completed", True):
        raise RuntimeError("TV turn did not complete")
    print(json.dumps({"reply": str(result.get("final_response", ""))[:6000]}))


if __name__ == "__main__":
    main()
