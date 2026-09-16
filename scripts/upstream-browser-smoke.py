"""Exercise pinned agent-browser against a disposable Chromium profile."""

import functools
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import urllib.request


def main():
    with tempfile.TemporaryDirectory(prefix="agent-browser-smoke-") as tmp:
        root = Path(tmp)
        (root / "index.html").write_text(
            '<title>Fixture</title><input aria-label="Name"><button hidden>Submit</button><output></output>'
            '<script>document.querySelector("input").oninput=()=>document.querySelector("button").hidden=false;'
            'document.querySelector("button").onclick=()=>document.querySelector("output").textContent='
            '"Saved "+document.querySelector("input").value;</script>'
        )
        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            functools.partial(http.server.SimpleHTTPRequestHandler, directory=tmp),
        )
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env = dict(os.environ, HOME=tmp, XDG_CONFIG_HOME=tmp, XDG_CACHE_HOME=tmp,
                   AGENT_BROWSER_DEFAULT_TIMEOUT="5000", AGENT_BROWSER_NAMESPACE=root.name)
        with (root / "browser.log").open("w") as log:
            browser = subprocess.Popen(
                [os.environ["CHROMIUM"], "--headless", "--disable-gpu", "--no-first-run",
                 "--password-store=basic", "--disable-background-timer-throttling",
                 "--disable-renderer-backgrounding", "--remote-debugging-address=127.0.0.1",
                 "--remote-debugging-port=0", f"--user-data-dir={tmp}/profile", "about:blank"],
                stdout=log, stderr=log, env=env,
            )
            sessions = []
            try:
                port_file = root / "profile/DevToolsActivePort"
                deadline = time.monotonic() + 30
                while not port_file.exists():
                    if browser.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError((root / "browser.log").read_text())
                    time.sleep(.1)
                port = port_file.read_text().splitlines()[0]

                def tabs():
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=5) as response:
                        return [t for t in json.load(response) if t["type"] == "page"]

                sentinel = tabs()[0]["id"]

                def run(session, *args, check=True):
                    start = time.monotonic()
                    result = subprocess.run(
                        [os.environ["AGENT_BROWSER"], "--session", session, "--cdp", port,
                         "--pin-tab", *args], env=env, cwd=tmp, text=True,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
                    )
                    print(args[0], round(time.monotonic() - start, 3), result.stdout[:1000])
                    if check:
                        assert result.returncode == 0, result.stderr + result.stdout
                    return result

                url = f"http://127.0.0.1:{server.server_port}/index.html"
                sessions.append("fixture-a")
                run("fixture-a", "open", url)
                run("fixture-a", "snapshot", "-i")
                run("fixture-a", "fill", "@e1", "upstream")


                run("fixture-a", "snapshot", "-i")
                run("fixture-a", "click", "@e2")
                assert "Saved upstream" in run("fixture-a", "get", "text", "output").stdout
                sessions.append("fixture-b")
                run("fixture-b", "open", url)
                assert len(tabs()) == 3
                assert "upstream" not in run("fixture-b", "get", "value", "input").stdout
                image = root / "acceptance.png"
                run("fixture-a", "screenshot", str(image))
                assert image.read_bytes().startswith(b"\x89PNG")
                run("fixture-a", "tab", "close")
                failure = run("fixture-a", "snapshot", "-i", check=False)
                assert failure.returncode != 0
                assert "tab_gone" in failure.stdout + failure.stderr or "closed" in failure.stdout + failure.stderr
                run("fixture-b", "tab", "close")
                assert len(tabs()) == 1 and tabs()[0]["id"] == sentinel
                assert tabs()[0]["url"] == "about:blank"
                print("PASS: form, dynamic button, screenshot, two pinned sessions, tab-loss refusal, sentinel preservation")
            finally:
                for session in sessions:
                    subprocess.run([os.environ["AGENT_BROWSER"], "--session", session, "close"],
                                   env=env, cwd=tmp, capture_output=True, timeout=15)
                browser.terminate()
                browser.wait(timeout=15)
                server.shutdown()
                server.server_close()


if __name__ == "__main__":
    main()
