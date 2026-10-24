#!/usr/bin/env python3
"""Seed Firefox UI preferences and the managed browser-chrome stylesheet."""

import os
from pathlib import Path
import sys

from firefox_profile import (
    BEGIN,
    CONTENT_BEGIN,
    CONTENT_END,
    END,
    _default_profile_path,
    replace_managed_block,
    split_stylesheets,
)


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
            'user_pref("browser.newtabpage.activity-stream.showSearch", true);',
            'user_pref("browser.newtabpage.activity-stream.topSitesRows", 1);',
            'user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);',
            'user_pref("browser.newtabpage.activity-stream.feeds.snippets", false);',
            'user_pref("browser.newtabpage.activity-stream.showSponsored", false);',
            'user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);',
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

    theme_css = style_source.read_text(encoding="utf-8")

    try:
        chrome_css, content_css = split_stylesheets(theme_css)
    except RuntimeError as error:
        raise SystemExit(str(error)) from error

    try:
        replace_managed_block(profile_path / "chrome" / "userChrome.css", BEGIN, END, chrome_css)
        if content_css:
            replace_managed_block(
                profile_path / "chrome" / "userContent.css",
                BEGIN,
                END,
                content_css,
            )
    except RuntimeError as error:
        raise SystemExit(str(error)) from error
    print(f"Ensured managed Firefox UI settings in {profile_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
