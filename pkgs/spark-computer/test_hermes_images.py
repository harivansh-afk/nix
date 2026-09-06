"""Run with Hermes' Python environment and HERMES_TEST_SOURCE pointing at patched source."""

import asyncio
import base64
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, os.environ["HERMES_TEST_SOURCE"])

from PIL import Image
from mcp.types import CallToolResult, ImageContent, TextContent
from agent.tool_dispatch_helpers import _is_multimodal_tool_result, _multimodal_text_summary
from gateway.platforms import base
from tools import mcp_tool, mcp_tool_handlers as handlers, vision_tools

_NATIVE_GATE = vision_tools._should_use_native_vision_fast_path


class MCPNativeImageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.enterContext(patch.object(base, "IMAGE_CACHE_DIR", Path(self.tmp.name)))
        self.native = self.enterContext(patch.object(
            vision_tools, "_should_use_native_vision_fast_path", return_value=True))
        self.cache = self.enterContext(patch.object(
            base, "cache_image_from_bytes", wraps=base.cache_image_from_bytes))
        buf = io.BytesIO()
        Image.new("RGB", (24, 16), "#2078bc").save(buf, format="PNG")
        self.png = buf.getvalue()
        self.image = ImageContent(type="image", mimeType="image/png",
                                  data=base64.b64encode(self.png).decode("ascii"))

    def render(self, *content, **kwargs):
        return handlers._render_call_tool_result(
            CallToolResult(content=list(content), **kwargs), "spark-computer")

    def assert_image_result(self, result, count=1):
        self.assertTrue(_is_multimodal_tool_result(result))
        self.assertEqual(_multimodal_text_summary(result), result["text_summary"])
        self.assertEqual(result["content"][0], {"type": "text", "text": result["text_summary"]})
        images = result["content"][1:]
        self.assertEqual(len(images), count)
        for part in images:
            self.assertEqual(part["type"], "image_url")
            header, encoded = part["image_url"]["url"].split(",", 1)
            self.assertEqual(header, "data:image/png;base64")
            self.assertEqual(base64.b64decode(encoded), self.png)
        self.assertNotIn(self.image.data, result["text_summary"])
        summary = json.loads(result["text_summary"])
        paths = [line.removeprefix("MEDIA:") for line in summary["result"].splitlines()
                 if line.startswith("MEDIA:")]
        self.assertEqual(len(paths), count)
        for path in paths:
            self.assertEqual(Path(path).read_bytes(), self.png)
        self.assertEqual(self.cache.call_count, count)
        return summary

    def test_real_image_and_metadata_reach_native_content(self):
        result = self.render(TextContent(type="text", text="Screenshot captured"), self.image,
                             structuredContent={"duplicate": True},
                             _meta={"com.example/view": "desktop", "mcp.io/private": True})
        summary = self.assert_image_result(result)
        self.assertTrue(summary["result"].startswith("Screenshot captured\nMEDIA:"))
        self.assertEqual(summary["_meta"], {"com.example/view": "desktop"})
        self.assertNotIn("structuredContent", summary)

    def test_multiple_images_are_cached_once_each(self):
        self.assert_image_result(self.render(self.image, self.image), count=2)

    def test_sync_handler_preserves_dictionary(self):
        server = SimpleNamespace(_rpc_lock=asyncio.Lock(), session=SimpleNamespace(
            call_tool=AsyncMock(return_value=CallToolResult(content=[self.image]))))
        with patch.object(handlers, "_trust_gate_check", return_value=None), \
                patch.object(handlers, "_check_circuit_breaker", return_value=None), \
                patch.object(handlers, "_acquire_call_server", return_value=(server, None)), \
                patch.object(mcp_tool, "_reset_server_error"), \
                patch.object(handlers._loop, "_run_on_mcp_loop",
                             side_effect=lambda call, timeout: asyncio.run(call())):
            result = handlers._make_tool_handler("spark-computer", "screenshot", 30)({})
        self.assert_image_result(result)
        server.session.call_tool.assert_awaited_once_with("screenshot", arguments={})

    def test_native_gate_receives_context_across_real_mcp_loop(self):
        from agent.auxiliary_client import _read_main_model, _read_main_provider, scoped_runtime_main
        loop = asyncio.new_event_loop()
        thread = threading.Thread(target=loop.run_forever, daemon=True)
        ready = threading.Event()
        thread.start()
        loop.call_soon_threadsafe(ready.set)
        self.assertTrue(ready.wait(5))
        self.native.side_effect = _NATIVE_GATE
        cfg = {"model": {"supports_vision": True}}

        async def render_in_loop():
            self.assertEqual(_read_main_provider(), "openai-codex")
            self.assertEqual(_read_main_model(), "gpt-6-astra")
            return self.render(self.image)

        try:
            with patch.object(mcp_tool, "_mcp_loop", loop), \
                    patch("hermes_cli.config.load_config", return_value=cfg), \
                    scoped_runtime_main({"provider": "openai-codex", "model": "gpt-6-astra"}):
                result = handlers._loop._run_on_mcp_loop(render_in_loop, timeout=5)
            self.assert_image_result(result)
        finally:
            loop.call_soon_threadsafe(loop.stop)
            thread.join(5)
            loop.close()

    def test_nonvision_preserves_media_json(self):
        self.native.return_value = False
        result = self.render(self.image)
        self.assertIsInstance(result, str)
        self.assertTrue(json.loads(result)["result"].startswith("MEDIA:"))
        self.assertNotIn(self.image.data, result)
        self.cache.assert_called_once()

    def test_text_and_structured_results_preserve_serialization(self):
        self.assertEqual(self.render(TextContent(type="text", text="hello")), '{"result": "hello"}')
        self.assertEqual(self.render(structuredContent={"value": 7}), '{"result": {"value": 7}}')
        self.assertEqual(self.render(_meta={"example/view": "desktop"}),
                         '{"_meta": {"example/view": "desktop"}, "result": ""}')
        self.assertEqual(self.render(), '{"result": ""}')
        self.native.assert_not_called()
        self.cache.assert_not_called()

    def test_errors_preserve_failure_and_attach_available_images(self):
        result = self.render(TextContent(type="text", text="assertion failed"), self.image, isError=True)
        self.assertTrue(_is_multimodal_tool_result(result))
        self.assertTrue(handlers._result_is_error(result))
        self.assertEqual(json.loads(result["text_summary"])["error"], "assertion failed")
        self.assertEqual(result["content"][0]["text"], result["text_summary"])
        encoded = result["content"][1]["image_url"]["url"].split(",", 1)[1]
        self.assertEqual(base64.b64decode(encoded), self.png)
        self.assertNotIn(self.image.data, result["text_summary"])
        self.cache.assert_called_once()
        with patch.object(mcp_tool, "_bump_server_error") as bump, \
                patch.object(mcp_tool, "_reset_server_error") as reset:
            self.assertIs(handlers._record_call_outcome("spark-computer", result), result)
        bump.assert_called_once_with("spark-computer")
        reset.assert_not_called()

    def test_errors_without_images_retain_plain_json(self):
        result = self.render(TextContent(type="text", text="capture failed"), isError=True)
        self.assertIsInstance(result, str)
        self.assertEqual(json.loads(result)["error"], "capture failed")
        self.assertTrue(handlers._result_is_error(result))
        self.native.assert_not_called()
        self.cache.assert_not_called()

    def test_error_with_broken_image_preserves_failure(self):
        invalid = ImageContent(type="image", mimeType="image/png", data="bm90IGFuIGltYWdl")
        result = self.render(TextContent(type="text", text="capture failed"), invalid, isError=True)
        self.assertIsInstance(result, str)
        self.assertEqual(json.loads(result)["error"], "capture failed")
        self.assertTrue(handlers._result_is_error(result))
        self.native.assert_not_called()

    def test_nonvision_error_keeps_original_error_payload(self):
        self.native.return_value = False
        result = self.render(TextContent(type="text", text="capture failed"), self.image, isError=True)
        self.assertIsInstance(result, str)
        self.assertEqual(json.loads(result)["error"], "capture failed")
        self.assertTrue(handlers._result_is_error(result))

    def test_attachment_failure_preserves_media_text(self):
        with patch.object(vision_tools, "_resize_image_for_vision", side_effect=OSError("unreadable")):
            result = self.render(TextContent(type="text", text="captured"), self.image)
        self.assertIsInstance(result, str)
        self.assertTrue(json.loads(result)["result"].startswith("captured\nMEDIA:"))
        self.cache.assert_called_once()

    def test_invalid_image_does_not_become_native_content(self):
        invalid = ImageContent(type="image", mimeType="image/png", data="bm90IGFuIGltYWdl")
        result = self.render(TextContent(type="text", text="no screenshot"), invalid)
        self.assertEqual(json.loads(result), {"result": "no screenshot"})
        self.native.assert_not_called()


if __name__ == "__main__":
    unittest.main()
