#!/usr/bin/env python3
"""Seed Firefox UI preferences and the managed browser-chrome stylesheet."""

import os
from pathlib import Path
import re
import sys

from firefox_profile import BEGIN, END, _default_profile_path, replace_managed_block


def main() -> int:
    style_source = Path(sys.argv[1])
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    profile_root = config_home / "mozilla" / "firefox"
    profiles_ini = profile_root / "profiles.ini"
    if not profiles_ini.is_file():
        print(f"Firefox profile not initialized at {profiles_ini}; skipping UI seed until a later activation")
        return 0

    try:
        profile_path = _default_profile_path(profile_root)
    except RuntimeError as error:
        raise SystemExit(str(error)) from error
    if not profile_path.is_dir():
        raise SystemExit(f"Firefox default profile does not exist: {profile_path}")

    user_prefs = "\n".join(
        [
            'user_pref("sidebar.revamp", true);',
            'user_pref("sidebar.verticalTabs", true);',
            'user_pref("sidebar.visibility", "always-show");',
            # Override Firefox's persisted open launcher state on every start.
            'user_pref("sidebar.backupState", "{\\"launcherExpanded\\":false,\\"launcherVisible\\":true,\\"panelOpen\\":false}");',
            'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);',
            'user_pref("browser.ctrlTab.sortByRecentlyUsed", true);',
            'user_pref("findbar.highlightAll", true);',
            'user_pref("browser.tabs.splitView.enabled", true);',
        ]
    )
    try:
        replace_managed_block(
            profile_path / "user.js",
            "// BEGIN nix-dotfiles managed Firefox UI",
            "// END nix-dotfiles managed Firefox UI",
            user_prefs,
        )
    except RuntimeError as error:
        raise SystemExit(str(error)) from error

    rendered_theme = (
        Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
        / "noctalia"
        / "firefox"
        / "userChrome.css"
    )
    theme_css = style_source.read_text()
    if rendered_theme.is_file():
        candidate = rendered_theme.read_text()
        if "{{" not in candidate and "}}" not in candidate:
            # Keep the rendered palette, but always install the current CSS
            # structure. Noctalia's cache may predate this system generation.
            for name, value in re.findall(r"(--tn-[a-z-]+):\s*(#[0-9a-fA-F]{6});", candidate):
                theme_css = re.sub(
                    rf"({re.escape(name)}:)\s*#[0-9a-fA-F]{{6}};",
                    rf"\g<1> {value};",
                    theme_css,
                )

    try:
        replace_managed_block(profile_path / "chrome" / "userChrome.css", BEGIN, END, theme_css)
    except RuntimeError as error:
        raise SystemExit(str(error)) from error
    print(f"Ensured managed Firefox UI settings in {profile_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
