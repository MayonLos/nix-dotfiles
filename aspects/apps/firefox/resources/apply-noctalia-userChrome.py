#!/usr/bin/env python3
"""Merge Noctalia's rendered palette CSS into Firefox's managed CSS block."""

import configparser
import os
from pathlib import Path
import sys

from firefox_profile import BEGIN, END, default_profile, replace_managed_block


def main() -> int:
    if len(sys.argv) != 2:
        raise RuntimeError("usage: apply-noctalia-userChrome.py RENDERED_CSS")
    rendered_css = Path(sys.argv[1])
    if not rendered_css.is_file():
        raise RuntimeError(f"Noctalia rendered Firefox CSS not found: {rendered_css}")
    css = rendered_css.read_text(encoding="utf-8")
    if "{{" in css or "}}" in css:
        raise RuntimeError(f"Noctalia left unrendered template expressions in {rendered_css}")

    config_home = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    profile_root = config_home / "mozilla" / "firefox"
    profile = default_profile(profile_root)
    if profile is None:
        print(f"Firefox profile not initialized at {profile_root}; theme will apply after Firefox is initialized")
        return 0

    css_path = profile / "chrome" / "userChrome.css"
    changed = replace_managed_block(css_path, BEGIN, END, css)
    if changed:
        print(f"Updated Noctalia palette CSS in {css_path}; restart Firefox to see palette changes")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"noctalia-firefox-theme: {error}", file=sys.stderr)
        raise SystemExit(1)
