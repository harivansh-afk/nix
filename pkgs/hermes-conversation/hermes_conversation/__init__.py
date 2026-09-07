"""Photon request policy using Hermes's supported middleware interface."""

from .handoff import HandoffContext
from .requests import conversation_request


def register(ctx):
    platforms = frozenset(ctx.get_config("platforms", ["photon"]))
    tools = frozenset(
        ctx.get_config("foreground_tools", ["delegate_task", "session_search"])
    )
    handoff = HandoffContext(max(0, int(ctx.get_config("worker_context_chars", 0))))

    def request_policy(
        request, platform="", session_id="", api_request_id="", **kwargs
    ):
        if platform not in platforms:
            return None
        handoff.capture(request, session_id, api_request_id)
        return {
            "request": conversation_request(request, tools),
            "source": "conversation",
        }

    ctx.register_middleware("llm_request", request_policy)

    def worker_context(tool_name, args, session_id="", api_request_id="", **kwargs):
        if tool_name != "delegate_task":
            return None
        updated = handoff.attach(args, session_id, api_request_id)
        if updated is not None:
            return {"args": updated, "source": "conversation"}

    ctx.register_middleware("tool_request", worker_context)
