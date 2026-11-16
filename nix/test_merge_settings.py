"""Behavior of the declarative settings merge at the filesystem boundary."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("merge-settings.py")


class MergeSettings(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.env = os.environ.copy()
        self.env.update({name: str(root / name) for name in
                         ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_RUNTIME_DIR")})
        self.env.pop("OMAPOD_HOME", None)
        self.env.pop("OMAPOD_RUNTIME_DIR", None)
        self.env["PYTHONPATH"] = str(SCRIPT.parent.parent)
        self.config = root / "XDG_CONFIG_HOME" / "omapod"
        self.settings = self.config / "settings.json"
        self.sidecar = self.config / ".nix-settings.json"
        self.declared = root / "declared.json"

    def put(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def get(self, path):
        return json.loads(path.read_text(encoding="utf-8"))

    def merge(self, declaration):
        self.put(self.declared, declaration)
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), str(self.declared)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_first_run_adds_absent_keys_and_records_them(self):
        self.merge({"speed": 1.5})
        self.assertEqual(self.get(self.settings), {"speed": 1.5})
        self.assertEqual(self.get(self.sidecar), {"speed": 1.5})
        self.assertEqual(self.settings.stat().st_mode & 0o777, 0o600)

    def test_first_run_preserves_present_key_even_when_equal(self):
        self.put(self.settings, {"speed": 1.5})
        self.merge({"speed": 1.5})
        self.assertEqual(self.get(self.settings), {"speed": 1.5})
        self.assertEqual(self.get(self.sidecar), {})

    def test_nix_owned_value_follows_new_declaration(self):
        self.merge({"speed": 1.5})
        self.merge({"speed": 3.0})
        self.assertEqual(self.get(self.settings), {"speed": 3.0})
        self.assertEqual(self.get(self.sidecar), {"speed": 3.0})

    def test_user_change_stays_until_it_matches_declaration(self):
        self.merge({"speed": 1.5})
        self.put(self.settings, {"speed": 2.0})
        self.merge({"speed": 3.0})
        self.assertEqual(self.get(self.settings), {"speed": 2.0})
        self.assertEqual(self.get(self.sidecar), {"speed": 1.5})
        self.merge({"speed": 2.0})
        self.assertEqual(self.get(self.sidecar), {"speed": 2.0})
        self.merge({"speed": 3.0})
        self.assertEqual(self.get(self.settings), {"speed": 3.0})

    def test_removed_declaration_deletes_only_unmodified_value(self):
        self.merge({"speed": 1.5, "rewind_secs": 10})
        self.put(self.settings, {"speed": 2.0, "rewind_secs": 10})
        self.merge({})
        self.assertEqual(self.get(self.settings), {"speed": 2.0})
        self.assertEqual(self.get(self.sidecar), {})

    def test_unchanged_merge_does_not_rewrite_files(self):
        self.merge({"speed": 1.5})
        before = (self.settings.stat().st_mtime_ns, self.sidecar.stat().st_mtime_ns)
        self.merge({"speed": 1.5})
        self.assertEqual(before, (self.settings.stat().st_mtime_ns,
                                  self.sidecar.stat().st_mtime_ns))

    def test_busy_app_lock_touches_nothing(self):
        self.put(self.settings, {"speed": 1.0})
        holder = subprocess.Popen([sys.executable, "-B", "-c",
                                   "from omapod.config import instance_lock; "
                                   "lock = instance_lock('app'); print('ready', flush=True); input()"],
                                  env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), "ready")
            result = self.merge({"speed": 1.5})
            self.assertIn("omaPOD is running", result.stdout)
            self.assertEqual(self.get(self.settings), {"speed": 1.0})
            self.assertFalse(self.sidecar.exists())
        finally:
            holder.stdin.write("\n")
            holder.stdin.flush()
            holder.wait(timeout=5)
            holder.stdin.close()
            holder.stdout.close()

    def test_damaged_settings_stays_untouched(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text("{broken", encoding="utf-8")
        result = self.merge({"speed": 1.5})
        self.assertIn("settings.json", result.stderr)
        self.assertEqual(self.settings.read_text(encoding="utf-8"), "{broken")
        self.assertFalse(self.sidecar.exists())

    def test_damaged_sidecar_treats_existing_keys_as_user_owned(self):
        self.put(self.settings, {"speed": 1.5})
        self.sidecar.write_text("[]", encoding="utf-8")
        self.merge({"speed": 1.5, "rewind_secs": 10})
        self.assertEqual(self.get(self.settings), {"speed": 1.5, "rewind_secs": 10})
        self.assertEqual(self.get(self.sidecar), {"rewind_secs": 10})

    def test_rollback_follows_recorded_value(self):
        self.merge({"speed": 1.5})
        self.merge({"speed": 3.0})
        self.merge({"speed": 1.5})
        self.assertEqual(self.get(self.settings), {"speed": 1.5})
        self.assertEqual(self.get(self.sidecar), {"speed": 1.5})

    def test_null_value_is_distinct_from_absent_key(self):
        self.merge({"speed": None})
        self.assertEqual(self.get(self.settings), {"speed": None})
        self.assertEqual(self.get(self.sidecar), {"speed": None})
        self.merge({})
        self.assertEqual(self.get(self.settings), {})


if __name__ == "__main__":
    unittest.main()
