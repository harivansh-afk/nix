"""Offline lifecycle regressions: never contact a browser or the user manager."""

import asyncio
import os
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

import server


class BrowserLifecycleTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.context = SimpleNamespace(new_page=AsyncMock(), pages=[])
        self.browser = Mock(contexts=[self.context])
        self.browser.is_connected.return_value = True
        self.connect = AsyncMock(return_value=self.browser)
        self.runtime = server.Runtime()
        self.runtime.playwright = SimpleNamespace(
            chromium=SimpleNamespace(connect_over_cdp=self.connect))
        self.process = Mock(returncode=0)
        self.process.communicate = AsyncMock(return_value=(None, b""))
        self.process.wait = AsyncMock()
        self.spawn = patch.object(server.asyncio, "create_subprocess_exec",
                                  AsyncMock(return_value=self.process))
        self.start = self.spawn.start()
        self.addCleanup(self.spawn.stop)

    async def test_ready_browser_does_not_start_service(self):
        self.assertIs(await self.runtime.browser_context(), self.context)
        self.start.assert_not_awaited()
        self.connect.assert_awaited_once_with(server.MANAGED_CDP, timeout=1000)

    async def test_cold_start_retries_and_serializes_callers(self):
        self.connect.side_effect = [server.PlaywrightError("refused"),
                                   server.PlaywrightError("starting"), self.browser]
        contexts = await asyncio.gather(*(self.runtime.browser_context() for _ in range(3)))
        self.assertEqual(contexts, [self.context] * 3)
        self.start.assert_awaited_once_with(
            "systemctl", "--user", "start", "chromium.service",
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE)
        self.assertEqual(self.connect.await_count, 3)

    async def test_start_failure_is_actionable(self):
        self.connect.side_effect = server.PlaywrightError("refused")
        self.process.returncode = 1
        self.process.communicate.return_value = (None, b"Unit chromium.service is masked")
        with self.assertRaisesRegex(RuntimeError, "Could not start.*masked"):
            await self.runtime.browser_context()
        self.assertEqual(self.connect.await_count, 1)

    async def test_missing_systemctl(self):
        self.connect.side_effect = server.PlaywrightError("refused")
        self.start.side_effect = FileNotFoundError("systemctl")
        with self.assertRaisesRegex(RuntimeError, "Could not start.*systemctl"):
            await self.runtime.browser_context()

    async def test_readiness_timeout(self):
        self.connect.side_effect = server.PlaywrightError("refused")
        with patch.object(server, "BROWSER_START_TIMEOUT", 0.02):
            with self.assertRaisesRegex(RuntimeError, "CDP was not ready.*journal"):
                await self.runtime.browser_context()
        self.assertIsNone(self.runtime.browser)
        self.start.assert_awaited_once()

    async def test_hung_start_is_killed_and_reaped(self):
        self.connect.side_effect = server.PlaywrightError("refused")
        self.process.returncode = None

        async def hang():
            await asyncio.Event().wait()
        self.process.communicate.side_effect = hang
        with patch.object(server, "BROWSER_START_TIMEOUT", 0.02):
            with self.assertRaisesRegex(RuntimeError, "CDP was not ready"):
                await self.runtime.browser_context()
        self.process.kill.assert_called_once()
        self.process.wait.assert_awaited_once()

    async def test_cancelled_start_is_killed_and_reaped(self):
        self.connect.side_effect = server.PlaywrightError("refused")
        self.process.returncode = None
        entered = asyncio.Event()
        async def hang():
            entered.set()
            await asyncio.Event().wait()
        self.process.communicate.side_effect = hang
        task = asyncio.create_task(self.runtime.browser_context())
        await entered.wait()
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.process.kill.assert_called_once()
        self.process.wait.assert_awaited_once()

    async def test_custom_endpoints_never_start_local_service(self):
        for endpoint in ["http://remote:19222", "http://127.0.0.1:9222",
                         "ws://127.0.0.1:19222/devtools/browser/custom"]:
            with self.subTest(endpoint=endpoint), patch.dict(os.environ, SPARK_BROWSER_CDP=endpoint):
                self.connect.side_effect = server.PlaywrightError("unavailable")
                with self.assertRaises(server.PlaywrightError):
                    await self.runtime.browser_context()
                self.connect.assert_awaited_with(endpoint, timeout=15000)
        self.start.assert_not_awaited()

    async def test_explicit_managed_endpoint_can_start(self):
        with patch.dict(os.environ, SPARK_BROWSER_CDP=server.MANAGED_CDP):
            self.connect.side_effect = [server.PlaywrightError("refused"), self.browser]
            await self.runtime.browser_context()
        self.start.assert_awaited_once()

    async def test_reconnect_after_browser_exit(self):
        stale = Mock()
        stale.is_connected.return_value = False
        self.runtime.browser = stale
        self.connect.side_effect = [server.PlaywrightError("refused"), self.browser]
        self.assertIs(await self.runtime.browser_context(), self.context)
        self.assertIs(self.runtime.browser, self.browser)

    async def test_missing_context_is_not_replaced(self):
        self.browser.contexts = []
        with self.assertRaisesRegex(RuntimeError, "no existing browser context"):
            await self.runtime.browser_context()
        self.start.assert_not_awaited()

    async def test_session_owns_only_its_tab(self):
        existing = Mock()
        owned = Mock(is_closed=Mock(return_value=False), close=AsyncMock())
        self.context.pages = [existing]
        self.context.new_page.return_value = owned
        helper = server.Browser(self.runtime)
        token = server.CURRENT.set(server.Output(False))
        try:
            self.assertIs(await helper.page(), owned)
            self.assertIs(await helper.page(), owned)
            await helper.close()
        finally:
            server.CURRENT.reset(token)
        self.context.new_page.assert_awaited_once()
        owned.close.assert_awaited_once()
        existing.close.assert_not_called()
        self.browser.close.assert_not_called()

    async def test_closed_owned_tab_requires_new_session_without_start(self):
        helper = server.Browser(self.runtime)
        helper.owned_page = Mock(is_closed=Mock(return_value=True))
        token = server.CURRENT.set(server.Output(False))
        try:
            with self.assertRaisesRegex(RuntimeError, "computer_close"):
                await helper.page()
        finally:
            server.CURRENT.reset(token)
        self.start.assert_not_awaited()
        self.connect.assert_not_awaited()


class ExecutionTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.runtime = server.Runtime(cua_factory=Mock())

    async def asyncTearDown(self):
        await self.runtime.close()

    @staticmethod
    def text(result):
        return "\n".join(block.text for block in result.content if block.type == "text")

    async def test_error_survives_full_stdout_and_preserves_variables(self):
        result = await self.runtime.execute("task", "value = 42; print('x' * 65536); raise ValueError('broken')")
        self.assertTrue(result.isError)
        self.assertIn("ValueError: broken", self.text(result))
        result = await self.runtime.execute("task", "print(value)")
        self.assertFalse(result.isError)
        self.assertEqual(self.text(result), "42\n")

    async def test_diagnostic_is_bounded(self):
        result = await self.runtime.execute("task", "raise ValueError('x' * 10000)")
        self.assertTrue(result.isError)
        self.assertEqual(len(self.text(result)), 4096)

    async def test_inner_timeout_is_not_execution_deadline(self):
        result = await self.runtime.execute("task", "raise TimeoutError('upstream wait failed')")
        self.assertTrue(result.isError)
        self.assertIn("TimeoutError: upstream wait failed", self.text(result))
        self.assertNotIn("Timed out after", self.text(result))

    async def test_deadline_survives_full_stdout(self):
        result = await self.runtime.execute("task", "print('x' * 65536); await asyncio.Event().wait()", timeout=1)
        self.assertTrue(result.isError)
        self.assertIn("Timed out after 1s", self.text(result))

    async def test_cancellation_survives_full_stdout_and_overlap_is_rejected(self):
        self.runtime.sessions["task"] = server.TaskSession("task", self.runtime)
        entered = asyncio.Event()
        self.runtime.sessions["task"].globals["entered"] = entered
        task = asyncio.create_task(self.runtime.execute(
            "task", "print('x' * 65536); entered.set(); await asyncio.Event().wait()"))
        await entered.wait()
        overlap = await self.runtime.execute("task", "print('must not execute')")
        self.assertTrue(overlap.isError)
        self.assertIn("already executing", self.text(overlap))
        task.cancel()
        result = await task
        self.assertTrue(result.isError)
        self.assertIn("Execution cancelled", self.text(result))

    async def test_desktop_requires_opt_in_without_connecting(self):
        result = await self.runtime.execute("task", "await desktop.describe()")
        self.assertTrue(result.isError)
        self.assertIn("require computer_exec(desktop=true)", self.text(result))
        self.runtime.cua_factory.assert_not_called()
        self.assertIsNone(self.runtime.playwright)


if __name__ == "__main__":
    unittest.main()
