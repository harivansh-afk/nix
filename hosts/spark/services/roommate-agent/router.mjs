import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, renameSync } from "node:fs";
import { join } from "node:path";

export function ownersFrom(value = "") {
  const users = value.split(",").map((s) => s.trim()).filter(Boolean);
  if (!users.length || users.includes("*")) throw new Error("TV enrollment needs explicit owners");
  return new Set(users);
}

export class RoommateRouter {
  constructor({ directory, owners, run, now = Date.now }) {
    this.directory = directory;
    this.owners = owners;
    this.run = run;
    this.now = now;
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    try {
      this.state = JSON.parse(readFileSync(join(directory, "groups.json"), "utf8"));
      if (!this.state.groups || !Array.isArray(this.state.seen)) throw new Error("Invalid enrollment state");
    } catch (e) {
      if (e.code !== "ENOENT") throw e;
      this.state = { groups: {}, seen: [] };
    }
    this.queue = Promise.resolve();
    this.pending = 0;
    this.active = new Map();
  }

  save() {
    const temporary = join(this.directory, "groups.tmp");
    writeFileSync(temporary, JSON.stringify(this.state), { mode: 0o600 });
    renameSync(temporary, join(this.directory, "groups.json"));
  }

  take(event, reply) {
    if (event.space?.type === "dm") return false;
    // Unknown types also fail closed. Nothing besides an explicit DM reaches the personal agent.
    if (event.space?.type !== "group") return true;
    const id = event.space.id;
    const sender = event.sender?.id;
    const message = event.messageId;
    const timestamp = Date.parse(event.timestamp);
    const age = this.now() - timestamp;
    if (![id, sender, message].every((s) => typeof s === "string" && s.length > 0 && s.length <= 256 && !["__proto__", "constructor", "prototype"].includes(s)) || !Number.isFinite(age) || age < -60000 || age > 300000) return true;
    if (this.state.seen.includes(message)) return true;
    this.state.seen = [...this.state.seen.slice(-499), message];
    this.save();
    if (event.content?.type !== "text" || typeof event.content.text !== "string") return true;
    const text = event.content.text.trim();
    if (!text || text.length > 4000) return true;
    const command = text.toLowerCase();
    if (this.owners.has(sender) && ["/tv enable", "/tv disable"].includes(command)) {
      if (command === "/tv enable") {
        this.state.groups[id] ??= { history: [] };
      } else {
        delete this.state.groups[id];
        this.active.get(id)?.abort();
      }
      this.save();
      void reply(command === "/tv enable"
        ? "TV control is enabled for this group. Everyone in this group, including future members, can request playback. Personal tools remain private."
        : "TV control is disabled for this group.").catch(() => {});
      return true;
    }
    const group = this.state.groups[id];
    if (!group || text.startsWith("/")) return true;
    if (this.pending >= 4) {
      void reply("The TV queue is full; try again shortly.").catch(() => {});
      return true;
    }
    this.pending++;
    this.queue = this.queue.then(async () => {
      if (this.state.groups[id] !== group) return;
      const controller = new AbortController();
      this.active.set(id, controller);
      let answer;
      try {
        answer = await this.run({ text, history: group.history }, controller.signal);
      } finally {
        this.active.delete(id);
      }
      if (this.state.groups[id] !== group) return;
      const response = typeof answer.reply === "string" ? answer.reply.slice(0, 6000) : "TV control failed. Please try again.";
      if (!response.trim()) return;
      group.history = [...group.history, { role: "user", content: text },
        { role: "assistant", content: response }].slice(-12);
      this.save();
      await reply(response);
    }).catch(async () => {
      if (this.state.groups[id] === group) await reply("TV control failed. Please try again.").catch(() => {});
    }).finally(() => { this.pending--; });
    return true;
  }
}

export function runWorker(command, payload, signal) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, [], { stdio: ["pipe", "pipe", "ignore"], detached: true });
    let output = "";
    const kill = () => { try { process.kill(-child.pid, "SIGKILL"); } catch {} };
    const abort = () => { kill(); reject(new Error("TV access revoked")); };
    signal?.addEventListener("abort", abort, { once: true });
    const timer = setTimeout(() => { kill(); reject(new Error("TV worker timed out")); }, 180000);
    child.stdout.on("data", (chunk) => {
      output += chunk;
      if (output.length > 65536) { kill(); reject(new Error("TV response too large")); }
    });
    child.on("error", reject);
    child.on("close", (code) => {
      clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
      if (code !== 0) return reject(new Error("TV worker failed"));
      try { resolve(JSON.parse(output)); } catch (error) { reject(error); }
    });
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify(payload));
  });
}

let router;
export function routeGroup(event, reply) {
  if (event.space?.type === "dm") return false;
  if (!process.env.ROOMMATE_WORKER) return true;
  try {
    router ??= new RoommateRouter({ directory: process.env.ROOMMATE_STATE,
      owners: ownersFrom(process.env.PHOTON_ALLOWED_USERS),
      run: (payload, signal) => runWorker(process.env.ROOMMATE_WORKER, payload, signal) });
    return router.take(event, reply);
  } catch {
    console.error("Roommate routing failed; group message withheld from personal agent");
    return true;
  }
}
