"""Exercise Relay discovery and profile isolation using the packaged Hermes runtime."""

import json
import os
import shutil
from pathlib import Path

from agent.secret_scope import (
    build_profile_secret_scope,
    reset_secret_scope,
    set_multiplex_active,
    set_secret_scope,
)
from gateway.config import load_gateway_config
from gateway.platform_registry import platform_registry
from hermes_cli.plugins import PluginManager
from hermes_constants import reset_hermes_home_override, set_hermes_home_override


root = Path(os.environ["HERMES_HOME"])
configs = json.loads(Path(os.environ["profileConfigs"]).read_text())
for name, source in configs.items():
    home = root if name == "default" else root / "profiles" / name
    home.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, home / "config.yaml")
    (home / ".env").write_text("")

plugins = root / "plugins"
plugins.mkdir()
(plugins / "nix-managed-relay-hermes").symlink_to(os.environ["relaySource"])
personal = root / "profiles" / "imessage"
(personal / "plugins").symlink_to(plugins)
(root / ".env").write_text("ANTHROPIC_API_KEY=shared-api-key\n")
(personal / ".env").write_text(
    "RELAY_AGENT_TOKEN=relay-fixture-token\nRELAY_ALLOWED_CONTACTS=owner-contact\n"
)
os.environ["RELAY_AGENT_TOKEN"] = "ambient-token-must-not-leak"

manager = PluginManager()
manager.discover_and_load()
plugin = next(item for item in manager.list_plugins() if item["name"] == "relay-hermes")
assert plugin["enabled"] and plugin["error"] is None, plugin
entry = platform_registry.get("relayapp")
assert entry is not None
set_multiplex_active(True)

for name in configs:
    home = root if name == "default" else root / "profiles" / name
    home_token = set_hermes_home_override(str(home))
    secrets = build_profile_secret_scope(home)
    scope_token = set_secret_scope(secrets, profile_home=str(home))
    try:
        config = load_gateway_config()
        enabled = {platform.value: value for platform, value in config.platforms.items() if value.enabled}
        assert "photon" not in enabled, (name, enabled.keys())
        if name == "imessage":
            assert "relayapp" in enabled, enabled.keys()
            assert "ANTHROPIC_API_KEY" not in secrets
            adapter = entry.adapter_factory(enabled["relayapp"])
            assert type(adapter).__name__ == "RelayAdapter"
            assert enabled["relayapp"].extra["allowed_contacts"] == ["owner-contact"]
            assert enabled["relayapp"].extra["token"] == "relay-fixture-token"
            assert adapter._allow_contact("owner-contact")
            assert not adapter._allow_contact("unknown-contact")
            assert adapter._inbox.path.parent == personal / "relay"
            settings = json.loads((home / "config.yaml").read_text())
            assert settings["model"]["provider"] == "anthropic"
            assert settings["model"]["default"] == "claude-opus-5-5"
            assert "beeper" in settings["platform_toolsets"]["relayapp"]
        else:
            assert "RELAY_AGENT_TOKEN" not in secrets
            assert "relayapp" not in enabled, (name, enabled.keys())
        if name == "default":
            assert secrets["ANTHROPIC_API_KEY"] == "shared-api-key"
            routes = {(route.platform, route.profile) for route in config.profile_routes}
            assert routes == {("relayapp", "imessage"), ("telegram", "roommates")}, routes
    finally:
        reset_secret_scope(scope_token)
        reset_hermes_home_override(home_token)

print("PASS: Relay loads, routes to the personal profile, and keeps credentials isolated; Photon is disabled")
