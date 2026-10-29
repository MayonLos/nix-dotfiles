#!/usr/bin/env python3
"""Seed Firefox UI preferences and the managed browser-chrome stylesheet."""

import os
import json
from pathlib import Path
import sys

from firefox_profile import (
    BEGIN,
    CONTENT_BEGIN,
    CONTENT_END,
    END,
    _default_profile_path,
    preference_defaults,
    PREF_BEGIN,
    PREF_END,
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

    # Initial placement only; preference_defaults leaves existing layouts alone.
    # currentVersion=28 is the schema in locked Firefox 159 CustomizableUI.
    toolbar = json.dumps({
        "placements": {"nav-bar": [
            "sidebar-button", "back-button", "forward-button", "stop-reload-button",
            "urlbar-container", "downloads-button", "unified-extensions-button",
        ]},
        "currentVersion": 28,
        "newElementCount": 0,
    }, separators=(",", ":"))
    user_prefs = "\n".join(
        [
            f'user_pref("browser.uiCustomization.state", {json.dumps(toolbar)});',
            # Locked Firefox 159's experimental Nova layout adds a content
            # frame and a different toolbar; keep the native compact layout.
            'user_pref("browser.nova.enabled", false);',
            # Current Firefox uses these general Linux/DMABuf preferences;
            # media.ffmpeg.vaapi.enabled is absent from Firefox 159's pref
            # definitions, and force-enabled would bypass decoder blocklists.
            'user_pref("media.hardware-video-decoding.enabled", true);',
            'user_pref("widget.dmabuf.enabled", true);',
            'user_pref("widget.dmabuf-webgl.enabled", true);',
            'user_pref("sidebar.revamp", true);',
            'user_pref("sidebar.verticalTabs", true);',
            # Firefox owns visibility, saved width and launcherExpanded. The
            # native Ctrl+Alt+Z / toolbar button toggles the icon rail.
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
            PREF_BEGIN,
            PREF_END,
            preference_defaults(profile_path, user_prefs),
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
