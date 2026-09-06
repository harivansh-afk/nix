import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { RoommateRouter, ownersFrom } from "./router.mjs";

function setup(t, run = async () => ({ reply: "Playing" })) {
  const directory = mkdtempSync(join(tmpdir(), "roommate-test-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  let number = 0;
  const router = new RoommateRouter({ directory, owners: new Set(["owner"]), run });
  const event = (text, sender = "guest", id = "group-a") => ({
    space: { type: "group", id }, sender: { id: sender }, messageId: `message-${++number}`,
    timestamp: new Date().toISOString(), content: { type: "text", text },
  });
  return { router, event, directory };
}
const ignore = async () => {};

test("only explicit DMs pass through to the personal agent", (t) => {
  const { router, event } = setup(t);
  assert.equal(router.take({ space: { type: "dm" } }, ignore), false);
  assert.equal(router.take({ space: { type: "unknown" } }, ignore), true);
  assert.equal(router.take(event("play something"), ignore), true);
});

test("only owner can enroll; guests cannot enroll or use admin commands", async (t) => {
  let calls = 0;
  const { router, event } = setup(t, async () => { calls++; return { reply: "Done" }; });
  router.take(event("/tv enable"), ignore);
  router.take(event("play"), ignore);
  await router.queue;
  assert.equal(calls, 0);
  router.take(event("/tv enable", "owner"), ignore);
  router.take(event("/model something"), ignore);
  router.take(event("play"), ignore);
  await router.queue;
  assert.equal(calls, 1);
});

test("chat boundary, deduplication and reply destination", async (t) => {
  const replies = [];
  let calls = 0;
  const { router, event } = setup(t, async () => { calls++; return { reply: "Done" }; });
  router.take(event("/tv enable", "owner"), ignore);
  const request = event("play");
  router.take(request, async (text) => replies.push(["group-a", text]));
  router.take(request, ignore);
  router.take(event("play", "guest", "group-b"), ignore);
  await router.queue;
  assert.equal(calls, 1);
  assert.deepEqual(replies, [["group-a", "Done"]]);
});

test("revocation drops queued work and replies", async (t) => {
  let release;
  const pending = new Promise((resolve) => { release = resolve; });
  let calls = 0;
  const { router, event } = setup(t, async () => { calls++; await pending; return { reply: "Done" }; });
  const replies = [];
  router.take(event("/tv enable", "owner"), ignore);
  router.take(event("play"), async (s) => replies.push(s));
  await new Promise((resolve) => setImmediate(resolve));
  router.take(event("play next"), ignore);
  router.take(event("/tv disable", "owner"), ignore);
  release();
  await router.queue;
  assert.equal(calls, 1);
  assert.deepEqual(replies, []);
});

test("stale messages cannot enroll and deduplication survives restart", async (t) => {
  const { router, event, directory } = setup(t);
  const stale = event("/tv enable", "owner");
  stale.timestamp = new Date(Date.now() - 600000).toISOString();
  router.take(stale, ignore);
  assert.deepEqual(router.state.groups, {});
  const enable = event("/tv enable", "owner");
  router.take(enable, ignore);
  const next = new RoommateRouter({ directory, owners: new Set(["owner"]), run: async () => { throw new Error("unexpected"); } });
  let replies = 0;
  next.take(enable, async () => { replies++; });
  assert.equal(replies, 0);
});

test("enrollment requires explicit owners", () => {
  assert.throws(() => ownersFrom(""));
  assert.throws(() => ownersFrom("*"));
  assert.deepEqual([...ownersFrom("owner, other")], ["owner", "other"]);
});

test("group history stays separate and queue admission is bounded", async (t) => {
  let release;
  const pending = new Promise((resolve) => { release = resolve; });
  const inputs = [];
  const { router, event } = setup(t, async (payload) => {
    inputs.push(payload);
    await pending;
    return { reply: "Done" };
  });
  router.take(event("/tv enable", "owner"), ignore);
  router.take(event("/tv enable", "owner", "group-b"), ignore);
  const replies = [];
  for (let i = 0; i < 5; i++) router.take(event(`request ${i}`), async (s) => replies.push(s));
  assert.equal(router.pending, 4);
  assert.equal(replies.length, 1);
  release();
  await router.queue;
  router.take(event("a different group", "guest", "group-b"), ignore);
  await router.queue;
  assert.deepEqual(inputs.at(-1).history, []);
});

test("missing sender or timestamp and prototype-shaped identities fail closed", (t) => {
  const { router, event } = setup(t);
  for (const change of [{sender: {}}, {timestamp: null}, {space: {id: "__proto__", type: "group"}}]) {
    router.take({...event("/tv enable", "owner"), ...change}, ignore);
  }
  assert.deepEqual(router.state.groups, {});
});
