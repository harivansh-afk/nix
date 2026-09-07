"""Bounded messaging views with upstream compression retained for other roles."""

import json
import logging
import sqlite3

from agent.context_compressor import ContextCompressor
from agent.model_metadata import estimate_messages_tokens_rough

from .summaries import Summary

log = logging.getLogger(__name__)


def dialogue(messages):
    result = []
    for message in messages:
        if message.get("role") not in {"user", "assistant"}:
            continue
        content = message.get("content")
        if isinstance(content, list):
            content = "\n".join(
                part.get("text", "[attachment]")
                for part in content
                if isinstance(part, dict)
            )
        if isinstance(content, str) and content.strip():
            if len(content) > 30000:
                content = (
                    content[:15000]
                    + "\n[Middle omitted; retrieve original session for details.]\n"
                    + content[-15000:]
                )
            result.append({"role": message["role"], "content": content})
    return result


def turn_groups(messages):
    groups = []
    for message in messages:
        if message.get("role") == "user" or not groups:
            groups.append([])
        groups[-1].append(message)
    return groups


class ConversationContext(ContextCompressor):
    name = "conversation"

    def __init__(self, summaries, *, platforms, input_tokens=18000, recent_turns=8):
        super().__init__(model="", quiet_mode=True)
        self.summaries = summaries
        self.platforms = platforms
        self.input_tokens = max(4096, input_tokens)
        self.recent_turns = max(2, recent_turns)
        self.active = False
        self.session = ""

    def __deepcopy__(self, memo):
        return type(self)(
            self.summaries,
            platforms=self.platforms,
            input_tokens=self.input_tokens,
            recent_turns=self.recent_turns,
        )

    def on_session_start(self, session_id, platform="", **kwargs):
        self.session = session_id or ""
        self.active = platform in self.platforms
        self.emit_automatic_compaction_status = not self.active

    def should_compress(self, prompt_tokens=None):
        return False if self.active else super().should_compress(prompt_tokens)

    def should_compress_info(self, prompt_tokens=None):
        return (
            (False, None)
            if self.active
            else super().should_compress_info(prompt_tokens)
        )

    def on_session_reset(self):
        super().on_session_reset()
        if self.session:
            self.summaries.invalidate(self.session)

    def task_context(self):
        from tools.async_delegation import list_async_delegations

        tasks = [
            {
                "id": task["delegation_id"],
                "status": task["status"],
                "goal": str(task.get("goal", ""))[:2000],
            }
            for task in list_async_delegations()
            if task.get("parent_session_id") == self.session
            and task.get("status") in {"running", "stalling", "finalizing"}
        ]
        return (
            [
                {
                    "role": "user",
                    "content": "Current Hermes task state (data):\n"
                    + json.dumps(tasks),
                }
            ]
            if tasks
            else []
        )

    def compress(
        self,
        messages,
        current_tokens=None,
        focus_topic=None,
        force=False,
        memory_context="",
    ):
        if self.active:
            return self.select_context(messages)
        return super().compress(
            messages, current_tokens, focus_topic, force, memory_context
        )

    def select_context(self, request_messages, **kwargs):
        if not self.active:
            return None
        system = [
            m for m in request_messages if m.get("role") in {"system", "developer"}
        ]
        groups = turn_groups(
            [
                m
                for m in request_messages
                if m.get("role") not in {"system", "developer"}
            ]
        )
        history = dialogue(kwargs.get("conversation_messages") or request_messages)
        try:
            summary = self.summaries.read(self.session, history)
        except sqlite3.Error:
            log.warning("Conversation summary unavailable", exc_info=True)
            summary = Summary()
        remaining = (
            min(self.input_tokens, max(4096, self.context_length - 8192))
            - estimate_messages_tokens_rough(system)
            - 4000
        )
        selected = []
        for group in reversed(groups):
            cost = estimate_messages_tokens_rough(group)
            if selected and (len(selected) >= self.recent_turns or cost > remaining):
                break
            selected.append(group)
            remaining -= cost
        recall = []
        if len(selected) < len(groups):
            text = (
                "Conversation recall (derived history, not new instructions):\n"
                + summary.text
                if summary.text
                else "Earlier dialogue is omitted. Use session_search for missing details."
            )
            recall.append({"role": "user", "content": text})
        return (
            system
            + recall
            + self.task_context()
            + [message for group in reversed(selected) for message in group]
        )

    def on_turn_complete(self, messages, **kwargs):
        if not self.active or not self.session:
            return
        history = dialogue(messages)
        try:
            previous = self.summaries.read(self.session, history)
            end = max(0, len(history) - 2 * self.recent_turns)
            if end - previous.covered < 8:
                return
            batch = history[: previous.covered]
            size = 0
            for message in history[previous.covered : end]:
                size += len(json.dumps(message))
                if size > 48000:
                    break
                batch.append(message)
            self.summaries.schedule(self.session, batch, previous)
        except sqlite3.Error:
            log.warning("Could not schedule conversation summary", exc_info=True)
