"""Native MCP smoke on a private Sway, D-Bus, Cua socket and disposable GTK app."""

import asyncio
import base64
import os
from pathlib import Path
import subprocess
import tempfile
import time
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main():
    with tempfile.TemporaryDirectory(prefix="upstream-native-") as tmp:
        root = Path(tmp)
        env = dict(
            os.environ,
            HOME=tmp,
            XDG_CONFIG_HOME=tmp,
            XDG_STATE_HOME=tmp,
            XDG_CACHE_HOME=tmp,
            XDG_RUNTIME_DIR=tmp,
            WLR_BACKENDS="headless",
            WLR_RENDERER="pixman",
            XDG_CURRENT_DESKTOP="sway",
            XDG_SESSION_TYPE="wayland",
            CUA_DRIVER_RS_ENABLE_WAYLAND="1",
            CUA_DRIVER_RS_TELEMETRY_ENABLED="0",
            GTK_A11Y="atspi",
            NO_AT_BRIDGE="0",
        )
        for key in [
            "DISPLAY",
            "WAYLAND_DISPLAY",
            "SWAYSOCK",
            "DBUS_SESSION_BUS_ADDRESS",
        ]:
            env.pop(key, None)
        processes = []
        with (root / "log").open("w") as log:

            def start(args, **kwargs):
                p = subprocess.Popen(args, env=env, stderr=log, stdout=log, **kwargs)
                processes.append(p)
                return p

            bus = subprocess.Popen(
                ["dbus-daemon", "--session", "--nofork", "--print-address=1"],
                env=env,
                stdout=subprocess.PIPE,
                stderr=log,
                text=True,
            )
            processes.append(bus)
            env["DBUS_SESSION_BUS_ADDRESS"] = bus.stdout.readline().strip()
            try:
                (root / "sway.conf").write_text(
                    "xwayland disable\noutput HEADLESS-1 mode 800x600\nseat seat0 fallback true\n"
                )
                start(
                    ["sway", "--unsupported-gpu", "--config", str(root / "sway.conf")]
                )
                deadline = time.monotonic() + 20
                while not list(root.glob("sway-ipc.*.sock")) or not list(
                    root.glob("wayland-*")
                ):
                    if time.monotonic() > deadline:
                        raise RuntimeError((root / "log").read_text())
                    await asyncio.sleep(0.1)
                env["SWAYSOCK"] = str(next(root.glob("sway-ipc.*.sock")))
                env["WAYLAND_DISPLAY"] = next(
                    p.name
                    for p in root.glob("wayland-*")
                    if not p.name.endswith(".lock")
                )
                subprocess.run(
                    [
                        "dbus-update-activation-environment",
                        "WAYLAND_DISPLAY",
                        "XDG_RUNTIME_DIR",
                        "XDG_SESSION_TYPE",
                        "GTK_A11Y",
                        "NO_AT_BRIDGE",
                    ],
                    env=env,
                    check=True,
                )
                driver = os.environ.get(
                    "CUA_DRIVER", "/run/current-system/sw/bin/cua-driver"
                )
                (root / "cua-driver").mkdir()
                socket = str(root / "cua-driver/control.sock")
                start([driver, "serve", "--socket", socket])
                app_output = (root / "app-output").open("w")
                app = subprocess.Popen(
                    [
                        os.environ["ZENITY"],
                        "--entry",
                        "--title=Upstream native fixture",
                        "--text=Disposable field",
                        "--entry-text=before",
                    ],
                    env=env,
                    stdout=app_output,
                    stderr=log,
                )
                processes.append(app)
                while not Path(socket).exists():
                    if time.monotonic() > deadline:
                        raise RuntimeError((root / "log").read_text())
                    await asyncio.sleep(0.1)
                params = StdioServerParameters(
                    command=os.environ.get("CUA_MCP", driver),
                    args=[]
                    if os.environ.get("CUA_MCP")
                    else ["mcp", "--socket", socket],
                    env=env,
                )
                async with stdio_client(params) as (r, w):
                    async with ClientSession(r, w) as client:
                        await client.initialize()
                        tools = (await client.list_tools()).tools
                        print("native tool count:", len(tools))

                        async def call(name, args):
                            started = time.monotonic()
                            result = await client.call_tool(name, args)
                            text = "\n".join(
                                c.text for c in result.content if c.type == "text"
                            )
                            print(
                                name, round(time.monotonic() - started, 3), text[:5000]
                            )
                            assert not getattr(
                                result, "is_error", getattr(result, "isError", False)
                            ), text
                            return result, getattr(
                                result,
                                "structured_content",
                                getattr(result, "structuredContent", None),
                            )

                        while True:
                            _, state = await call("list_windows", {"pid": app.pid})
                            windows = state.get("windows", [])
                            if windows:
                                break
                            if time.monotonic() > deadline:
                                raise RuntimeError((root / "log").read_text())
                            await asyncio.sleep(0.2)
                        window = windows[0]["window_id"]
                        for attempt in range(10):
                            result, state = await call(
                                "get_window_state",
                                {"pid": app.pid, "window_id": window},
                            )
                            if state["elements"]:
                                break
                            await asyncio.sleep(0.2)
                        if not state["elements"]:
                            print("fixture log:", (root / "log").read_text())
                            print("degraded state:", state)
                        images = [c for c in result.content if c.type == "image"]
                        assert images and base64.b64decode(images[0].data).startswith(
                            b"\x89PNG"
                        )
                        entry = next(
                            e for e in state["elements"] if e.get("role") == "text box"
                        )
                        await call(
                            "set_value",
                            {
                                "pid": app.pid,
                                "window_id": window,
                                "element_token": entry["element_token"],
                                "value": "verified upstream",
                            },
                        )
                        result, after = await call(
                            "get_window_state", {"pid": app.pid, "window_id": window}
                        )
                        image = next(c for c in result.content if c.type == "image")
                        if os.environ.get("NATIVE_EVIDENCE"):
                            Path(os.environ["NATIVE_EVIDENCE"]).write_bytes(
                                base64.b64decode(image.data)
                            )
                        button = next(
                            e
                            for e in after["elements"]
                            if e.get("label") == "OK" and e.get("role") == "button"
                        )
                        await call(
                            "click",
                            {
                                "pid": app.pid,
                                "window_id": window,
                                "element_token": button["element_token"],
                            },
                        )
                        await asyncio.to_thread(app.wait, timeout=10)
                        app_output.close()
                        assert app.returncode == 0
                        assert (
                            root / "app-output"
                        ).read_text().strip() == "verified upstream"
                        print(
                            "PASS: native image + background edit/click + app output readback"
                        )
            finally:
                for p in reversed(processes):
                    if p.poll() is None:
                        p.terminate()
                        try:
                            p.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            p.kill()
                            p.wait()
                print("native processes cleaned up")


asyncio.run(main())
