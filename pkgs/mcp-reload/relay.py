"""Stdio MCP relay that swaps its child for the newly deployed build.

Usage: mcp-reload COMMAND [ARGS...]

COMMAND should be a stable path such as /run/current-system/sw/bin/webjit.
When its resolved target changes and no client request is in flight, the
relay starts the new build, replays the client's initialize handshake,
switches over, stops the old child and sends tools/list_changed.
"""

import json
import os
import subprocess
import sys
import threading
import time

POLL_SECONDS = 2
INIT_TIMEOUT = 60
INIT_ID = "mcp-reload-init"

argv = sys.argv[1:]
if not argv:
    sys.exit("usage: mcp-reload COMMAND [ARGS...]")

lock = threading.Lock()
out_lock = threading.Lock()
pending = set()
init_request = None
initialized_note = None
child = None
target = None


def log(msg):
    print(f"mcp-reload[{os.path.basename(argv[0])}]: {msg}", file=sys.stderr, flush=True)


def emit(line):
    with out_lock:
        sys.stdout.buffer.write(line)
        sys.stdout.buffer.flush()


def spawn():
    return subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE)


def send(proc, line):
    proc.stdin.write(line)
    proc.stdin.flush()


def parse(line):
    try:
        msg = json.loads(line)
    except ValueError:
        return None
    return msg if isinstance(msg, dict) else None


def pump(proc):
    for line in proc.stdout:
        msg = parse(line)
        if msg is not None and "method" not in msg and "id" in msg:
            if msg["id"] == INIT_ID:
                continue
            with lock:
                pending.discard(json.dumps(msg["id"]))
        emit(line)
    if proc is child:
        log(f"child exited with {proc.wait()}")
        os._exit(proc.returncode or 1)


def start(proc):
    threading.Thread(target=pump, args=(proc,), daemon=True).start()


def handshake(proc):
    reply = {}
    done = threading.Event()

    def read():
        for line in proc.stdout:
            msg = parse(line)
            if msg is not None and msg.get("id") == INIT_ID:
                reply.update(msg)
                done.set()
                return
        done.set()

    reader = threading.Thread(target=read, daemon=True)
    request = dict(init_request, id=INIT_ID)
    send(proc, (json.dumps(request) + "\n").encode())
    reader.start()
    if not done.wait(INIT_TIMEOUT) or "result" not in reply:
        return False
    reader.join()
    if initialized_note is not None:
        send(proc, initialized_note)
    return True


def swap():
    global child, target
    new_target = os.path.realpath(argv[0])
    proc = spawn()
    try:
        ok = handshake(proc)
    except OSError:
        ok = False
    if not ok:
        log(f"new build {new_target} failed to initialize; keeping the old one")
        proc.kill()
        target = new_target
        return
    old, child, target = child, proc, new_target
    start(proc)
    old.stdin.close()
    threading.Timer(10, old.kill).start()
    emit(b'{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}\n')
    log(f"reloaded {target}")


def watch():
    while True:
        time.sleep(POLL_SECONDS)
        if init_request is None or os.path.realpath(argv[0]) == target:
            continue
        with lock:
            if not pending:
                swap()


def main():
    global child, target, init_request, initialized_note
    target = os.path.realpath(argv[0])
    child = spawn()
    start(child)
    threading.Thread(target=watch, daemon=True).start()
    for line in sys.stdin.buffer:
        msg = parse(line)
        with lock:
            if msg is not None and "method" in msg:
                if msg["method"] == "initialize":
                    init_request = msg
                elif msg["method"] == "notifications/initialized":
                    initialized_note = line
                elif msg["method"] == "notifications/cancelled":
                    params = msg.get("params") or {}
                    pending.discard(json.dumps(params.get("requestId")))
                if "id" in msg and msg["method"] != "initialize":
                    pending.add(json.dumps(msg["id"]))
            try:
                send(child, line)
            except BrokenPipeError:
                break
    child.stdin.close()
    sys.exit(child.wait())


main()
