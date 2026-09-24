"""Exercise generated Hermes provider routes and profile-scoped credentials offline."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace


def check_profile(name, source):
    with tempfile.TemporaryDirectory() as directory:
        home = Path(directory)
        os.environ["HERMES_HOME"] = str(home)
        config = json.loads(Path(source).read_text())
        if name == "roommates":
            assert config["model"]["provider"] == "openai-codex"
            assert config["model"]["default"] == "gpt-5.6-luna"
            assert "secrets" not in config
            return

        assert config["model"]["provider"] == "devin"
        assert config["providers"]["devin"]["key_env"] == "DEVIN_CODEX_TOKEN"
        token = "test-only-hermes-devin-token"
        (home / "token.env").write_text(f"DEVIN_CODEX_TOKEN={token}\n")
        command = config["secrets"]["command"]["command"]
        assert command.endswith(" /var/lib/hermes-devin/token.env")
        config["secrets"]["command"]["command"] = command.replace(
            "/var/lib/hermes-devin/token.env", str(home / "token.env")
        )
        (home / "config.yaml").write_text(json.dumps(config))

        from agent.secret_scope import build_profile_secret_scope, set_secret_scope
        from hermes_cli.env_loader import hydrate_profile_secret_sources
        from hermes_cli.runtime_provider import resolve_runtime_provider
        from tools.delegate_tool_config import _resolve_child_runtime

        hydrate_profile_secret_sources(home)
        scope = build_profile_secret_scope(home)
        assert scope["DEVIN_CODEX_TOKEN"] == token
        set_secret_scope(scope)
        runtime = resolve_runtime_provider()
        assert runtime["api_key"] == token
        assert runtime["provider"] == "custom"
        assert runtime["api_mode"] == "codex_responses"
        assert runtime["base_url"] == "http://127.0.0.1:19476/v1"

        parent = SimpleNamespace(
            model=config["model"]["default"],
            provider=runtime["provider"],
            base_url=runtime["base_url"],
            api_mode=runtime["api_mode"],
        )
        child = _resolve_child_runtime(
            parent, config.get("delegation", {}), runtime["api_key"],
            model=config.get("delegation", {}).get("model"),
            override_provider=None, override_base_url=None, override_api_key=None,
            override_api_mode=None, override_acp_command=None, override_acp_args=None,
        )
        for field in ("api_key", "provider", "api_mode", "base_url"):
            assert child[field] == runtime[field], field


if len(sys.argv) == 3:
    check_profile(*sys.argv[1:])
else:
    for name, source in json.loads(Path(sys.argv[1]).read_text()).items():
        subprocess.run([sys.executable, __file__, name, source], check=True)
        print(f"PASS: {name} provider and scoped credentials")
