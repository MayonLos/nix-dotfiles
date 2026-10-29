import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("obsidian_theme.py")
LAYOUT_SNIPPET = Path(__file__).with_name("obsidian-quiet-layout.css")


class ObsidianThemeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config_home = self.root / "config"
        (self.config_home / "obsidian").mkdir(parents=True)
        self.vault = self.root / "vault"
        self.vault.mkdir()
        self.unregistered = self.root / "unregistered"
        self.unregistered.mkdir()
        self.registry = self.config_home / "obsidian" / "obsidian.json"
        self.write_registry({"vault-a": {"path": str(self.vault)}})
        self.env = {
            **os.environ,
            "HOME": str(self.root),
            "XDG_CONFIG_HOME": str(self.config_home),
        }

    def tearDown(self):
        self.temp.cleanup()

    def write_registry(self, vaults):
        self.registry.write_text(json.dumps({"vaults": vaults}), encoding="utf-8")

    def run_script(self, action, succeeds=True):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), action],
            env=self.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_outputs_only_registered_vaults_and_creates_missing_directories(self):
        self.write_registry({
            "vault-a": {"path": str(self.vault)},
        })
        (self.root / "decoy").mkdir()
        (self.root / "decoy" / ".obsidian").mkdir()
        result = self.run_script("outputs")
        expected = self.vault / ".obsidian" / "snippets" / "noctalia.css"
        self.assertEqual(result.stdout.splitlines(), [str(expected)])
        self.assertTrue(expected.parent.is_dir())
        self.assertFalse((self.root / "decoy" / ".obsidian" / "snippets").exists())

    def test_missing_registered_vault_does_not_block_existing_vault(self):
        self.write_registry({
            "present": {"path": str(self.vault)},
            "offline": {"path": str(self.root / "offline")},
        })
        result = self.run_script("outputs")
        self.assertEqual(result.stdout.splitlines(), [str(self.vault / ".obsidian/snippets/noctalia.css")])
        self.run_script("enable")
        self.assertFalse((self.root / "offline").exists())

    def test_enable_is_idempotent_and_preserves_existing_values(self):
        obsidian = self.vault / ".obsidian"
        obsidian.mkdir()
        appearance = obsidian / "appearance.json"
        appearance.write_text(json.dumps({"cssTheme": "Minimal", "enabledCssSnippets": ["vaults-ui"]}), encoding="utf-8")
        self.run_script("enable")
        first = appearance.read_bytes()
        self.run_script("enable")
        self.assertEqual(appearance.read_bytes(), first)
        self.assertEqual(json.loads(first), {"cssTheme": "Minimal", "enabledCssSnippets": ["vaults-ui", "noctalia"]})

    def test_quiet_layout_is_opt_in_and_does_not_hide_navigation(self):
        obsidian = self.vault / ".obsidian"
        obsidian.mkdir()
        appearance = obsidian / "appearance.json"
        appearance.write_text(
            json.dumps({"cssTheme": "Minimal", "enabledCssSnippets": ["vaults-ui"]}),
            encoding="utf-8",
        )

        css = LAYOUT_SNIPPET.read_text(encoding="utf-8")
        self.assertIn(".workspace-tab-header.is-active", css)
        self.assertIn("inset 0 -1px var(--vault-blue)", css)
        self.assertIn(".workspace-split.mod-left-split", css)
        self.assertIn(".workspace-split.mod-right-split", css)
        self.assertNotIn("display: none", css)
        self.assertNotIn("#", css)

        self.run_script("enable")
        updated = json.loads(appearance.read_text(encoding="utf-8"))
        self.assertEqual(updated["cssTheme"], "Minimal")
        self.assertEqual(updated["enabledCssSnippets"], ["vaults-ui", "noctalia"])
        self.assertNotIn("obsidian-quiet-layout", updated["enabledCssSnippets"])

    def test_bad_appearance_json_is_rejected_without_rewrite(self):
        obsidian = self.vault / ".obsidian"
        obsidian.mkdir()
        appearance = obsidian / "appearance.json"
        appearance.write_text("{bad", encoding="utf-8")
        before = appearance.read_bytes()
        self.run_script("enable", succeeds=False)
        self.assertEqual(appearance.read_bytes(), before)

    def test_symlink_in_output_path_is_rejected(self):
        obsidian = self.vault / ".obsidian"
        obsidian.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        (obsidian / "snippets").symlink_to(outside, target_is_directory=True)
        self.run_script("outputs", succeeds=False)

    def test_symlink_css_target_is_rejected(self):
        snippets = self.vault / ".obsidian" / "snippets"
        snippets.mkdir(parents=True)
        outside = self.root / "outside.css"
        outside.write_text("user-owned", encoding="utf-8")
        (snippets / "noctalia.css").symlink_to(outside)
        self.run_script("outputs", succeeds=False)

    def test_non_regular_css_target_is_rejected(self):
        snippets = self.vault / ".obsidian" / "snippets"
        snippets.mkdir(parents=True)
        (snippets / "noctalia.css").mkdir()
        self.run_script("outputs", succeeds=False)

    def test_symlink_appearance_file_is_rejected(self):
        obsidian = self.vault / ".obsidian"
        obsidian.mkdir()
        outside = self.root / "appearance.json"
        outside.write_text('{"enabledCssSnippets": []}', encoding="utf-8")
        (obsidian / "appearance.json").symlink_to(outside)
        self.run_script("enable", succeeds=False)

    def test_registered_vault_symlink_is_rejected(self):
        alias = self.root / "vault-alias"
        alias.symlink_to(self.vault, target_is_directory=True)
        self.write_registry({"vault-link": {"path": str(alias)}})
        self.run_script("outputs", succeeds=False)

    def test_line_break_in_registered_path_is_rejected(self):
        self.write_registry({"vault-line-break": {"path": str(self.root) + "\nforged"}})
        self.run_script("outputs", succeeds=False)


if __name__ == "__main__":
    unittest.main()
