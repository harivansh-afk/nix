import copy
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from apply import configure, read
from seed import seed


SOURCE = Path(__file__).parent


class MouseMappingsTest(unittest.TestCase):
    def setUp(self):
        self.defaults = json.loads((SOURCE / "settings.json").read_text())
        self.policy = json.loads((SOURCE / "mappings.json").read_text())
        self.key = self.defaults["profile_keys"][0]

    def test_controls_and_browser_scope(self):
        result = configure(self.defaults, self.defaults, self.policy)
        self.assertEqual(len(result["profile_keys"]), 5)
        for key in result["profile_keys"]:
            assignments = {a["slotId"]: a["card"] for a in result[key]["assignments"]}
            for device in self.policy["devices"]:
                self.assertEqual(assignments[device + "_c86"]["macro"]["actionName"], "⌘V")
                gestures = assignments[device + "_c195"]["nestedCards"]["custom_gesture"]["nestedCards"]
                self.assertEqual(gestures["click"]["macro"]["actionName"], "⌘C")
                for direction in ("up", "down"):
                    self.assertEqual(gestures[direction]["macro"]["media"]["usage"], "VOLUME_" + direction.upper())
                for direction, action in (("left", "BACK"), ("right", "FORWARD")):
                    if key == self.key:
                        self.assertEqual(gestures[direction]["macro"]["type"], "DO_NOTHING")
                    else:
                        self.assertEqual(gestures[direction]["macro"]["mouse"]["action"], "OSX_GESTURE_" + action)

    def test_preserves_unowned_state_and_reuses_browser_registration(self):
        current = copy.deepcopy(self.defaults)
        current["account_sentinel"] = {"keep": True}
        current["applications"]["applications"].append({
            "bundleId": "net.imput.helium", "applicationId": "existing-helium",
            "lastRunTime": "preserve-me",
        })
        before = copy.deepcopy(current)
        result = configure(current, self.defaults, self.policy)
        self.assertEqual(current, before)
        self.assertEqual(result["account_sentinel"], before["account_sentinel"])
        self.assertIn("profile-existing-helium", result)
        self.assertNotIn("profile-nix-browser-helium", result)
        owned = {d + "_" + s for d in self.policy["devices"] for s in ("c86", "c195")}
        after = {a["slotId"]: a for a in result[self.key]["assignments"]}
        for assignment in before[self.key]["assignments"]:
            if assignment["slotId"] not in owned:
                self.assertEqual(after[assignment["slotId"]], assignment)
        self.assertEqual(configure(result, self.defaults, self.policy), result)

    def test_seed_is_valid_and_does_not_replace_existing_databases(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            seed(SOURCE, destination)
            for name in ("settings", "macros"):
                with sqlite3.connect(destination / f"{name}.db") as db:
                    self.assertEqual(db.execute("PRAGMA integrity_check").fetchone(), ("ok",))
                    self.assertEqual(read(db)[1], json.loads((SOURCE / f"{name}.json").read_text()))
                    db.execute("UPDATE data SET file=?", (b'{"preserve":"user edits"}',))
            before = {p.name: p.read_bytes() for p in destination.iterdir()}
            seed(SOURCE, destination)
            self.assertEqual(before, {p.name: p.read_bytes() for p in destination.iterdir()})


if __name__ == "__main__":
    unittest.main()
