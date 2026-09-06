"""Trusted local Python sessions over stdio MCP; Chromium and CUA stay upstream."""

import ast
import asyncio
import base64
import builtins
import contextvars
import fcntl
import inspect
import json
import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path

from mcp import ClientSession, StdioServerParameters, types
from mcp.client.stdio import stdio_client
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server
from playwright.async_api import async_playwright


CURRENT = contextvars.ContextVar("computer_execution", default=None)
TEXT_LIMIT = 64 * 1024
IMAGE_LIMIT = 20 * 1024 * 1024


class CodeStdout:
    """Keep imported Python code's prints away from the MCP protocol stream."""

    def write(self, value):
        output = CURRENT.get()
        if output is not None and output.active:
            output.write(value)
        else:
            sys.stderr.write(value)
        return len(value)

    def flush(self):
        sys.stderr.flush()


class Output:
    def __init__(self, desktop):
        self.desktop = desktop
        self.active = True
        self.blocks = []
        self.text_size = 0
        self.image_size = 0
        self.image_count = 0

    def write(self, value):
        room = TEXT_LIMIT - self.text_size
        if room <= 0:
            return
        value = value[:room]
        self.text_size += len(value)
        if self.blocks and self.blocks[-1].type == "text":
            self.blocks[-1].text += value
        else:
            self.blocks.append(types.TextContent(type="text", text=value))

    def image(self, block):
        size = len(block.data)
        if self.image_count >= 8 or self.image_size + size > IMAGE_LIMIT:
            raise ValueError("Image output limit reached (8 images / 20 MiB encoded)")
        self.image_count += 1
        self.image_size += size
        self.blocks.append(block)


def execution(require_desktop=False):
    output = CURRENT.get()
    if output is None or not output.active:
        raise RuntimeError("Use this helper inside computer_exec")
    if require_desktop and not output.desktop:
        raise RuntimeError("Desktop operations require computer_exec(desktop=true)")
    return output


def captured_print(*values, sep=" ", end="\n", file=None, flush=False):
    if file is not None and file not in (sys.stdout, sys.stderr):
        return builtins.print(*values, sep=sep, end=end, file=file, flush=flush)
    execution().write(sep.join(str(value) for value in values) + end)


def display(value):
    output = execution()
    if isinstance(value, (str, os.PathLike)):
        path = Path(value)
        if path.stat().st_size > IMAGE_LIMIT:
            raise ValueError("Image file exceeds output limit")
        value = path.read_bytes()
    if not isinstance(value, bytes):
        raise TypeError("display expects image bytes or a local image path")
    if value.startswith(b"\x89PNG\r\n\x1a\n"):
        mime = "image/png"
    elif value.startswith(b"\xff\xd8\xff"):
        mime = "image/jpeg"
    elif value.startswith((b"GIF87a", b"GIF89a")):
        mime = "image/gif"
    elif value.startswith(b"RIFF") and value[8:12] == b"WEBP":
        mime = "image/webp"
    else:
        raise ValueError("Unsupported image format; use PNG, JPEG, GIF or WebP")
    output.image(types.ImageContent(type="image", mimeType=mime,
                                    data=base64.b64encode(value).decode("ascii")))


class Browser:
    def __init__(self, runtime):
        self.runtime = runtime
        self.owned_page = None

    async def page(self):
        execution()
        if self.owned_page is not None and (
            self.owned_page.is_closed()
            or (self.runtime.browser is not None and not self.runtime.browser.is_connected())
        ):
            raise RuntimeError("The task's browser tab was closed or disconnected; "
                               "use computer_close and start a new session")
        if self.owned_page is None:
            context = await self.runtime.browser_context()
            self.owned_page = await context.new_page()
        return self.owned_page

    async def tabs(self):
        execution()
        context = await self.runtime.browser_context()
        return [{"url": page.url, "title": await page.title(),
                 "owned": page is self.owned_page} for page in context.pages]

    async def close(self):
        try:
            if self.owned_page is not None and not self.owned_page.is_closed():
                await self.owned_page.close()
        finally:
            self.owned_page = None


class CuaClient:
    """One owner task keeps MCP's AnyIO transport scopes in the same task."""

    def __init__(self):
        self.queue = asyncio.Queue()
        self.ready = asyncio.get_running_loop().create_future()
        self.worker = asyncio.create_task(self.run())
        self.worker.add_done_callback(lambda _: self.finish_requests())

    def finish_requests(self):
        stopped = RuntimeError("CUA transport stopped; close this computer session")
        if not self.ready.done():
            self.ready.set_exception(stopped)
        while not self.queue.empty():
            request = self.queue.get_nowait()
            if request is not None:
                _, _, reply, finished = request
                if not reply.done():
                    reply.set_exception(stopped)
                finished.set()

    async def run(self):
        try:
            args = ["mcp", "--socket", os.environ.get("CUA_DRIVER_SOCKET",
                    f"/run/user/{os.getuid()}/cua-driver.sock")]
            params = StdioServerParameters(command=os.environ.get("CUA_DRIVER_COMMAND", "cua-driver"),
                                           args=args, env=dict(os.environ))
            async with stdio_client(params) as (read, write):
                async with ClientSession(read, write) as client:
                    await client.initialize()
                    self.ready.set_result(None)
                    while (request := await self.queue.get()) is not None:
                        method, arguments, reply, finished = request
                        try:
                            operation = asyncio.create_task(getattr(client, method)(**arguments))
                            def cancel_operation(future, operation=operation):
                                if future.cancelled():
                                    operation.cancel()
                            reply.add_done_callback(cancel_operation)
                            result = await operation
                            if not reply.done():
                                reply.set_result(result)
                        except asyncio.CancelledError:
                            if not reply.cancelled():
                                reply.cancel()
                                raise
                        except Exception as error:
                            if not reply.done():
                                reply.set_exception(error)
                        finally:
                            finished.set()
        except Exception as error:
            if not self.ready.done():
                self.ready.set_exception(error)
            else:
                raise
        finally:
            self.finish_requests()

    async def request(self, method, **arguments):
        await asyncio.shield(self.ready)
        if self.worker.done():
            self.worker.result()
            raise RuntimeError("CUA connection is closed; close this computer session")
        reply = asyncio.get_running_loop().create_future()
        finished = asyncio.Event()
        await self.queue.put((method, arguments, reply, finished))
        try:
            return await reply
        except asyncio.CancelledError:
            reply.cancel()
            await asyncio.shield(finished.wait())
            raise

    async def close(self):
        if not self.ready.done():
            self.worker.cancel()
        else:
            await self.queue.put(None)
        try:
            await self.worker
        except asyncio.CancelledError:
            pass
        finally:
            if self.ready.done() and not self.ready.cancelled():
                self.ready.exception()


class Desktop:
    def __init__(self, name, factory):
        self.name = name
        self.factory = factory
        self.client = None
        self.tools = None

    async def describe(self, name=None):
        execution(require_desktop=True)
        if self.client is None:
            self.client = self.factory()
        if self.tools is None:
            tools = {}
            cursor = None
            while True:
                result = await self.client.request("list_tools", cursor=cursor)
                tools.update({tool.name: tool for tool in result.tools})
                cursor = result.nextCursor
                if not cursor:
                    break
            self.tools = tools
        if name is None:
            return [{"name": tool.name, "description": tool.description}
                    for tool in self.tools.values()]
        if name not in self.tools:
            raise ValueError(f"Unknown desktop tool: {name}")
        return self.tools[name].model_dump(exclude_none=True)

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)

        async def call(**arguments):
            output = execution(require_desktop=True)
            schema = await self.describe(name)
            properties = schema["inputSchema"].get("properties", {})
            for key in ("session", "session_id"):
                if key in properties:
                    arguments.setdefault(key, self.name)
            result = await self.client.request("call_tool", name=name, arguments=arguments)
            content = []
            for block in result.content:
                if block.type == "image":
                    output.image(block)
                else:
                    content.append(block.model_dump(exclude_none=True))
            if result.isError:
                message = "\n".join(block["text"] for block in content if block["type"] == "text")
                raise RuntimeError(f"Desktop tool {name} failed: {message or 'upstream reported an error'}")
            if result.structuredContent is not None:
                return result.structuredContent
            if len(content) == 1 and content[0]["type"] == "text":
                try:
                    return json.loads(content[0]["text"])
                except json.JSONDecodeError:
                    pass
            return {"content": content}
        return call

    async def close(self):
        try:
            if self.client is not None:
                await self.client.close()
        finally:
            self.client = None
            self.tools = None


class TaskSession:
    def __init__(self, name, runtime):
        self.lock = asyncio.Lock()
        self.browser = Browser(runtime)
        self.desktop = Desktop(f"computer-{os.getpid()}-{name}", runtime.cua_factory)
        self.globals = {"__builtins__": {**vars(builtins), "print": captured_print},
                        "__name__": "__computer__", "asyncio": asyncio,
                        "browser": self.browser, "desktop": self.desktop, "display": display}

    async def close(self):
        try:
            await self.browser.close()
        finally:
            try:
                await self.desktop.close()
            finally:
                self.globals.clear()


class Runtime:
    def __init__(self, cua_factory=CuaClient):
        self.sessions = {}
        self.cua_factory = cua_factory
        self.desktop_lock = asyncio.Lock()
        self.browser_lock = asyncio.Lock()
        self.playwright = None
        self.browser = None

    async def browser_context(self):
        async with self.browser_lock:
            if self.playwright is None:
                self.playwright = await async_playwright().start()
            if self.browser is None or not self.browser.is_connected():
                self.browser = await self.playwright.chromium.connect_over_cdp(
                    os.environ.get("SPARK_BROWSER_CDP", "http://127.0.0.1:19222"))
            if not self.browser.contexts:
                raise RuntimeError("Chromium has no existing browser context")
            return self.browser.contexts[0]

    @asynccontextmanager
    async def desktop_access(self, enabled):
        if not enabled:
            yield
            return
        async with self.desktop_lock:
            path = os.environ.get("SPARK_COMPUTER_LOCK",
                                  f"/run/user/{os.getuid()}/spark-computer.lock")
            with open(path, "a") as lock:
                while True:
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError:
                        await asyncio.sleep(0.05)
                try:
                    yield
                finally:
                    fcntl.flock(lock, fcntl.LOCK_UN)

    async def execute(self, session, code, desktop=False, timeout=60):
        output = Output(desktop)
        if not isinstance(session, str) or not session or len(session) > 80:
            return self.error("session must be a nonempty name of at most 80 characters")
        if not isinstance(code, str) or len(code) > 100_000:
            return self.error("code must be a string of at most 100000 characters")
        if type(desktop) is not bool or type(timeout) is not int or not 1 <= timeout <= 120:
            return self.error("desktop must be boolean; timeout must be an integer from 1 to 120")
        if session not in self.sessions:
            if len(self.sessions) >= 16:
                return self.error("Session limit reached; use computer_close first")
            self.sessions[session] = TaskSession(session, self)
        task = self.sessions[session]
        if task.lock.locked():
            return self.error(f"Session {session!r} is already executing")
        token = CURRENT.set(output)
        failed = False
        try:
            async with task.lock, asyncio.timeout(timeout):
                async with self.desktop_access(desktop):
                    compiled = compile(code, f"<computer:{session}>", "exec",
                                       flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)
                    result = eval(compiled, task.globals)
                    if inspect.isawaitable(result):
                        await result
        except TimeoutError:
            output.write(f"\nTimed out after {timeout}s; session variables are preserved. "
                         "An external operation may already have taken effect.\n")
            failed = True
        except asyncio.CancelledError:
            output.write("\nExecution cancelled; session variables are preserved.\n")
            failed = True
        except Exception as error:
            output.write(f"\n{type(error).__name__}: {error}\n")
            failed = True
        finally:
            output.active = False
            CURRENT.reset(token)
        if output.text_size >= TEXT_LIMIT:
            output.blocks.append(types.TextContent(type="text", text="[Text output truncated]"))
        return types.CallToolResult(content=output.blocks or [types.TextContent(type="text", text="Done")],
                                    isError=failed)

    @staticmethod
    def error(message):
        return types.CallToolResult(content=[types.TextContent(type="text", text=message)], isError=True)

    async def close_session(self, session):
        task = self.sessions.get(session)
        if task is None:
            return self.error("Unknown session")
        if task.lock.locked():
            return self.error("Session is executing; cancel or wait before closing it")
        async with task.lock:
            try:
                await task.close()
            except Exception as error:
                return self.error(f"Session discarded; resource cleanup failed: {error}")
            finally:
                del self.sessions[session]
        return types.CallToolResult(content=[types.TextContent(type="text", text="Session closed")])

    async def close(self):
        try:
            for task in list(self.sessions.values()):
                try:
                    await task.close()
                except Exception as error:
                    print(f"Session cleanup failed: {error}", file=sys.stderr)
            self.sessions.clear()
        finally:
            if self.playwright is not None:
                await self.playwright.stop()
            self.playwright = self.browser = None


server = Server("spark-computer")
runtime = Runtime()


@server.list_tools()
async def list_tools():
    return [types.Tool(name="computer_exec", description=(
        "Execute trusted Python with top-level await in a persistent named session. "
        "Use page = await browser.page() for your own tab in the logged-in Chromium context; "
        "await browser.tabs() lists metadata. display(await page.screenshot()) returns an image. "
        "print() returns text. desktop=true holds the shared desktop lock for this entire call; "
        "await desktop.describe() lists CUA tools, await desktop.describe('name') shows its schema, "
        "and await desktop.name(**kwargs) calls it, forwarding images automatically. "
        "Desktop calls return structured data or decoded JSON when available and raise on errors. "
        "Use computer_close when finished. No sandbox: run only trusted code. "
        "Timeouts are cooperative: use async APIs; blocking Python cannot be interrupted. "
        "Do not leave background tasks running between calls."), inputSchema={
            "type": "object", "properties": {
                "session": {"type": "string", "minLength": 1, "maxLength": 80},
                "code": {"type": "string", "maxLength": 100000},
                "desktop": {"type": "boolean", "default": False},
                "timeout": {"type": "integer", "minimum": 1, "maximum": 120, "default": 60}},
            "required": ["session", "code"], "additionalProperties": False}),
        types.Tool(name="computer_close", description=(
            "Close a named session's owned browser tab and CUA connection and discard Python variables. "
            "The attached browser, existing context, and other tabs remain open."), inputSchema={
                "type": "object", "properties": {"session": {"type": "string"}},
                "required": ["session"], "additionalProperties": False})]


@server.call_tool()
async def call_tool(name, arguments):
    if name == "computer_exec":
        return await runtime.execute(**arguments)
    if name == "computer_close":
        return await runtime.close_session(**arguments)
    return runtime.error(f"Unknown tool: {name}")


async def main():
    original_stdout = sys.stdout
    try:
        async with stdio_server() as (read, write):
            sys.stdout = CodeStdout()
            await server.run(read, write, server.create_initialization_options())
    finally:
        sys.stdout = original_stdout
        await runtime.close()


if __name__ == "__main__":
    asyncio.run(main())
