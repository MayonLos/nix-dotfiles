#!/usr/bin/env python3
"""Temporary-directory tests for reconcile-overrides.py; never use a real HOME."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock


SCRIPT = Path(__file__).with_name("reconcile-overrides.py")
SPEC = importlib.util.spec_from_file_location("reconcile_overrides", SCRIPT)
assert SPEC and SPEC.loader
reconcile_overrides = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reconcile_overrides)


class ReconcileOverridesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="noctalia-reconcile-test-")
        self.root = Path(self.temp.name)
        self.state = self.root / "settings.toml"
        self.managed = self.root / "managed.json"
        self.backups = self.root / "backups"
        self.managed.write_text(
            json.dumps(
                {
                    "theme": {
                        "mode": "dark",
                        "custom_palette": "One-Dark-Darker",
                        "templates": {"builtin_ids": ["mango"]},
                    },
                    "dock": {"monitors": ["DP-1"]},
                    "plugins": {"enabled": ["declarative-plugin"]},
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_reconcile(self):
        return reconcile_overrides.reconcile(self.state, self.managed, self.backups)

    def test_remove_declared_paths_regardless_of_value_and_explicit_legacy_template(self) -> None:
        self.state.write_text(
            """# Keep this comment.
config_version = 14
[theme]
mode = "Tokyo Night" # differs from declaration
custom_palette = "Tokyo-Night" # differs from declaration
source = "custom" # preserve unrelated
[theme.templates]
builtin_ids = ["kitty", "zathura"] # differing template array
[dock]
monitors = ["HDMI-1"] # differing managed array
enabled = true
[plugins]
enabled = ["local-plugin"] # differs from declaration
oauth_token = "secret-sentinel-DO-NOT-BACK-UP"
other_unknown_setting = "keep-this"
[theme.templates.user.noctalia-mango]
input_path = "/nix/store/public-template"
post_hook = "public-hook"
[theme.templates.user.keep-me]
input_path = "/user/custom"
""",
            encoding="utf-8",
        )
        os.chmod(self.state, 0o640)

        removed = self.run_reconcile()

        self.assertEqual(
            set(removed),
            {
                ("theme", "mode"),
                ("theme", "custom_palette"),
                ("theme", "templates", "builtin_ids"),
                ("dock", "monitors"),
                ("plugins", "enabled"),
                ("theme", "templates", "user", "noctalia-mango"),
            },
        )
        result = self.state.read_text(encoding="utf-8")
        self.assertIn("# Keep this comment.", result)
        self.assertIn('source = "custom" # preserve unrelated', result)
        self.assertIn("enabled = true", result)
        self.assertIn('oauth_token = "secret-sentinel-DO-NOT-BACK-UP"', result)
        self.assertIn('other_unknown_setting = "keep-this"', result)
        self.assertIn("secret-sentinel-DO-NOT-BACK-UP", result)
        self.assertIn("keep-me", result)
        self.assertNotIn('mode = "dark"', result)
        self.assertNotIn('custom_palette = "Tokyo-Night"', result)
        self.assertNotIn('builtin_ids = ["kitty", "zathura"]', result)
        self.assertNotIn('monitors = ["HDMI-1"]', result)
        self.assertNotIn('enabled = ["local-plugin"]', result)
        self.assertNotIn("noctalia-mango", result)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o640)

        backup_files = list(self.backups.iterdir())
        self.assertEqual(len(backup_files), 1)
        self.assertEqual(stat.S_IMODE(self.backups.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(backup_files[0].stat().st_mode), 0o600)
        backup_text = backup_files[0].read_text(encoding="utf-8")
        self.assertIn("noctalia-mango", backup_text)
        self.assertIn("public-template", backup_text)
        self.assertIn("Tokyo-Night", backup_text)
        self.assertIn("kitty", backup_text)
        self.assertIn("local-plugin", backup_text)
        self.assertNotIn("secret-sentinel-DO-NOT-BACK-UP", backup_text)
        self.assertNotIn("oauth_token", backup_text)
        self.assertNotIn("other_unknown_setting", backup_text)

    def test_idempotent_second_run_does_not_write_or_make_backup(self) -> None:
        self.state.write_text('[theme]\nmode = "dark"\ncustom_palette = "One-Dark-Darker"\n', encoding="utf-8")
        self.assertEqual(len(self.run_reconcile()), 2)
        first = self.state.read_bytes()
        mtime = self.state.stat().st_mtime_ns
        backups = list(self.backups.iterdir())

        self.assertEqual(self.run_reconcile(), [])
        self.assertEqual(self.state.read_bytes(), first)
        self.assertEqual(self.state.stat().st_mtime_ns, mtime)
        self.assertEqual(list(self.backups.iterdir()), backups)

    def test_missing_state_is_noop(self) -> None:
        self.assertEqual(self.run_reconcile(), [])
        self.assertFalse(self.backups.exists())

    def test_rejects_state_symlink(self) -> None:
        target = self.root / "target.toml"
        target.write_text('[theme]\nmode = "dark"\n', encoding="utf-8")
        self.state.symlink_to(target)
        with self.assertRaisesRegex(reconcile_overrides.ReconcileError, "symlink"):
            self.run_reconcile()
        self.assertEqual(target.read_text(encoding="utf-8"), '[theme]\nmode = "dark"\n')

    def test_rejects_invalid_toml_without_backup_or_write(self) -> None:
        bad = b"[theme\nmode = \"dark\"\n"
        self.state.write_bytes(bad)
        with self.assertRaisesRegex(reconcile_overrides.ReconcileError, "invalid Noctalia TOML"):
            self.run_reconcile()
        self.assertEqual(self.state.read_bytes(), bad)
        self.assertFalse(self.backups.exists())

    def test_live_noctalia_guard_refuses_even_without_a_required_write(self) -> None:
        original = '[theme]\nmode = "dark"\n'
        self.state.write_text(original, encoding="utf-8")
        proc_root = self.root / "proc"
        self._add_proc_entry(proc_root, "2378", "/nix/store/noctalia/bin/.noctalia-wrapped (deleted)")
        proc_check = reconcile_overrides._proc_has_noctalia
        has_live_writer = lambda uid: proc_check(uid, proc_root)
        with mock.patch.object(reconcile_overrides, "_proc_has_noctalia", side_effect=has_live_writer):
            with self.assertRaisesRegex(reconcile_overrides.ReconcileError, "still running"):
                reconcile_overrides.reconcile(self.state, self.managed, self.backups, True)
        self.assertEqual(self.state.read_text(encoding="utf-8"), original)
        self.assertFalse(self.backups.exists())

        self.managed.write_text("{}", encoding="utf-8")
        with mock.patch.object(reconcile_overrides, "_proc_has_noctalia", side_effect=has_live_writer):
            with self.assertRaisesRegex(reconcile_overrides.ReconcileError, "still running"):
                reconcile_overrides.reconcile(self.state, self.managed, self.backups, True)
        self.assertEqual(self.state.read_text(encoding="utf-8"), original)
        self.assertFalse(self.backups.exists())

        self.state.unlink()
        with mock.patch.object(reconcile_overrides, "_proc_has_noctalia", side_effect=has_live_writer):
            with self.assertRaisesRegex(reconcile_overrides.ReconcileError, "still running"):
                reconcile_overrides.reconcile(self.state, self.managed, self.backups, True)
        self.assertFalse(self.state.exists())
        self.assertFalse(self.backups.exists())

    def _add_proc_entry(self, proc_root: Path, pid: str, executable: str) -> Path:
        entry = proc_root / pid
        entry.mkdir(parents=True, exist_ok=True)
        (entry / "exe").symlink_to(executable)
        return entry

    def _probe_proc_executable(self, executable: str, entry_uid: int | None = None) -> bool:
        proc_root = self.root / f"proc-{len(list(self.root.glob('proc-*')))}"
        entry = self._add_proc_entry(proc_root, "42", executable)
        current_uid = os.getuid()
        process_uid = current_uid if entry_uid is None else entry_uid
        real_stat = Path.stat

        def fake_stat(path: Path, *args, **kwargs):
            result = real_stat(path, *args, **kwargs)
            if path == entry:
                return SimpleNamespace(st_uid=process_uid)
            return result

        with mock.patch.object(Path, "stat", autospec=True, side_effect=fake_stat):
            return reconcile_overrides._proc_has_noctalia(current_uid, proc_root)

    def test_proc_guard_matches_only_noctalia_executable_metadata(self) -> None:
        self.assertTrue(self._probe_proc_executable("/nix/store/noctalia/bin/noctalia"))
        self.assertTrue(self._probe_proc_executable("/nix/store/noctalia/bin/.noctalia-wrapped"))
        self.assertTrue(self._probe_proc_executable("/nix/store/noctalia/bin/.noctalia-wrapped (deleted)"))
        self.assertFalse(self._probe_proc_executable("/usr/bin/other-shell"))
        self.assertFalse(self._probe_proc_executable("/nix/store/noctalia/bin/.noctalia-wrapped", os.getuid() + 1))

    def test_detects_external_edit_before_replace(self) -> None:
        self.state.write_text('[theme]\nmode = "dark"\n', encoding="utf-8")
        original_fingerprint = reconcile_overrides._fingerprint
        calls = 0

        def edit_before_final_check(path: Path):
            nonlocal calls
            calls += 1
            if calls == 2:
                path.write_text('[theme]\nmode = "light"\n', encoding="utf-8")
            return original_fingerprint(path)

        with mock.patch.object(reconcile_overrides, "_fingerprint", side_effect=edit_before_final_check):
            with self.assertRaisesRegex(reconcile_overrides.ReconcileError, "changed during reconciliation"):
                self.run_reconcile()
        self.assertIn('mode = "light"', self.state.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
