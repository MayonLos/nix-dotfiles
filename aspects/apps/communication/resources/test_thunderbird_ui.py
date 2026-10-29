#!/usr/bin/env python3
"""Exercise Thunderbird UI seeding against isolated synthetic profiles."""

import importlib.util
import os
from pathlib import Path
import re
import tempfile
from unittest.mock import patch

import tinycss2

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("thunderbird_seed", HERE / "seed-thunderbird-ui.py")
SEED = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(SEED)


def write_profiles(root: Path, default: str = "Profiles/default.release", *, relative: bool = True) -> Path:
    profile = root / default
    profile.mkdir(parents=True, exist_ok=True)
    (root / "Profiles/legacy.default").mkdir(parents=True, exist_ok=True)
    (root / "profiles.ini").write_text(
        "[Profile0]\nName=legacy\nIsRelative=1\nPath=Profiles/legacy.default\nDefault=1\n"
        f"[Profile1]\nName=release\nIsRelative={int(relative)}\nPath={default}\n"
        f"[InstallA]\nDefault={default}\n",
        encoding="utf-8",
    )
    return profile


def seed(home: Path, config: Path, css: Path) -> None:
    with patch.dict(os.environ, {"HOME": str(home), "XDG_CONFIG_HOME": str(config)}), patch(
        "sys.argv", [str(HERE / "seed-thunderbird-ui.py"), str(css)]
    ):
        SEED.main()


def expect_seed_error(home: Path, config: Path, css: Path) -> None:
    with patch.dict(os.environ, {"HOME": str(home), "XDG_CONFIG_HOME": str(config)}), patch(
        "sys.argv", [str(HERE / "seed-thunderbird-ui.py"), str(css)]
    ):
        try:
            SEED.main()
        except SEED.SeedError:
            return
    raise AssertionError("Expected seed to reject invalid profile configuration")


def serialize(tokens) -> str:
    return tinycss2.serialize(tokens)


def url_scopes(rule) -> set[str]:
    return {
        serialize(token.arguments).strip().strip("\"'")
        for token in rule.prelude
        if token.type == "function" and token.lower_name == "url"
    }


def assert_css_contract(css: bytes) -> None:
    source = css.decode("utf-8")
    assert '@-moz-document url("about:home")' not in source
    assert "nix-dotfiles userContent segment" not in source
    parsed = tinycss2.parse_stylesheet(source, skip_whitespace=True, skip_comments=True)
    assert all(rule.type != "error" for rule in parsed), "invalid CSS"
    scopes = [rule for rule in parsed if rule.type == "at-rule" and rule.lower_at_keyword == "-moz-document"]
    assert len(scopes) == 1
    assert url_scopes(scopes[0]) == {
        "chrome://messenger/content/messenger.xhtml",
        "about:3pane",
        "about:message",
    }
    assert all(rule.type == "at-rule" for rule in parsed), "unscoped style rule found"
    rules = tinycss2.parse_rule_list(scopes[0].content, skip_whitespace=True, skip_comments=True)
    assert all(rule.type != "error" for rule in rules), "invalid scoped CSS"
    selectors = {
        serialize(rule.prelude).strip(): {
            declaration.lower_name: serialize(declaration.value).strip()
            for declaration in tinycss2.parse_declaration_list(
                rule.content, skip_whitespace=True, skip_comments=True
            )
            if declaration.type == "declaration"
        }
        for rule in rules
        if rule.type == "qualified-rule"
    }
    root = selectors[":root"]
    assert '"Inter", "Noto Sans CJK SC", sans-serif' in root["font-family"]
    assert root["font-size"] == "13px"
    selected = [decls for selector, decls in selectors.items() if "selected" in selector or ".current" in selector]
    assert any(
        "var(--tb-selection)" in decls.get("background", decls.get("background-color", ""))
        for decls in selected
    )
    assert any("inset 2px 0 var(--tb-blue)" in decls.get("box-shadow", "") for decls in selected)
    assert any("padding-block" in decls for selector, decls in selectors.items() if "toolbar" in selector.lower())
    assert any(decls.get("min-height") == "30px" for selector, decls in selectors.items() if "tabmail-tab" in selector)
    body_selector = re.compile(r"(?:^|[\s>+~,])(?:body|#messagepane|\.moz-text-html|\.moz-text-flowed)(?:$|[\s.#:[>+~,])", re.I)
    assert not any(body_selector.search(selector) for selector in selectors), "message body selector found"


def managed_user(profile: Path) -> bytes:
    return (profile / "user.js").read_bytes()


def test_profile_seed(css_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="thunderbird-seed-") as temp:
        base = Path(temp)
        home, config = base / "home", base / "config"
        profile = write_profiles(config / "thunderbird")
        home_profile = write_profiles(home / ".thunderbird", "Profiles/home.default")
        chrome = profile / "chrome"
        chrome.mkdir()
        css_file = chrome / "userChrome.css"
        personal_css = b"/* personal bytes */\r\n:root { --personal: yes; }\n"
        css_file.write_bytes(personal_css)
        user_js = profile / "user.js"
        personal_user = b'// personal\nuser_pref("mailnews.message_display.disable_remote_image", true);\n'
        user_js.write_bytes(personal_user)
        prefs_js = profile / "prefs.js"
        saved_prefs = b'// account state\nuser_pref("mail.accountmanager.accounts", "account1");\n'
        prefs_js.write_bytes(saved_prefs)

        seed(home, config, css_path)
        seeded_css, seeded_user = css_file.read_bytes(), user_js.read_bytes()
        assert seeded_css.startswith(personal_css) and css_path.read_bytes().rstrip() in seeded_css
        assert seeded_css.count(SEED.CSS_BEGIN) == seeded_css.count(SEED.CSS_END) == 1
        assert seeded_user.startswith(personal_user)
        assert b'toolkit.legacyUserProfileCustomizations.stylesheets", true' in seeded_user
        assert b'mail.uidensity", 0' in seeded_user
        assert b'mailnews.message_display.disable_remote_image' in seeded_user
        assert prefs_js.read_bytes() == saved_prefs
        assert not (home_profile / "chrome" / "userChrome.css").exists()
        seed(home, config, css_path)
        assert css_file.read_bytes() == seeded_css and user_js.read_bytes() == seeded_user

        # Active preferences outside the marker win, regardless of line layout.
        for personal in (
            b'user_pref("other.pref", true); user_pref("mail.uidensity", 2);\n',
            b"user_pref(\n  'mail.uidensity',\n  3\n);\n",
        ):
            user_js.write_bytes(personal)
            seed(home, config, css_path)
            managed = managed_user(profile).split(SEED.PREF_BEGIN, 1)[1].split(SEED.PREF_END, 1)[0]
            assert b"mail.uidensity" not in managed

        # Commented examples and strings containing source text do not override defaults.
        user_js.write_bytes(
            b'// user_pref("mail.uidensity", 2);\n'
            b"/* user_pref('mail.uidensity', 2); */\n"
            b'const example = "user_pref(\\"mail.uidensity\\", 2)";\n'
        )
        seed(home, config, css_path)
        assert b'mail.uidensity", 0' in managed_user(profile)

        # Saved prefs.js explicit values are preserved, including stylesheet=false.
        prefs_js.write_bytes(
            saved_prefs
            + b'user_pref("mail.uidensity", 1);\n'
            + b'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);\n'
        )
        user_js.write_bytes(personal_user)
        seed(home, config, css_path)
        managed = managed_user(profile)
        assert b"mail.uidensity" not in managed
        assert b"toolkit.legacyUserProfileCustomizations.stylesheets" not in managed

        # If only stylesheet loading is explicitly disabled, density remains managed.
        prefs_js.write_bytes(saved_prefs + b'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);\n')
        user_js.write_bytes(personal_user)
        seed(home, config, css_path)
        managed = managed_user(profile).split(SEED.PREF_BEGIN, 1)[1].split(SEED.PREF_END, 1)[0]
        assert b"toolkit.legacyUserProfileCustomizations.stylesheets" not in managed
        assert b'mail.uidensity", 0' in managed


def test_paths_and_failures(css_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="thunderbird-absolute-") as temp:
        base = Path(temp)
        profile = write_profiles(base / "config/thunderbird", str(base / "outside"), relative=False)
        seed(base / "home", base / "config", css_path)
        assert (profile / "chrome/userChrome.css").is_file()

    with tempfile.TemporaryDirectory(prefix="thunderbird-legacy-") as temp:
        base = Path(temp)
        profile = write_profiles(base / "home/.thunderbird", "Profiles/home.default")
        seed(base / "home", base / "config", css_path)
        assert (profile / "chrome/userChrome.css").is_file()

    with tempfile.TemporaryDirectory(prefix="thunderbird-missing-") as temp:
        base = Path(temp)
        (base / "config").mkdir()
        seed(base / "home", base / "config", css_path)
        assert not (base / "home").exists()

    malformed_css = (
        SEED.CSS_BEGIN + b"\na{}\n" + SEED.CSS_END + b"\n" + SEED.CSS_BEGIN + b"\nb{}\n" + SEED.CSS_END,
        SEED.CSS_END + b"\n" + SEED.CSS_BEGIN + b"\na{}\n",
    )
    malformed_prefs = (
        SEED.PREF_BEGIN + b"\na\n" + SEED.PREF_END + b"\n" + SEED.PREF_BEGIN + b"\nb\n" + SEED.PREF_END,
        SEED.PREF_END + b"\n" + SEED.PREF_BEGIN + b"\na\n",
    )
    for index, (bad_css, bad_user) in enumerate(zip(malformed_css, malformed_prefs, strict=True)):
        with tempfile.TemporaryDirectory(prefix=f"thunderbird-markers-{index}-") as temp:
            base = Path(temp)
            profile = write_profiles(base / "config/thunderbird")
            (profile / "chrome").mkdir()
            css_file, user_file = profile / "chrome/userChrome.css", profile / "user.js"
            css_file.write_bytes(bad_css)
            user_file.write_bytes(bad_user)
            before = css_file.read_bytes(), user_file.read_bytes()
            expect_seed_error(base / "home", base / "config", css_path)
            assert (css_file.read_bytes(), user_file.read_bytes()) == before

    with tempfile.TemporaryDirectory(prefix="thunderbird-symlink-") as temp:
        base = Path(temp)
        profile = write_profiles(base / "config/thunderbird")
        target = profile / "real-chrome"
        target.mkdir()
        (profile / "chrome").symlink_to(target, target_is_directory=True)
        expect_seed_error(base / "home", base / "config", css_path)
        assert list(target.iterdir()) == []


def main() -> None:
    import sys

    if len(sys.argv) != 2:
        raise SystemExit("usage: test_thunderbird_ui.py FALLBACK_CSS")
    css_path = Path(sys.argv[1])
    assert_css_contract(css_path.read_bytes())
    test_profile_seed(css_path)
    test_paths_and_failures(css_path)
    print("Thunderbird UI seed tests passed")


if __name__ == "__main__":
    main()
