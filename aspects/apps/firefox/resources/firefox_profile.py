"""Shared Firefox profile and managed-configuration helpers."""

import configparser
import json
import re
from pathlib import Path
import tempfile

BEGIN = "/* BEGIN nix-dotfiles managed Firefox theme */"
END = "/* END nix-dotfiles managed Firefox theme */"
CONTENT_BEGIN = "/* >>> nix-dotfiles userContent segment >>>"
CONTENT_END = "<<< nix-dotfiles userContent segment <<< */"


def split_stylesheets(source: str) -> tuple[str, str]:
    """Split the commented userContent payload from the shared palette template."""
    if (CONTENT_BEGIN in source) != (CONTENT_END in source):
        raise RuntimeError("Incomplete userContent segment markers in Firefox CSS template")
    if CONTENT_BEGIN not in source:
        return source.rstrip(), ""
    if source.count(CONTENT_BEGIN) != 1 or source.count(CONTENT_END) != 1:
        raise RuntimeError("Duplicate userContent segment markers in Firefox CSS template")
    start = source.index(CONTENT_BEGIN)
    finish = source.index(CONTENT_END, start)
    if finish < start:
        raise RuntimeError("Reversed userContent segment markers in Firefox CSS template")
    content_start = start + len(CONTENT_BEGIN)
    chrome = source[:start] + source[finish + len(CONTENT_END) :]
    content = source[content_start:finish]
    return chrome.rstrip(), content.strip()


def _default_profile_path(profile_root: Path) -> Path | None:
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
    return profile_path.expanduser().resolve()


def default_profile(profile_root: Path) -> Path | None:
    """Return the existing default profile, or None if it is not initialized."""
    profile_path = _default_profile_path(profile_root)
    return profile_path if profile_path is not None and profile_path.is_dir() else None


def replace_managed_block(path: Path, begin: str, end: str, content: str) -> bool:
    if path.is_symlink() or path.parent.is_symlink():
        raise RuntimeError(f"Refusing to modify symlinked Firefox config: {path}")
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    if (begin in old) != (end in old) or old.count(begin) != old.count(end):
        raise RuntimeError(f"Incomplete managed markers in {path}; preserving the file")
    if old.count(begin) > 1:
        raise RuntimeError(f"Duplicate managed markers in {path}; preserving the file")

    block = f"{begin}\n{content.rstrip()}\n{end}"
    if begin in old:
        start = old.index(begin)
        end_start = old.find(end, start + len(begin))
        if end_start < 0:
            raise RuntimeError(f"Reversed managed markers in {path}; preserving the file")
        finish = end_start + len(end)
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


PREF_BEGIN = "// BEGIN nix-dotfiles managed Firefox UI"
PREF_END = "// END nix-dotfiles managed Firefox UI"
PREF_PATTERN = re.compile(r'^\s*user_pref\(\s*("(?:[^"\\]|\\.)*")\s*,\s*(.*?)\s*\);', re.MULTILINE)


def preference_defaults(profile: Path, defaults: str) -> str:
    """Keep defaults only while the user has not chosen another value.

    prefs.js records Firefox UI changes. Compare it with the previous managed
    value, not the new default, so upgrading a default does not steal a choice.
    An explicit user.js preference outside our markers always wins. No file
    outside the managed user.js block is written.
    """
    path = profile / "user.js"
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    previous = ""
    outside = old
    if PREF_BEGIN in old and PREF_END in old:
        start = old.index(PREF_BEGIN)
        finish = old.find(PREF_END, start + len(PREF_BEGIN))
        if finish >= 0:
            previous = old[start + len(PREF_BEGIN):finish]
            outside = old[:start] + old[finish + len(PREF_END):]

    def prefs(text: str) -> dict:
        return {json.loads(key): value for key, value in PREF_PATTERN.findall(text)}

    explicit = prefs(outside)
    prior = prefs(previous)
    saved_path = profile / "prefs.js"
    saved = prefs(saved_path.read_text(encoding="utf-8")) if saved_path.exists() else {}
    result = []
    for line in defaults.splitlines():
        match = PREF_PATTERN.match(line)
        if match is None:
            continue
        key = json.loads(match[1])
        if key in explicit:
            continue
        if key in saved:
            # Unknown/complex JS values are user data too: leave them alone.
            try:
                unchanged = key in prior and json.loads(saved[key]) == json.loads(prior[key])
            except (ValueError, TypeError):
                unchanged = False
            if not unchanged:
                continue
        result.append(line)
    return "\n".join(result)
