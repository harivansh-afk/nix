"""Messaging policy through Hermes's context-engine and request middleware APIs."""

from .context import ConversationContext
from .handoff import HandoffContext
from .requests import Admission, conversation_request
from .summaries import Summaries


def register(ctx):
    platforms = frozenset(ctx.get_config("platforms", ["photon"]))
    tools = frozenset(
        ctx.get_config("foreground_tools", ["delegate_task", "session_search"])
    )
    handoff = HandoffContext(max(0, int(ctx.get_config("worker_context_chars", 0))))

    admission = Admission(int(ctx.get_config("max_active", 2)))
    ctx.register_auxiliary_task(
        "conversation_summary",
        display_name="Conversation summary",
        description="Background dialogue summaries; never delays a conversation turn",
    )
    summaries = Summaries(ctx.state.data_dir / "summaries.sqlite3", ctx.llm)
    ctx.register_context_engine(
        ConversationContext(
            summaries,
            platforms=platforms,
            input_tokens=int(ctx.get_config("input_tokens", 18000)),
            recent_turns=int(ctx.get_config("recent_turns", 8)),
        )
    )

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

    def tool_policy(tool_name, args, next_call, platform="", **kwargs):
        from agent.delegation_context import is_delegated_child_context
        from gateway.session_context import get_session_env

        if (
            get_session_env("HERMES_SESSION_PLATFORM", platform) in platforms
            and not is_delegated_child_context()
            and tool_name == "delegate_task"
            and str(args.get("action") or "spawn").strip().lower() == "spawn"
        ):
            return admission.execute(args, next_call)
        return next_call(args)

    ctx.register_middleware("tool_execution", tool_policy)
