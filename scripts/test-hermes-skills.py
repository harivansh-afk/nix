"""Exercise Nix skill selection and migration against the packaged Hermes runtime."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


settings, marker, bundled, migration = sys.argv[1:]
home = Path(os.environ["HERMES_HOME"])
config = json.loads(Path(settings).read_text())
assert config["skills"]["project_discovery"] is False
home.mkdir(parents=True, exist_ok=True)
(home / "config.yaml").write_text(json.dumps(config))
shutil.copyfile(marker, home / ".no-bundled-skills")
os.environ["HERMES_BUNDLED_SKILLS"] = bundled

local = home / "skills"
legacy = local / "autonomous-ai-agents" / "computer-use"
legacy.mkdir(parents=True)
(legacy / "SKILL.md").write_text("User-modified legacy skill\n")
(local / "custom-link").symlink_to(legacy, target_is_directory=True)
(local / ".old-skill").mkdir()
(local / ".old-skill/SKILL.md").write_text("Hidden runtime skill\n")
(local / ".bundled_manifest").write_text("computer-use:old-hash\n")
(home / "memories").mkdir(exist_ok=True)
(home / "memories" / "sentinel").write_text("keep personal memory\n")
backups = home.parent / "skills-backups"
subprocess.run(["bash", migration, str(home), str(backups)], check=True)
archived = list(backups.iterdir())
assert len(archived) == 1
assert (archived[0] / "autonomous-ai-agents/computer-use/SKILL.md").read_text() == "User-modified legacy skill\n"
assert (archived[0] / "custom-link").is_symlink()
assert (archived[0] / ".old-skill/SKILL.md").exists()
assert (archived[0].stat().st_mode & 0o777) == 0o700
assert (local / ".bundled_manifest").exists()
assert (home / "memories/sentinel").read_text() == "keep personal memory\n"
subprocess.run(["bash", migration, str(home), str(backups)], check=True)
assert list(backups.iterdir()) == archived

from tools.skills_sync import sync_skills
from tools.skills_tool import _find_all_skills, skill_view

expected = {p.name for root in config["skills"]["external_dirs"] for p in Path(root).iterdir()}
assert {"hermes-agent", "spark-computer", "cua-driver", "self-evolve"} <= expected
assert "computer-use" not in expected
for _ in range(2):
    result = sync_skills(quiet=True)
    assert result["skipped_opt_out"], result
    assert not result["copied"] and not result["updated"], result
    for platform in ("cli", "photon", "api_server"):
        os.environ["HERMES_PLATFORM"] = platform
        actual = {s["name"] for s in _find_all_skills()}
        assert actual == expected, (platform, actual, expected)
    assert not json.loads(skill_view("computer-use"))["success"]
    for name in expected:
        assert json.loads(skill_view(name, preprocess=False))["success"], name
assert not list(local.rglob("SKILL.md"))
print("PASS: migration preserves private data; repeated sync exposes only Nix-selected skills")
