"""Photon request policy using Hermes's supported middleware interface."""

from .requests import conversation_request


def register(ctx):
    platforms = frozenset(ctx.get_config("platforms", ["photon"]))
    tools = frozenset(
        ctx.get_config("foreground_tools", ["delegate_task", "session_search"])
    )

    def request_policy(request, platform="", **kwargs):
        if platform not in platforms:
            return None
        return {"request": conversation_request(request, tools), "source": "conversation"}

    ctx.register_middleware("llm_request", request_policy)
