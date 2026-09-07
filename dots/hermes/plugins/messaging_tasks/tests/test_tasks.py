"""Isolated contract tests; no model, gateway, browser or MCP calls."""

import copy
import json
import unittest
from types import SimpleNamespace
from unittest.mock import Mock

from agent.subagent_lifecycle import SubagentHandle

from dots.hermes.plugins.messaging_tasks import MessagingTasks, worker_result


class State:
    def __init__(self):
        self.data = {}

    def get(self, key, default=None):
        return copy.deepcopy(self.data.get(key, default))

    def set(self, key, value):
        self.data[key] = copy.deepcopy(value)


def result(summary, state="SUCCEEDED"):
    return SimpleNamespace(
        terminal_state=SimpleNamespace(value=state),
        summary=summary,
        error_message=None,
        error_classification=None,
    )


class ReportTests(unittest.TestCase):
    def test_invalid_or_incomplete_reports_are_uncertain(self):
        for text in ("done", "{}", "null", '{"status":"completed"}'):
            with self.subTest(text=text):
                self.assertEqual(worker_result(result(text))["state"], "uncertain")

    def test_waiting_question_is_preserved(self):
        report = {
            "status": "waiting_for_input",
            "summary": "Need a course",
            "evidence": [],
            "artifacts": [],
            "remaining": ["Check homework"],
            "question": "Which course?",
        }
        self.assertEqual(worker_result(result(json.dumps(report)))["result"], report)

    def test_outstanding_requirements_cannot_be_completed(self):
        report = {
            "status": "completed",
            "summary": "Done",
            "evidence": [],
            "artifacts": [],
            "remaining": ["Verify file"],
            "question": "",
        }
        self.assertEqual(
            worker_result(result(json.dumps(report)))["state"], "uncertain"
        )


class AdmissionTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        config = {
            "max_active": 1,
            "worker_model": "configured-worker",
            "worker_toolsets": ["file"],
        }
        self.ctx = SimpleNamespace(
            state=State(),
            get_config=lambda key, default=None: config.get(key, default),
            subagent_lifecycle=Mock(),
            spawn_task=lambda coroutine, **kwargs: coroutine.close(),
        )
        self.ctx.subagent_lifecycle.launch.return_value = SubagentHandle(
            1,
            "child",
            "session",
            None,
            1.0,
            "provider",
            "configured-worker",
            "leaf",
            1,
            "private-token",
        )
        self.tasks = MessagingTasks(self.ctx)

    async def test_capacity_rejects_before_launch(self):
        await self.tasks.start({"goal": "first"}, "session", "route")
        with self.assertRaisesRegex(ValueError, "capacity"):
            await self.tasks.start({"goal": "second"}, "session", "route")
        self.assertEqual(self.ctx.subagent_lifecycle.launch.call_count, 1)

    async def test_launch_uses_config_and_never_exposes_handle(self):
        record = await self.tasks.start(
            {"goal": "work", "context": "Only read"}, "session", "route"
        )
        request = self.ctx.subagent_lifecycle.launch.call_args.args[0]
        self.assertEqual(request.model, "configured-worker")
        self.assertEqual(request.allowed_toolsets, ("file",))
        self.assertIn("Only read", request.context)
        self.assertNotIn("private-token", json.dumps(record))
        with self.assertRaisesRegex(ValueError, "Unknown task"):
            self.tasks.owned(record["id"], "other-session", "route")
        with self.assertRaisesRegex(ValueError, "Unknown task"):
            self.tasks.owned(record["id"], "session", "other-route")

    async def test_continuation_claim_is_unique(self):
        record = await self.tasks.start({"goal": "work"}, "session", "route")
        prior = self.tasks.update(
            record["id"],
            state="waiting_for_input",
            result={"question": "Which course?"},
        )
        follow_up = await self.tasks.start(
            {"input": "CS2150"}, "session", "route", predecessor=prior
        )
        current = self.tasks.owned(record["id"], "session", "route")
        self.assertEqual(current["state"], "continued")
        self.assertIn(
            "CS2150", self.ctx.subagent_lifecycle.launch.call_args.args[0].context
        )
        self.tasks.update(follow_up["id"], state="completed")
        with self.assertRaisesRegex(ValueError, "already has a continuation"):
            await self.tasks.start(
                {"input": "Again"}, "session", "route", predecessor=prior
            )
        self.assertEqual(self.ctx.subagent_lifecycle.launch.call_count, 2)

    async def test_failed_admission_releases_capacity(self):
        self.ctx.subagent_lifecycle.launch.side_effect = ValueError("refused")
        with self.assertRaisesRegex(ValueError, "refused"):
            await self.tasks.start({"goal": "work"}, "session", "route")
        self.assertEqual(
            next(iter(self.ctx.state.get("tasks").values()))["state"], "failed"
        )

    async def test_lost_handle_is_not_replayed(self):
        record = await self.tasks.start({"goal": "work"}, "session", "route")
        self.ctx.subagent_lifecycle.result.return_value = SimpleNamespace(
            ready=False, error_classification="UNKNOWN_HANDLE"
        )
        saved = self.tasks.owned(record["id"], "session", "route")
        self.assertEqual(self.tasks.refresh(saved)["state"], "uncertain")
        self.assertEqual(self.ctx.subagent_lifecycle.launch.call_count, 1)
