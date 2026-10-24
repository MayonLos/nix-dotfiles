"""Shared Firefox profile and managed-configuration helpers."""

import configparser
from pathlib import Path
import tempfile

BEGIN = "/* BEGIN nix-dotfiles managed Firefox theme */"
END = "/* END nix-dotfiles managed Firefox theme */"


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
    if (begin in old) != (end in old):
        raise RuntimeError(f"Incomplete managed markers in {path}; preserving the file")

    block = f"{begin}\n{content.rstrip()}\n{end}"
    if begin in old:
        start = old.index(begin)
        finish = old.index(end, start) + len(end)
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
