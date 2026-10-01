#!/usr/bin/env python3
"""Merge Noctalia's rendered palette CSS into Firefox's managed CSS block."""

import configparser
import os
from pathlib import Path
import sys
import tempfile

BEGIN = "/* BEGIN nix-dotfiles managed Firefox theme */"
END = "/* END nix-dotfiles managed Firefox theme */"


def default_profile(profile_root: Path) -> Path | None:
    profiles_ini = profile_root / "profiles.ini"
    if not profiles_ini.is_file():
        return None

    ini = configparser.ConfigParser(interpolation=None)
    ini.read(profiles_ini)
    sections = ini.sections()
    install_default = next(
        (
            ini[section].get("Default")
            for section in sections
            if section.startswith("Install") and ini[section].get("Default")
        ),
        None,
    )
    selected = None
    if install_default:
        selected = next(
            (
                ini[section]
                for section in sections
                if section.startswith("Profile") and ini[section].get("Path") == install_default
            ),
            None,
        )
    if selected is None:
        selected = next(
            (
                ini[section]
                for section in sections
                if section.startswith("Profile") and ini[section].getboolean("Default", fallback=False)
            ),
            None,
        )
    if selected is None:
        raise RuntimeError(f"No default Firefox profile found in {profiles_ini}")

    profile_path = Path(selected["Path"])
    if selected.getboolean("IsRelative", fallback=True):
        profile_path = profile_root / profile_path
    profile_path = profile_path.expanduser().resolve()
    return profile_path if profile_path.is_dir() else None


def replace_managed_block(path: Path, content: str) -> bool:
    if path.is_symlink() or path.parent.is_symlink():
        raise RuntimeError(f"Refusing to modify symlinked Firefox config: {path}")
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    if (BEGIN in old) != (END in old):
        raise RuntimeError(f"Incomplete managed markers in {path}; preserving the file")

    block = f"{BEGIN}\n{content.rstrip()}\n{END}"
    if BEGIN in old:
        start = old.index(BEGIN)
        finish = old.index(END, start) + len(END)
        new = old[:start] + block + old[finish:]
    else:
        new = old.rstrip() + ("\n\n" if old.strip() else "") + block + "\n"
    if new == old:
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as out:
        out.write(new)
        temp_path = Path(out.name)
    temp_path.chmod(mode)
    temp_path.replace(path)
    return True


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
    changed = replace_managed_block(css_path, css)
    if changed:
        print(f"Updated Noctalia palette CSS in {css_path}; restart Firefox to see palette changes")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, configparser.Error) as error:
        print(f"noctalia-firefox-theme: {error}", file=sys.stderr)
        raise SystemExit(1)
