"""Manual native acceptance for the separately launched GTK fixture.

Launch: spark-computer-native-fixture --state /tmp/spark-native-acceptance.json
Run: SPARK_COMPUTER_COMMAND=/.../bin/spark-computer uv run ... test_native.py
     --state /tmp/spark-native-acceptance.json --title 'Spark Computer Acceptance'
The fixture stays running. Only its uniquely matching window receives input.
"""

import argparse
import asyncio
import base64
import json
import os
from pathlib import Path
import tempfile
import time
import uuid

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def execute(client, session, code):
    result = await client.call_tool("computer_exec", {
        "session": session, "code": code, "desktop": True, "timeout": 30})
    if result.isError:
        raise AssertionError("\n".join(block.text for block in result.content if block.type == "text"))
    return result


async def read_effect(path, expected_text, expected_count):
    async with asyncio.timeout(3):
        while True:
            state = json.loads(path.read_text())
            if state["name"] == expected_text and state["applications"] == expected_count:
                assert state["output"] == f"Applied: {expected_text}; Count: {expected_count}"
                return state
            await asyncio.sleep(0.05)


def save_image(result, path):
    images = [block for block in result.content if block.type == "image"]
    assert images, "CUA did not return an MCP screenshot image"
    image = images[-1]
    assert image.mimeType == "image/png"
    data = base64.b64decode(image.data, validate=True)
    assert data.startswith(b"\x89PNG\r\n\x1a\n")
    path.write_bytes(data)
    return len(data)


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--title", default="Spark Computer Acceptance")
    parser.add_argument("--artifacts", type=Path)
    args = parser.parse_args()
    assert args.title.strip(), "A nonempty fixture title is required"
    initial = json.loads(args.state.read_text())
    artifacts = args.artifacts or Path(tempfile.mkdtemp(prefix="spark-computer-native-"))
    artifacts.mkdir(parents=True, exist_ok=True)
    token = uuid.uuid4().hex[:8]
    session = f"native-acceptance-{token}"
    semantic_text, pixel_text = f"Semantic acceptance {token}", f"Pixel acceptance {token}"
    params = StdioServerParameters(command=os.environ["SPARK_COMPUTER_COMMAND"], env=dict(os.environ))
    started = time.monotonic()
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as client:
            await client.initialize()
            try:
                await execute(client, session, f"""
title = {args.title!r}
async def fixture_window():
    windows = (await desktop.list_windows())['windows']
    matches = [window for window in windows if title in window['title']]
    assert len(matches) == 1, 'Fixture window match must be unique'
    window = matches[0]
    if 'target' in globals():
        assert (window['pid'], window['window_id']) == (target['pid'], target['window_id']), 'Fixture identity changed'
    return window
def element(state, label, role):
    matches = [entry for entry in state['elements'] if entry['label'] == label and entry['role'] == role and entry['enabled']]
    assert len(matches) == 1, 'Fixture control match must be unique'
    return matches[0]
def center(entry, window):
    frame = entry['frame']
    x, y = frame['x'] + frame['w']/2 - window['x'], frame['y'] + frame['h']/2 - window['y']
    assert 0 <= x < window['width'] and 0 <= y < window['height'], 'Control lies outside fixture window'
    return {{'x': x, 'y': y}}
target = await fixture_window()
identity = {{'pid': target['pid'], 'window_id': target['window_id']}}
state = await desktop.get_window_state(**identity)
name = element(state, 'Name', 'text')
await desktop.set_value(**identity, element_token=name['element_token'], value={semantic_text!r})
state = await desktop.get_window_state(**identity)
button = element(state, 'Apply', 'button')
await desktop.click(**identity, element_token=button['element_token'])
""")
                semantic_state = await read_effect(args.state, semantic_text, initial["applications"] + 1)
                semantic_image = await execute(client, session, "await fixture_window()\nawait desktop.get_window_state(**identity)")
                semantic_bytes = save_image(semantic_image, artifacts / "semantic.png")
                await execute(client, session, f"""
target = await fixture_window()
state = await desktop.get_window_state(**identity)
name = element(state, 'Name', 'text')
await desktop.hotkey(**identity, **center(name, target), keys=['ctrl', 'a'], delivery_mode='foreground')
await desktop.type_text(**identity, text={pixel_text!r}, delivery_mode='foreground')
target = await fixture_window()
state = await desktop.get_window_state(**identity)
button = element(state, 'Apply', 'button')
await desktop.click(**identity, **center(button, target), delivery_mode='foreground')
""")
                pixel_state = await read_effect(args.state, pixel_text, initial["applications"] + 2)
                pixel_image = await execute(client, session, "await fixture_window()\nawait desktop.get_window_state(**identity)")
                pixel_bytes = save_image(pixel_image, artifacts / "pixel.png")
            finally:
                closed = await client.call_tool("computer_close", {"session": session})
                assert not closed.isError, "Native acceptance session cleanup failed"
    result = {"command": params.command, "title": args.title, "state_file": str(args.state),
              "semantic": semantic_state, "pixel": pixel_state,
              "screenshots": {"semantic_bytes": semantic_bytes, "pixel_bytes": pixel_bytes},
              "elapsed_seconds": time.monotonic() - started, "artifacts": str(artifacts),
              "fixture_left_running": True}
    (artifacts / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
