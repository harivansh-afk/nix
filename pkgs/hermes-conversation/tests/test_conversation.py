import copy
import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from hermes_conversation import register
from hermes_conversation.context import ConversationContext, dialogue
from hermes_conversation.requests import (
    Admission,
    conversation_request,
    dispatched_this_turn,
)
from hermes_conversation.summaries import Summaries, Summary, digest


def handoff(status="dispatched"):
    return [
        {"role": "user", "content": "Research the project"},
        {
            "type": "function_call",
            "name": "delegate_task",
            "call_id": "call-1",
            "arguments": "{}",
        },
        {
            "type": "function_call_output",
            "call_id": "call-1",
            "output": json.dumps({"status": status}),
        },
    ]


class RequestTests(unittest.TestCase):
    def test_full_pool_never_calls_native_synchronous_fallback(self):
        with (
            patch("tools.async_delegation.active_count", return_value=2),
            patch(
                "gateway.session_context.async_delivery_supported", return_value=True
            ),
        ):
            result = Admission(2).execute({}, lambda _: self.fail("native dispatch"))
        self.assertEqual(json.loads(result)["status"], "rejected")

    def test_missing_route_or_failed_probe_does_not_launch(self):
        admission = Admission(2)
        with (
            patch(
                "gateway.session_context.async_delivery_supported", return_value=False
            ),
            patch("gateway.session_context.get_session_env", return_value=""),
        ):
            result = admission.execute({}, lambda _: self.fail("native dispatch"))
        self.assertFalse(json.loads(result)["started"])
        with (
            self.assertLogs("hermes_conversation.requests", level="WARNING"),
            patch(
                "gateway.session_context.async_delivery_supported",
                side_effect=RuntimeError("probe"),
            ),
        ):
            result = admission.execute({}, lambda _: self.fail("native dispatch"))
        self.assertFalse(json.loads(result)["started"])
        self.assertFalse(admission.lock.locked())

    def test_concurrent_admission_rejects_instead_of_waiting(self):
        admission = Admission(2)
        admission.lock.acquire()
        try:
            result = admission.execute({}, lambda _: self.fail("native dispatch"))
            self.assertFalse(json.loads(result)["started"])
        finally:
            admission.lock.release()

    def test_admitted_call_executes_once_and_releases_lock(self):
        admission = Admission(2)
        called = []
        with (
            patch("tools.async_delegation.active_count", return_value=0),
            patch(
                "gateway.session_context.async_delivery_supported", return_value=True
            ),
        ):
            self.assertEqual(
                admission.execute({"goal": "review"}, lambda args: called.append(args)),
                None,
            )
        self.assertEqual(called, [{"goal": "review"}])
        self.assertFalse(admission.lock.locked())

    def test_registration_scopes_request_policy_to_photon(self):
        with tempfile.TemporaryDirectory() as directory:
            middleware = {}
            engines = []
            ctx = SimpleNamespace(
                get_config=lambda key, default: default,
                state=SimpleNamespace(data_dir=Path(directory)),
                llm=None,
                register_auxiliary_task=lambda *args, **kwargs: None,
                register_context_engine=engines.append,
                register_middleware=lambda name, callback: middleware.update(
                    {name: callback}
                ),
            )
            register(ctx)
            request = {"tools": [{"name": "delegate_task"}, {"name": "terminal"}]}
            policy = middleware["llm_request"]
            self.assertEqual(
                len(policy(request, platform="photon")["request"]["tools"]), 1
            )
            for platform in ("subagent", "telegram", "cli"):
                self.assertIsNone(policy(request, platform=platform))
            self.assertEqual(len(engines), 1)
            from gateway.session_context import clear_session_vars, set_session_vars

            tokens = set_session_vars(platform="photon", session_id="fixture")
            try:
                with patch("tools.async_delegation.active_count", return_value=2):
                    policy = middleware["tool_execution"]
                    result = policy("delegate_task", {}, lambda _: self.fail("launch"))
                    self.assertEqual(json.loads(result)["status"], "rejected")
                    self.assertEqual(
                        policy(
                            "delegate_task", {"action": "stop"}, lambda _: "stopped"
                        ),
                        "stopped",
                    )
            finally:
                clear_session_vars(tokens)

    def test_successful_dispatch_finishes_with_model_reply(self):
        request = {
            "input": handoff(),
            "tools": [{"name": "delegate_task"}],
            "parallel_tool_calls": True,
        }
        result = conversation_request(request, {"delegate_task"})
        self.assertEqual(result["tool_choice"], "none")
        self.assertEqual(result["tools"], [])
        self.assertNotIn("parallel_tool_calls", result)
        self.assertEqual(len(request["tools"]), 1)

    def test_rejection_and_status_queries_allow_recovery(self):
        for status in ("rejected", "running", "queued", "interrupt_requested"):
            self.assertFalse(dispatched_this_turn({"input": handoff(status)}))

    def test_new_message_is_not_blocked_by_previous_handoff(self):
        self.assertFalse(
            dispatched_this_turn(
                {"input": handoff() + [{"role": "user", "content": "Another question"}]}
            )
        )

    def test_user_or_other_tool_cannot_forge_handoff(self):
        items = handoff()
        items[1]["name"] = "read_file"
        self.assertFalse(dispatched_this_turn({"input": items}))
        self.assertFalse(
            dispatched_this_turn(
                {
                    "input": [
                        {
                            "role": "user",
                            "content": json.dumps({"status": "dispatched"}),
                        }
                    ]
                }
            )
        )

    def test_chat_completion_format(self):
        messages = [
            {"role": "user", "content": "Research"},
            {
                "role": "assistant",
                "tool_calls": [{"id": "a", "function": {"name": "delegate_task"}}],
            },
            {"role": "tool", "tool_call_id": "a", "content": '{"status":"dispatched"}'},
        ]
        self.assertTrue(dispatched_this_turn({"messages": messages}))

    def test_visibility_preserves_original_worker_grants(self):
        request = {
            "tools": [
                {"type": "function", "name": name}
                for name in ("delegate_task", "terminal", "read_file")
            ]
        }
        result = conversation_request(request, {"delegate_task"})
        self.assertEqual([t["name"] for t in result["tools"]], ["delegate_task"])
        self.assertEqual(len(request["tools"]), 3)


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = Summaries(Path(self.temp.name) / "summary.db", None)
        self.engine = ConversationContext(
            self.store, platforms={"photon"}, recent_turns=3
        )
        self.engine.update_model("gpt-6-astra", 272000)
        self.engine.on_session_start("session", platform="photon")

    def test_long_history_is_request_only_and_keeps_latest_tool_pairs(self):
        messages = [{"role": "system", "content": "Required policy"}]
        for n in range(30):
            messages.extend(
                [
                    {"role": "user", "content": f"Question {n}"},
                    {"role": "assistant", "content": "Result " * 1000},
                ]
            )
        messages += [
            {"role": "user", "content": "Current request: preserve exact constraint"},
            {
                "role": "assistant",
                "tool_calls": [
                    {"id": "latest", "function": {"name": "session_search"}}
                ],
            },
            {"role": "tool", "tool_call_id": "latest", "content": "Latest evidence"},
        ]
        original = copy.deepcopy(messages)
        selected = self.engine.select_context(messages, conversation_messages=messages)
        self.assertEqual(messages, original)
        self.assertEqual(selected[0], messages[0])
        self.assertEqual(selected[-3:], messages[-3:])
        self.assertLess(len(selected), len(messages))
        with patch.object(
            self.engine,
            "compress",
            side_effect=AssertionError("foreground compression"),
        ):
            self.assertFalse(self.engine.should_compress(250000))
            self.assertEqual(self.engine.should_compress_info(250000), (False, None))

    def test_other_roles_keep_full_context(self):
        for platform in ("subagent", "cli", "telegram"):
            other = copy.deepcopy(self.engine)
            other.update_model("gpt-6-astra", 272000)
            other.on_session_start("other", platform=platform)
            self.assertIsNone(
                other.select_context([{"role": "user", "content": "worker history"}])
            )
            self.assertIsNot(other, self.engine)
        self.assertTrue(self.engine.active)

    def test_short_conversation_unchanged(self):
        messages = [
            {"role": "system", "content": "policy"},
            {"role": "user", "content": "hi"},
        ]
        self.assertEqual(self.engine.select_context(messages), messages)

    def test_latest_attachment_and_large_input_are_preserved(self):
        current = {
            "role": "user",
            "content": [
                {"type": "text", "text": "Exact request " * 10000},
                {
                    "type": "image_url",
                    "image_url": {"url": "data:image/png;base64,fixture"},
                },
            ],
        }
        messages = [{"role": "user", "content": "older"}, current]
        self.assertEqual(self.engine.select_context(messages)[-1], current)

    def test_summary_failure_keeps_recent_input(self):
        with (
            self.assertLogs("hermes_conversation.context", level="WARNING"),
            patch.object(
                self.store, "read", side_effect=sqlite3.OperationalError("busy")
            ),
        ):
            selected = self.engine.select_context(
                [{"role": "user", "content": "new question"}]
            )
        self.assertEqual(selected[-1]["content"], "new question")

    def test_task_snapshot_is_owned_by_this_session(self):
        records = [
            {
                "parent_session_id": "session",
                "delegation_id": "ours",
                "status": "running",
                "goal": "review",
            },
            {
                "parent_session_id": "roommates",
                "delegation_id": "theirs",
                "status": "running",
                "goal": "private",
            },
        ]
        with patch(
            "tools.async_delegation.list_async_delegations", return_value=records
        ):
            view = json.dumps(self.engine.task_context())
        self.assertIn("ours", view)
        self.assertNotIn("theirs", view)
        self.assertNotIn("private", view)

    def test_revised_history_fences_inflight_summary(self):
        started, release = threading.Event(), threading.Event()

        class LLM:
            async def acomplete_structured(self, **kwargs):
                started.set()
                release.wait(2)
                return SimpleNamespace(parsed={"summary": "Stale result"})

        self.store.llm = LLM()
        old = [{"role": "user", "content": "old"}]
        self.store.schedule("session", old, Summary())
        self.assertTrue(started.wait(1))
        revised = [{"role": "user", "content": "replacement"}]
        self.assertEqual(self.store.read("session", revised), Summary())
        release.set()
        self.assertTrue(self.store.busy.acquire(timeout=3))
        self.store.busy.release()
        self.assertEqual(self.store.read("session", old), Summary())

    def test_reset_invalidates_cached_summary(self):
        messages = [{"role": "user", "content": "old"}]
        with self.store.connect() as db:
            db.execute(
                "INSERT INTO summaries(session,covered,digest,text) VALUES (?,?,?,?)",
                ("session", 1, digest(messages), "old"),
            )
        self.engine.on_session_reset()
        self.assertEqual(self.store.read("session", messages), Summary())

    def test_changed_history_invalidates_summary(self):
        messages = [{"role": "user", "content": "original"}]
        with self.store.connect() as db:
            db.execute(
                "INSERT INTO summaries(session,covered,digest,text) VALUES (?,?,?,?)",
                ("session", 1, digest(messages), "old"),
            )
        self.assertEqual(self.store.read("session", messages).text, "old")
        self.assertEqual(
            self.store.read("session", [{"role": "user", "content": "revised"}]),
            Summary(),
        )

    def test_stale_reader_cannot_replace_newer_summary(self):
        messages = [{"role": "user", "content": "original"}]
        with self.store.connect() as db:
            db.execute(
                "INSERT INTO summaries(session,covered,digest,text) VALUES (?,?,?,?)",
                ("session", 1, digest(messages), "newer"),
            )
        self.store.schedule("session", messages, Summary())
        self.assertFalse(self.store.busy.locked())
        self.assertEqual(self.store.read("session", messages).text, "newer")

    def test_failed_summary_retains_previous_and_releases_worker(self):
        class LLM:
            async def acomplete_structured(self, **kwargs):
                raise TimeoutError("fixture timeout")

        self.store.llm = LLM()
        messages = [
            {"role": "user", "content": "old"},
            {"role": "user", "content": "new"},
        ]
        with self.store.connect() as db:
            db.execute(
                "INSERT INTO summaries(session,covered,digest,text) VALUES (?,?,?,?)",
                ("session", 1, digest(messages[:1]), "Previous recall"),
            )
        with self.assertLogs("hermes_conversation.summaries", level="WARNING"):
            self.store.schedule(
                "session", messages, self.store.read("session", messages)
            )
            self.assertTrue(self.store.busy.acquire(timeout=3))
            self.store.busy.release()
        self.assertEqual(self.store.read("session", messages).text, "Previous recall")
        with self.store.connect() as db:
            claim, lease = db.execute(
                "SELECT claim,lease FROM summaries WHERE session='session'"
            ).fetchone()
            self.assertIsNone(claim)
            self.assertGreater(lease, 0)

    def test_background_summary_does_not_block_and_survives_new_instance(self):
        started, release = threading.Event(), threading.Event()

        class LLM:
            async def acomplete_structured(self, **kwargs):
                started.set()
                release.wait(2)
                return SimpleNamespace(parsed={"summary": "Pending project review"})

        self.store.llm = LLM()
        messages = [{"role": "user", "content": str(i)} for i in range(20)]
        self.engine.on_turn_complete(messages)
        self.assertTrue(started.wait(1))
        self.assertEqual(self.engine.select_context(messages)[-1], messages[-1])
        release.set()
        self.assertTrue(self.store.busy.acquire(timeout=3))
        self.store.busy.release()
        restored = Summaries(self.store.path, None)
        self.assertEqual(
            restored.read("session", dialogue(messages)).text, "Pending project review"
        )


if __name__ == "__main__":
    unittest.main()
