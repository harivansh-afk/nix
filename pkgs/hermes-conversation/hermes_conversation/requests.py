"""Request-only tool visibility; worker authorization remains owned by Hermes."""

import json
import logging
import threading

log = logging.getLogger(__name__)


class Admission:
    """Serialize Photon admission checks without changing native worker execution."""

    def __init__(self, limit):
        self.limit = limit
        self.lock = threading.Lock()

    def execute(self, args, next_call):
        from gateway.session_context import async_delivery_supported, get_session_env
        from tools.async_delegation import active_count

        def rejected(reason):
            return json.dumps({"status": "rejected", "error": reason, "started": False})

        if not self.lock.acquire(blocking=False):
            return rejected("Another admission is in progress. No new work started.")
        try:
            try:
                if not async_delivery_supported() and not get_session_env(
                    "HERMES_SESSION_ID", ""
                ):
                    return rejected("No background completion route is available.")
                if active_count() >= self.limit:
                    return rejected(
                        "Background capacity is full. No new work started; await an existing result."
                    )
            except Exception:
                log.warning("Could not check background admission", exc_info=True)
                return rejected(
                    "Could not verify background capacity or routing. No new work started."
                )
            return next_call(args)
        finally:
            self.lock.release()


def tool_name(tool):
    return tool.get("function", tool).get("name", "")


def dispatched_this_turn(request):
    """Recognize a successful native handoff in either supported provider format."""
    calls = {}
    dispatched = False
    for item in request.get("input", request.get("messages", [])):
        if item.get("role") == "user":
            calls.clear()
            dispatched = False
        for call in item.get("tool_calls") or []:
            calls[call.get("id")] = tool_name(call)
        if item.get("type") == "function_call":
            calls[item.get("call_id")] = item.get("name")
        if item.get("role") == "tool":
            name = calls.get(item.get("tool_call_id"))
            output = item.get("content")
        elif item.get("type") == "function_call_output":
            name = calls.get(item.get("call_id"))
            output = item.get("output")
        else:
            continue
        if name != "delegate_task" or not isinstance(output, str):
            continue
        try:
            result = json.loads(output)
        except ValueError:
            continue
        if isinstance(result, dict) and result.get("status") == "dispatched":
            dispatched = True
    return dispatched


def conversation_request(request, allowed_tools):
    result = dict(request)
    if dispatched_this_turn(request):
        result["tools"] = []
        result["tool_choice"] = "none"
        result.pop("parallel_tool_calls", None)
    elif "tools" in request:
        result["tools"] = [
            tool for tool in request["tools"] if tool_name(tool) in allowed_tools
        ]
        if (
            isinstance(result.get("tool_choice"), dict)
            and tool_name(result["tool_choice"]) not in allowed_tools
        ):
            result["tool_choice"] = "auto" if result["tools"] else "none"
    return result
