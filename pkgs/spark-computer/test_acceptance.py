"""Manual Spark acceptance: SPARK_COMPUTER_COMMAND=/.../bin/spark-computer uv run ... this-file.

Uses the existing Chromium CDP endpoint, local fixture tabs, and an isolated test
desktop lock. It never sends native GUI input or records existing tab URLs.
"""

import asyncio
import base64
from contextlib import asynccontextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import tempfile
import threading
import time

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from playwright.async_api import async_playwright


FIXTURE = b"""<!doctype html><html><head><title>Spark computer acceptance</title>
<style>body{font:20px sans-serif;max-width:750px;margin:40px}section{margin:25px 0}
button,input,textarea{font:inherit;padding:8px}canvas{border:1px solid #555}</style></head>
<body><h1>Spark computer acceptance</h1>
<section><form id="form"><label>Name <input id="name"></label>
<button>Submit locally</button></form><p id="greeting"></p></section>
<section><button id="wait">Show delayed element</button><div id="delayed"></div></section>
<section><canvas id="canvas" width="300" height="100"></canvas><p id="canvas-state"></p></section>
<section><a id="download" href="/download">Download fixture</a></section>
<section><label>Draft <textarea id="draft"></textarea></label>
<button id="save">Save draft locally</button><p id="saved"></p></section>
<script>
form.onsubmit=e=>{e.preventDefault();greeting.textContent='Hello '+document.querySelector('#name').value};
document.querySelector('#wait').onclick=()=>setTimeout(()=>{
document.querySelector('#delayed').textContent='Delayed element ready'},250);
const canvas=document.querySelector('#canvas'),ctx=canvas.getContext('2d');
ctx.fillStyle='#4261a5';ctx.fillRect(0,0,300,100);ctx.fillStyle='white';
ctx.font='20px sans-serif';ctx.fillText('Canvas interaction',35,55);
canvas.onclick=()=>document.querySelector('#canvas-state').textContent='Canvas clicked';
document.querySelector('#save').onclick=async()=>{
await fetch('/draft',{method:'POST',body:document.querySelector('#draft').value});
document.querySelector('#saved').textContent='Draft saved locally'};
</script></body></html>"""
DOWNLOAD = b"spark-computer acceptance download\n"


class FixtureHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        data = DOWNLOAD if self.path == "/download" else FIXTURE
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream" if self.path == "/download" else "text/html")
        self.send_header("Content-Length", str(len(data)))
        if self.path == "/download":
            self.send_header("Content-Disposition", 'attachment; filename="fixture.txt"')
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path != "/draft":
            self.send_error(404)
            return
        self.server.saved_drafts.append(self.rfile.read(int(self.headers["Content-Length"])).decode())
        self.send_response(204)
        self.end_headers()


@asynccontextmanager
async def computer(command, lock_path):
    params = StdioServerParameters(command=command, env={**os.environ,
        "SPARK_COMPUTER_LOCK": str(lock_path)})
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as client:
            await client.initialize()
            yield client


async def execute(client, session, code, desktop=False):
    result = await client.call_tool("computer_exec", {"session": session, "code": code,
                                                      "desktop": desktop, "timeout": 30})
    if result.isError:
        raise AssertionError("\n".join(block.text for block in result.content if block.type == "text"))
    return result


def result_json(result):
    return json.loads("".join(block.text for block in result.content if block.type == "text"))


async def targets(browser):
    session = await browser.new_browser_cdp_session()
    try:
        result = await session.send("Target.getTargets")
        return {target["targetId"]: target["url"] for target in result["targetInfos"]
                if target["type"] == "page"}
    finally:
        await session.detach()


async def browser_acceptance(client, fixture_url, artifacts):
    async with async_playwright() as playwright:
        browser = await playwright.chromium.connect_over_cdp(
            os.environ.get("SPARK_BROWSER_CDP", "http://127.0.0.1:19222"))
        before = await targets(browser)
        try:
            await execute(client, "fixture-a", f"""
page = await browser.page()
await page.goto({fixture_url!r})
assert page.url == {fixture_url!r}
persistent_value = 40
await page.locator('#name').fill('Hari fixture')
await page.locator('#form button').click()
assert await page.locator('#greeting').inner_text() == 'Hello Hari fixture'
await page.locator('#wait').click()
await page.locator('#delayed').get_by_text('Delayed element ready', exact=True).wait_for()
await page.locator('#canvas').click(position={{'x': 120, 'y': 50}})
assert await page.locator('#canvas-state').inner_text() == 'Canvas clicked'
""")
            await execute(client, "fixture-a", f"""
persistent_value += 2
assert persistent_value == 42
assert await browser.page() is page
async with page.expect_download() as event:
    await page.locator('#download').click()
download = await event.value
assert download.suggested_filename == 'fixture.txt'
from pathlib import Path
assert Path(await download.path()).read_bytes() == {DOWNLOAD!r}
await download.save_as({str(artifacts / 'fixture.txt')!r})
await page.locator('#draft').fill('Acceptance draft, kept on localhost.')
await page.locator('#save').click()
await page.locator('#saved').get_by_text('Draft saved locally', exact=True).wait_for()
""")
            image_result = await execute(client, "fixture-a", "display(await page.screenshot(full_page=True))")
            images = [block for block in image_result.content if block.type == "image"]
            assert len(images) == 1 and images[0].mimeType == "image/png"
            screenshot = base64.b64decode(images[0].data, validate=True)
            assert screenshot.startswith(b"\x89PNG\r\n\x1a\n")
            (artifacts / "browser.png").write_bytes(screenshot)
            await execute(client, "fixture-b", f"""
page = await browser.page()
await page.goto({fixture_url + '?second-task'!r})
assert 'persistent_value' not in globals()
assert sum(tab['owned'] for tab in await browser.tabs()) == 1
""")
            active = await targets(browser)
            owned = set(active) - set(before)
            assert len(owned) == 2, f"Expected two owned targets, saw {len(owned)}"
            assert all(active[target].startswith(fixture_url) for target in owned)
            await execute(client, "fixture-a", "assert persistent_value == 42\nassert '?second-task' not in page.url")
        finally:
            for name in ("fixture-a", "fixture-b"):
                await client.call_tool("computer_close", {"session": name})
        after = await targets(browser)
        assert set(before) <= set(after), "A pre-existing browser tab was closed"
        assert all(after[target] == url for target, url in before.items()), "A pre-existing tab was navigated"
        assert not owned.intersection(after), "An owned task tab survived computer_close"
        return {"checks": ["form", "delayed element", "canvas", "download", "draft",
                           "persistent globals", "distinct task tabs", "owned-tab cleanup", "MCP image"],
                "preexisting_tabs_preserved": len(before), "screenshot_bytes": len(screenshot)}


async def locking_acceptance(first, second, artifacts):
    marker = artifacts / "lock-held"
    waiter = None
    hold = asyncio.create_task(execute(first, "lock-holder", f"""
import json, time
from pathlib import Path
start = time.monotonic()
Path({str(marker)!r}).write_text('held')
await asyncio.sleep(1.5)
print(json.dumps({{'start': start, 'end': time.monotonic()}}))
""", desktop=True))
    try:
        async with asyncio.timeout(5):
            while not marker.exists():
                await asyncio.sleep(0.02)
        waiter = asyncio.create_task(execute(second, "lock-waiter",
            "import json, time\nprint(json.dumps({'entered': time.monotonic()}))", desktop=True))
        browser_only = result_json(await execute(second, "lock-independent",
            "import json, time\nawait browser.tabs()\nprint(json.dumps({'completed': time.monotonic()}))"))
        held, waited = result_json(await hold), result_json(await waiter)
        assert browser_only["completed"] < held["end"], "Browser-only invocation waited on desktop lock"
        assert waited["entered"] >= held["end"], "Separate MCP processes overlapped desktop access"
        return {"separate_processes_serialized": True, "browser_only_bypassed_lock": True,
                "held_seconds": held["end"] - held["start"],
                "waiter_entered_after_release_seconds": waited["entered"] - held["end"]}
    finally:
        calls = [call for call in (hold, waiter) if call is not None]
        for call in calls:
            if not call.done():
                call.cancel()
        await asyncio.gather(*calls, return_exceptions=True)
        marker.unlink(missing_ok=True)
        for client, name in ((first, "lock-holder"), (second, "lock-waiter"), (second, "lock-independent")):
            await client.call_tool("computer_close", {"session": name})


async def main():
    command = os.environ["SPARK_COMPUTER_COMMAND"]
    artifacts = Path(os.environ.get("SPARK_COMPUTER_ARTIFACT_DIR") or tempfile.mkdtemp(prefix="spark-computer-acceptance-"))
    artifacts.mkdir(parents=True, exist_ok=True)
    fixture = ThreadingHTTPServer(("127.0.0.1", 0), FixtureHandler)
    fixture.saved_drafts = []
    thread = threading.Thread(target=fixture.serve_forever, daemon=True)
    thread.start()
    started = time.monotonic()
    try:
        lock_path = artifacts / "desktop.lock"
        async with computer(command, lock_path) as first, computer(command, lock_path) as second:
            result = {"browser": await browser_acceptance(first,
                f"http://127.0.0.1:{fixture.server_port}/", artifacts)}
            assert fixture.saved_drafts == ["Acceptance draft, kept on localhost."]
            result["desktop_lock"] = await locking_acceptance(first, second, artifacts)
        result.update({"command": command, "elapsed_seconds": time.monotonic() - started,
                       "artifacts": str(artifacts), "native_gui_input": False})
        (artifacts / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))
    finally:
        fixture.shutdown()
        fixture.server_close()
        thread.join()


if __name__ == "__main__":
    asyncio.run(main())
