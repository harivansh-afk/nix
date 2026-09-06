import asyncio
import base64
import fcntl
import os
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from mcp import types
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server

import server


PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=")


class FakePage:
    def __init__(self, url="about:blank"):
        self.url = url
        self.closed = False

    def is_closed(self):
        return self.closed

    async def title(self):
        return self.url

    async def goto(self, url):
        self.url = url

    async def close(self):
        self.closed = True

    async def screenshot(self):
        return PNG


class FakeContext:
    def __init__(self):
        self.pages = [FakePage("https://user.example/")]

    async def new_page(self):
        page = FakePage()
        self.pages.append(page)
        return page


class FakeCua:
    def __init__(self):
        self.calls = []
        self.closed = False
        self.result = None

    async def request(self, method, **arguments):
        self.calls.append((method, arguments))
        if method == "list_tools":
            return types.ListToolsResult(tools=[types.Tool(
                name="get_window_state", description="Inspect a window", inputSchema={
                    "type": "object", "properties": {"session": {"type": "string"},
                                                         "window_id": {"type": "integer"}}})])
        return self.result or types.CallToolResult(content=[types.TextContent(type="text", text="window ready"),
            types.ImageContent(type="image", mimeType="image/png", data=base64.b64encode(PNG).decode())],
            structuredContent={"window_id": 12})

    async def close(self):
        self.closed = True


class RuntimeTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.lock_path = Path(self.tmp.name) / "computer.lock"
        self.env = patch.dict(os.environ, {"SPARK_COMPUTER_LOCK": str(self.lock_path)})
        self.env.start()
        self.clients = []
        def factory():
            client = FakeCua()
            self.clients.append(client)
            return client
        self.runtime = server.Runtime(cua_factory=factory)
        self.context = FakeContext()
        async def context():
            return self.context
        self.runtime.browser_context = context

    async def asyncTearDown(self):
        await self.runtime.close()
        self.env.stop()
        self.tmp.cleanup()

    def text(self, result):
        return "".join(block.text for block in result.content if block.type == "text")

    async def test_persistent_namespaces_exception_and_await(self):
        result = await self.runtime.execute("one", "x = 41\nawait asyncio.sleep(0)\nprint(x)")
        self.assertEqual(self.text(result), "41\n")
        result = await self.runtime.execute("one", "x += 1\nraise ValueError('bad code')")
        self.assertTrue(result.isError)
        self.assertIn("ValueError: bad code", self.text(result))
        self.assertEqual(self.text(await self.runtime.execute("one", "print(x)")), "42\n")
        self.assertTrue((await self.runtime.execute("two", "print(x)")).isError)

    async def test_owned_pages_and_cleanup_leave_user_page(self):
        self.assertEqual(len(self.context.pages), 1)
        await self.runtime.execute("one", "page = await browser.page()\nawait page.goto('https://task.example/')")
        first = self.context.pages[-1]
        await self.runtime.execute("one", "assert await browser.page() is page")
        self.assertEqual(len(self.context.pages), 2)
        await self.runtime.execute("two", "page = await browser.page()")
        second = self.context.pages[-1]
        await self.runtime.execute("one", "tabs = await browser.tabs()\nassert sum(t['owned'] for t in tabs) == 1")
        self.assertFalse((await self.runtime.close_session("one")).isError)
        self.assertTrue(first.closed)
        self.assertFalse(second.closed)
        self.assertEqual(self.context.pages[0].url, "https://user.example/")
        await self.runtime.close()
        self.assertTrue(second.closed)
        self.assertFalse(self.context.pages[0].closed)
        self.assertFalse(self.runtime.sessions)

    async def test_display_returns_images_without_base64_text(self):
        result = await self.runtime.execute("one", "page = await browser.page()\nprint('before')\ndisplay(await page.screenshot())\nprint('after')")
        self.assertEqual([block.type for block in result.content], ["text", "image", "text"])
        self.assertEqual(base64.b64decode(result.content[1].data), PNG)
        self.assertNotIn("iVBOR", self.text(result))
        path = Path(self.tmp.name) / "image.png"
        path.write_bytes(PNG)
        result = await self.runtime.execute("one", f"display({str(path)!r})")
        self.assertEqual(result.content[0].mimeType, "image/png")

    async def test_desktop_schema_permission_and_image_forwarding(self):
        result = await self.runtime.execute("one", "await desktop.describe()")
        self.assertTrue(result.isError)
        self.assertFalse(self.clients)
        result = await self.runtime.execute("one", "r = await desktop.get_window_state(window_id=12)\nprint(r)", desktop=True)
        self.assertFalse(result.isError)
        self.assertEqual(result.content[0].type, "image")
        self.assertIn("window_id", self.text(result))
        self.assertEqual(self.runtime.sessions["one"].globals["r"], {"window_id": 12})
        self.assertNotIn("iVBOR", self.text(result))
        arguments = self.clients[0].calls[-1][1]["arguments"]
        self.assertEqual(arguments["session"], f"computer-{os.getpid()}-one")
        self.assertEqual(arguments["window_id"], 12)
        await self.runtime.execute("one", "await desktop.describe('get_window_state')", desktop=True)
        self.assertEqual(sum(method == "list_tools" for method, _ in self.clients[0].calls), 1)
        await self.runtime.close_session("one")
        self.assertTrue(self.clients[0].closed)

    async def test_desktop_decodes_json_and_preserves_plain_text_envelope(self):
        await self.runtime.execute("one", "await desktop.describe()", desktop=True)
        self.clients[0].result = types.CallToolResult(content=[
            types.TextContent(type="text", text='{"windows": [{"id": 12}]}')])
        result = await self.runtime.execute("one", "r = await desktop.get_window_state()\nprint(r['windows'][0]['id'])", desktop=True)
        self.assertEqual(self.text(result), "12\n")
        self.clients[0].result = types.CallToolResult(content=[
            types.TextContent(type="text", text="plain text")])
        result = await self.runtime.execute("one", "r = await desktop.get_window_state()\nprint(r['content'][0]['text'])", desktop=True)
        self.assertEqual(self.text(result), "plain text\n")

    async def test_desktop_discovery_retries_after_partial_failure(self):
        client = FakeCua()
        original_request = client.request
        cursors = []
        async def flaky_request(method, **arguments):
            if method != "list_tools":
                return await original_request(method, **arguments)
            cursors.append(arguments["cursor"])
            if len(cursors) == 1:
                result = await original_request(method, **arguments)
                result.nextCursor = "next"
                return result
            if len(cursors) == 2:
                raise RuntimeError("temporary discovery failure")
            return await original_request(method, **arguments)
        client.request = flaky_request
        self.runtime.cua_factory = lambda: client
        first = await self.runtime.execute("retry", "await desktop.describe()", desktop=True)
        self.assertTrue(first.isError)
        self.assertIsNone(self.runtime.sessions["retry"].desktop.tools)
        second = await self.runtime.execute("retry", "r = await desktop.get_window_state()\nprint(r['window_id'])", desktop=True)
        self.assertFalse(second.isError, self.text(second))
        self.assertEqual(self.text(second), "12\n")
        self.assertEqual(cursors, [None, "next", None])

    async def test_desktop_native_error_raises_and_still_forwards_images(self):
        await self.runtime.execute("one", "await desktop.describe()", desktop=True)
        self.clients[0].result = types.CallToolResult(isError=True, content=[
            types.TextContent(type="text", text="Window not found"),
            types.ImageContent(type="image", mimeType="image/png", data=base64.b64encode(PNG).decode())])
        result = await self.runtime.execute("one", "await desktop.get_window_state()\nprint('should not execute')", desktop=True)
        self.assertTrue(result.isError)
        self.assertEqual(result.content[0].type, "image")
        self.assertIn("Window not found", self.text(result))
        self.assertNotIn("should not execute", self.text(result))

    async def test_closed_owned_page_fails_without_allocating_replacement(self):
        await self.runtime.execute("one", "page = await browser.page()")
        owned = self.context.pages[-1]
        await owned.close()
        result = await self.runtime.execute("one", "page = await browser.page()")
        self.assertTrue(result.isError)
        self.assertIn("closed or disconnected", self.text(result))
        self.assertEqual(len(self.context.pages), 2)
        self.assertFalse(self.context.pages[0].closed)
        old_task = self.runtime.sessions["one"]
        await self.runtime.close_session("one")
        self.assertEqual(old_task.globals, {})
        await self.runtime.execute("one", "page = await browser.page()")
        self.assertEqual(len(self.context.pages), 3)

    async def test_disconnected_browser_fails_owned_page_and_cleanup_discards_state(self):
        await self.runtime.execute("one", "page = await browser.page()")
        self.runtime.browser = SimpleNamespace(is_connected=lambda: False)
        result = await self.runtime.execute("one", "await browser.page()")
        self.assertTrue(result.isError)
        self.assertEqual(len(self.context.pages), 2)
        task = self.runtime.sessions["one"]
        async def failed_close():
            raise RuntimeError("browser transport disconnected")
        task.browser.owned_page.close = failed_close
        result = await self.runtime.close_session("one")
        self.assertTrue(result.isError)
        self.assertNotIn("one", self.runtime.sessions)
        self.assertEqual(task.globals, {})
        self.assertIsNone(task.browser.owned_page)
        self.assertFalse(self.context.pages[0].closed)

    async def test_timeout_releases_both_locks_and_preserves_session(self):
        result = await self.runtime.execute("one", "x = 1\nawait asyncio.sleep(10)", desktop=True, timeout=1)
        self.assertTrue(result.isError)
        self.assertIn("Timed out", self.text(result))
        self.assertFalse(self.runtime.desktop_lock.locked())
        self.assertFalse(self.runtime.sessions["one"].lock.locked())
        with self.lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = await self.runtime.execute("one", "print(x)", desktop=True)
        self.assertEqual(self.text(result), "1\n")

    async def test_desktop_lock_wait_is_bounded_and_browser_calls_skip_lock(self):
        with self.lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = await self.runtime.execute("one", "print('browser')")
            self.assertEqual(self.text(result), "browser\n")
            result = await self.runtime.execute("two", "print('desktop')", desktop=True, timeout=1)
            self.assertTrue(result.isError)
            self.assertNotIn("desktop", self.text(result))

    async def test_same_session_reentrance_and_close_are_rejected(self):
        running = asyncio.create_task(self.runtime.execute("one", "await asyncio.sleep(10)", desktop=True))
        await asyncio.sleep(0.05)
        self.assertTrue((await self.runtime.execute("one", "print('racing')")).isError)
        self.assertTrue((await self.runtime.close_session("one")).isError)
        result = await self.runtime.execute("two", "print('independent')")
        self.assertEqual(self.text(result), "independent\n")
        running.cancel()
        result = await running
        self.assertTrue(result.isError)
        self.assertFalse(self.runtime.desktop_lock.locked())

    async def test_limits(self):
        result = await self.runtime.execute("one", "print('x' * 100000)")
        self.assertIn("truncated", self.text(result))
        self.assertLess(len(self.text(result)), server.TEXT_LIMIT + 100)
        for index in range(15):
            await self.runtime.execute(str(index), "pass")
        self.assertTrue((await self.runtime.execute("overflow", "pass")).isError)
        self.assertTrue((await self.runtime.execute("one", "pass", timeout=0)).isError)
        self.assertTrue((await self.runtime.execute("one", "pass", timeout=121)).isError)

    async def test_shutdown_disconnects_transport_without_browser_close(self):
        stopped = []
        async def stop():
            stopped.append(True)
        self.runtime.playwright = SimpleNamespace(stop=stop)
        self.runtime.browser = object()
        await self.runtime.close()
        self.assertEqual(stopped, [True])

    def fake_cua_executable(self):
        executable = Path(self.tmp.name) / "fake-cua"
        executable.write_text(f"#!{sys.executable}\nimport sys, asyncio\n"
                              f"sys.path.insert(0, {str(Path(__file__).parent)!r})\n"
                              "from test_server import fake_cua_main\nasyncio.run(fake_cua_main())\n")
        executable.chmod(0o700)
        return str(executable)

    async def test_persistent_cua_transport_survives_cancel_and_closes(self):
        self.runtime.cua_factory = server.CuaClient
        with patch.dict(os.environ, {"CUA_DRIVER_COMMAND": self.fake_cua_executable()}):
            result = await self.runtime.execute("transport", "await desktop.pause()", desktop=True, timeout=1)
            self.assertTrue(result.isError)
            self.assertIn("Timed out", self.text(result))
            result = await self.runtime.execute("transport", "print(await desktop.ping())", desktop=True)
            self.assertFalse(result.isError, self.text(result))
            self.assertIn("pong", self.text(result))
            client = self.runtime.sessions["transport"].desktop.client
            await self.runtime.close_session("transport")
            self.assertTrue(client.worker.done())

    async def test_cua_worker_death_settles_queued_and_cancelled_requests(self):
        with patch.dict(os.environ, {"CUA_DRIVER_COMMAND": self.fake_cua_executable()}):
            client = server.CuaClient()
            await client.request("list_tools")
            first = asyncio.create_task(client.request("call_tool", name="pause", arguments={}))
            await asyncio.sleep(0.05)
            pending = asyncio.create_task(client.request("call_tool", name="ping", arguments={}))
            cancelled = asyncio.create_task(client.request("call_tool", name="ping", arguments={}))
            await asyncio.sleep(0)
            cancelled.cancel()
            client.worker.cancel()
            results = await asyncio.wait_for(asyncio.gather(first, pending, cancelled,
                                                            return_exceptions=True), timeout=5)
            self.assertIsInstance(results[0], asyncio.CancelledError)
            self.assertIsInstance(results[1], RuntimeError)
            self.assertIn("transport stopped", str(results[1]))
            self.assertIsInstance(results[2], asyncio.CancelledError)
            self.assertTrue(client.queue.empty())
            await client.close()

    async def test_cua_startup_failure_settles_all_waiters(self):
        with patch.dict(os.environ, {"CUA_DRIVER_COMMAND": str(Path(self.tmp.name) / "missing")}):
            client = server.CuaClient()
            results = await asyncio.wait_for(asyncio.gather(client.request("list_tools"),
                client.request("list_tools"), return_exceptions=True), timeout=2)
            self.assertTrue(all(isinstance(result, Exception) for result in results))
            await client.close()

    async def test_cua_close_before_worker_start_settles_readiness(self):
        client = server.CuaClient()
        await client.close()
        with self.assertRaisesRegex(RuntimeError, "transport stopped"):
            await asyncio.wait_for(client.request("list_tools"), timeout=1)

    async def test_stdio_protocol_returns_real_images_and_captures_imported_print(self):
        params = StdioServerParameters(command=sys.executable,
                                       args=[str(Path(server.__file__))])
        async with stdio_client(params) as (read, write):
            async with ClientSession(read, write) as client:
                await client.initialize()
                tools = await client.list_tools()
                self.assertEqual({tool.name for tool in tools.tools}, {"computer_exec", "computer_close"})
                result = await client.call_tool("computer_exec", {"session": "wire", "code":
                    f"import builtins\nbuiltins.print('imported')\nx = 23\ndisplay({PNG!r})"})
                self.assertFalse(result.isError, self.text(result))
                self.assertEqual(self.text(result), "imported\n")
                self.assertEqual(result.content[1].type, "image")
                self.assertEqual(base64.b64decode(result.content[1].data), PNG)
                result = await client.call_tool("computer_exec", {"session": "wire", "code": "print(x)"})
                self.assertEqual(self.text(result), "23\n")
                self.assertFalse((await client.call_tool("computer_close", {"session": "wire"})).isError)


async def fake_cua_main():
    fake = Server("fake-cua")
    @fake.list_tools()
    async def list_tools():
        return [types.Tool(name=name, inputSchema={"type": "object", "properties": {}})
                for name in ("pause", "ping")]
    @fake.call_tool()
    async def call_tool(name, arguments):
        if name == "pause":
            await asyncio.sleep(10)
        return [types.TextContent(type="text", text="pong")]
    async with stdio_server() as (read, write):
        await fake.run(read, write, fake.create_initialization_options())


if __name__ == "__main__":
    unittest.main()
