#!/usr/bin/env python3
"""Temporary-profile tests for Firefox UI seeding and stylesheet templates."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import tinycss2

from firefox_profile import BEGIN, CONTENT_BEGIN, CONTENT_END, END, split_stylesheets, replace_managed_block


RESOURCE_DIR = Path(__file__).resolve().parent
SEED_SCRIPT = RESOURCE_DIR / "seed-firefox-ui.py"
NOCTALIA_HOOK = RESOURCE_DIR / "apply-noctalia-userChrome.py"
FALLBACK_CSS_PATH: Path | None = None


def css_parse_errors(source: str) -> list[str]:
    """Return syntax errors from stylesheet rules, at-rules, and declarations."""
    errors: list[str] = []

    def visit(rules: list[object]) -> None:
        for rule in rules:
            if rule.type == "error":
                errors.append(f"line {rule.source_line}:{rule.source_column}: {rule.message}")
            elif rule.type == "qualified-rule":
                for declaration in tinycss2.parse_declaration_list(
                    rule.content,
                    skip_comments=True,
                    skip_whitespace=True,
                ):
                    if declaration.type == "error":
                        errors.append(
                            f"line {declaration.source_line}:{declaration.source_column}: "
                            f"{declaration.message}"
                        )
            elif rule.type == "at-rule" and rule.content is not None:
                visit(
                    tinycss2.parse_rule_list(
                        rule.content,
                        skip_comments=True,
                        skip_whitespace=True,
                    )
                )

    visit(tinycss2.parse_stylesheet(source, skip_comments=True, skip_whitespace=True))
    return errors


class FirefoxUiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if FALLBACK_CSS_PATH is None:
            raise SystemExit(f"usage: {Path(sys.argv[0]).name} FALLBACK_CSS")
        cls.fallback_css_path = FALLBACK_CSS_PATH
        if not cls.fallback_css_path.is_file():
            raise SystemExit(f"Firefox fallback CSS not found: {cls.fallback_css_path}")
        cls.fallback_css = cls.fallback_css_path.read_text(encoding="utf-8")
        try:
            cls.chrome_css, cls.content_css = split_stylesheets(cls.fallback_css)
        except RuntimeError as error:
            raise SystemExit(str(error)) from error
        if not cls.content_css:
            raise SystemExit("Firefox fallback CSS has no managed userContent segment")
        if "{{" in cls.fallback_css or "}}" in cls.fallback_css:
            raise SystemExit("Firefox fallback CSS contains unrendered template tokens")

    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="firefox-ui-test-")
        self.addCleanup(self.tempdir.cleanup)
        self.root = Path(self.tempdir.name)
        self.config_home = self.root / "config"
        self.cache_home = self.root / "cache"
        self.profile_root = self.config_home / "mozilla" / "firefox"
        self.profile = self.profile_root / "default"
        (self.profile / "chrome").mkdir(parents=True)
        (self.profile_root / "profiles.ini").write_text(
            "[Profile0]\nName=default\nIsRelative=1\nPath=default\nDefault=1\n",
            encoding="utf-8",
        )
        self.chrome_path = self.profile / "chrome" / "userChrome.css"
        self.content_path = self.profile / "chrome" / "userContent.css"
        self.prefs_path = self.profile / "user.js"
        self.chrome_path.write_text("/* manual chrome rules */\n", encoding="utf-8")
        self.content_path.write_text("/* manual content rules */\n", encoding="utf-8")
        self.prefs_path.write_text("// manual preference\n", encoding="utf-8")
        self.env = os.environ.copy()
        self.env.update(
            {
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_CACHE_HOME": str(self.cache_home),
                "PYTHONDONTWRITEBYTECODE": "1",
            }
        )

    def run_script(self, script: Path) -> None:
        subprocess.run(
            [sys.executable, "-B", str(script), str(self.fallback_css_path)],
            check=True,
            capture_output=True,
            text=True,
            env=self.env,
        )

    def test_fallback_css_parses_as_two_stylesheets(self) -> None:
        self.assertFalse(css_parse_errors(self.chrome_css), css_parse_errors(self.chrome_css))
        self.assertFalse(css_parse_errors(self.content_css), css_parse_errors(self.content_css))

    def test_managed_ui_uses_reading_face_for_tabs_and_monospace_for_urls(self) -> None:
        self.assertIn('font-family: "Maple Mono NF CN", monospace', self.chrome_css)
        self.assertIn("#urlbar-input", self.chrome_css)
        rules = tinycss2.parse_stylesheet(self.chrome_css, skip_comments=True, skip_whitespace=True)
        labels = next(rule for rule in rules if rule.type == "qualified-rule"
                      and ".tabbrowser-tab .tab-label," in tinycss2.serialize(rule.prelude))
        declarations = {item.lower_name: tinycss2.serialize(item.value).strip()
                        for item in tinycss2.parse_declaration_list(labels.content)
                        if item.type == "declaration"}
        self.assertEqual(declarations["font-family"], '"Inter", "Noto Sans CJK SC", sans-serif')
        self.assertEqual(declarations["font-size"], "14px")
        # A saved native sidebar resize must never be replaced by CSS.
        for rule in rules:
            if rule.type == "qualified-rule" and "::" not in tinycss2.serialize(rule.prelude) and any(selector in tinycss2.serialize(rule.prelude)
                for selector in ("sidebar-main", "#sidebar-container", "#tabbrowser-tabs")):
                names = {item.lower_name for item in tinycss2.parse_declaration_list(rule.content)
                         if item.type == "declaration"}
                self.assertFalse(names & {"width", "min-width", "max-width", "inline-size", "min-inline-size", "max-inline-size"})
        self.assertIn('url("about:home")', self.content_css)
        self.assertIn('url("about:newtab")', self.content_css)
        self.assertIn("width: min(100%, 560px) !important", self.content_css)
        self.assertIn("height: 48px !important", self.content_css)
        self.assertIn("--urlbar-height: 48px !important", self.content_css)
        for property_name in (
            "background-color",
            "color",
            "fill",
            "caret-color",
            "border-width",
            "border-radius",
            "unfocused-border-color",
            "fakefocus-border-color",
            "fakefocus-box-shadow-inner",
            "fakefocus-box-shadow-outer",
        ):
            self.assertIn(f"--content-search-handoff-ui-{property_name}:", self.content_css)

    def test_seed_is_idempotent_and_preserves_user_content(self) -> None:
        self.run_script(SEED_SCRIPT)
        first = (
            self.chrome_path.read_text(encoding="utf-8"),
            self.content_path.read_text(encoding="utf-8"),
            self.prefs_path.read_text(encoding="utf-8"),
        )
        self.assertIn("manual chrome rules", first[0])
        self.assertIn("manual content rules", first[1])
        self.assertIn("// manual preference", first[2])
        self.assertIn(BEGIN, first[0])
        self.assertIn(BEGIN, first[1])
        self.assertIn('browser.newtabpage.activity-stream.topSitesRows", 1', first[2])
        self.assertIn("about:home", first[1])
        self.assertIn("about:newtab", first[1])

        self.run_script(SEED_SCRIPT)
        self.assertEqual(
            first,
            (
                self.chrome_path.read_text(encoding="utf-8"),
                self.content_path.read_text(encoding="utf-8"),
                self.prefs_path.read_text(encoding="utf-8"),
            ),
        )

    def test_noctalia_hook_updates_both_stylesheet_blocks(self) -> None:
        self.run_script(NOCTALIA_HOOK)
        chrome = self.chrome_path.read_text(encoding="utf-8")
        content = self.content_path.read_text(encoding="utf-8")
        self.assertIn(BEGIN, chrome)
        self.assertIn(END, chrome)
        self.assertIn(BEGIN, content)
        self.assertIn(END, content)
        self.assertIn("manual chrome rules", chrome)
        self.assertIn("manual content rules", content)
        self.assertIn('url("about:newtab")', content)

    def test_managed_writer_refuses_symlinks_and_bad_markers(self) -> None:
        linked_target = self.root / "linked-target"
        linked_target.write_text("manual\n", encoding="utf-8")
        linked_file = self.root / "linked.css"
        linked_file.symlink_to(linked_target)
        incomplete = self.root / "incomplete.css"
        incomplete.write_text("BEGIN\nmanual\n", encoding="utf-8")
        duplicate = self.root / "duplicate.css"
        duplicate.write_text("BEGIN\nEND\nBEGIN\nEND\n", encoding="utf-8")

        for path in (linked_file, incomplete, duplicate):
            with self.subTest(path=path.name), self.assertRaises(RuntimeError):
                replace_managed_block(path, "BEGIN", "END", "managed")

    def test_template_split_refuses_incomplete_or_duplicate_markers(self) -> None:
        for source in (
            CONTENT_BEGIN,
            f"{CONTENT_BEGIN}\ncss\n{CONTENT_END}\n{CONTENT_BEGIN}\nmore\n{CONTENT_END}",
        ):
            with self.subTest(source=source), self.assertRaises(RuntimeError):
                split_stylesheets(source)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} FALLBACK_CSS")
    FALLBACK_CSS_PATH = Path(sys.argv[1]).expanduser().resolve()
    unittest.main(argv=[sys.argv[0]])
