"""Request-only tool visibility; worker authorization remains owned by Hermes."""

import json


def tool_name(tool):
    return tool.get("function", tool).get("name", "")


def dispatched_this_turn(request):
    """Recognize a successful native handoff after the latest user message."""
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
    if "tools" in request:
        result["tools"] = [
            tool for tool in request["tools"] if tool_name(tool) in allowed_tools
        ]
        if (
            isinstance(result.get("tool_choice"), dict)
            and tool_name(result["tool_choice"]) not in allowed_tools
        ):
            result["tool_choice"] = "auto" if result["tools"] else "none"
    if dispatched_this_turn(request):
        result["tool_choice"] = "none"
        result.pop("parallel_tool_calls", None)
    return result
