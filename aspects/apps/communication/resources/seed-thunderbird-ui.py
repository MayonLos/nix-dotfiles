#!/usr/bin/env python3
"""Merge managed Thunderbird chrome and UI defaults into an existing profile."""

import configparser
import os
from pathlib import Path
import stat
import sys
import tempfile

CSS_BEGIN = b"/* BEGIN nix-dotfiles managed Thunderbird theme */"
CSS_END = b"/* END nix-dotfiles managed Thunderbird theme */"
PREF_BEGIN = b"// BEGIN nix-dotfiles managed Thunderbird UI"
PREF_END = b"// END nix-dotfiles managed Thunderbird UI"
MANAGED_PREFS = (
    ("toolkit.legacyUserProfileCustomizations.stylesheets", "true"),
    ("mail.uidensity", "0"),
)


class SeedError(RuntimeError):
    pass


def reject_symlink_components(path: Path) -> None:
    """Check the lexical path, including existing ancestors, before resolving it."""
    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        if current.is_symlink():
            raise SeedError(f"Refusing symlink path: {current}")


def profile_root() -> Path:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    candidates = [config_home / "thunderbird", Path.home() / ".thunderbird"]
    for candidate in candidates:
        reject_symlink_components(candidate)
        if (candidate / "profiles.ini").is_file():
            return candidate
    return candidates[0]


def default_profile(root: Path) -> Path | None:
    ini_path = root / "profiles.ini"
    if not ini_path.is_file():
        return None
    reject_symlink_components(ini_path)
    ini = configparser.ConfigParser(interpolation=None)
    try:
        ini.read(ini_path, encoding="utf-8")
    except (OSError, configparser.Error) as error:
        raise SeedError(f"Cannot read {ini_path}: {error}") from error

    sections = ini.sections()
    install_path = next(
        (ini[name].get("Default") for name in sections if name.startswith("Install") and ini[name].get("Default")),
        None,
    )
    selected = next(
        (
            ini[name]
            for name in sections
            if name.startswith("Profile")
            and install_path is not None
            and ini[name].get("Path") == install_path
        ),
        None,
    )
    if selected is None:
        selected = next(
            (ini[name] for name in sections if name.startswith("Profile") and ini[name].getboolean("Default", fallback=False)),
            None,
        )
    if selected is None or not selected.get("Path"):
        raise SeedError(f"No default Thunderbird profile in {ini_path}")

    path = Path(selected["Path"])
    if selected.getboolean("IsRelative", fallback=True):
        path = root / path
    path = Path(os.path.abspath(path))
    reject_symlink_components(path)
    return path if path.is_dir() else None


def replace_block(old: bytes, begin: bytes, end: bytes, content: bytes, label: str) -> bytes:
    begins, ends = old.count(begin), old.count(end)
    if begins != ends or begins > 1:
        raise SeedError(f"Incomplete or duplicate {label} markers; preserving the file")
    if begins:
        start = old.index(begin)
        end_at = old.index(end)
        if end_at < start + len(begin):
            raise SeedError(f"Reversed {label} markers; preserving the file")
        finish = end_at + len(end)
        block = begin + b"\n" + content.rstrip(b"\r\n") + b"\n" + end
        return old[:start] + block + old[finish:]
    block = begin + b"\n" + content.rstrip(b"\r\n") + b"\n" + end
    separator = b"" if not old else (b"" if old.endswith((b"\n", b"\r")) else b"\n")
    if old and not old.endswith((b"\n\n", b"\r\n\r\n")):
        separator += b"\n"
    return old + separator + block + b"\n"


def without_block(old: bytes, begin: bytes, end: bytes) -> bytes:
    if not begin in old:
        return old
    start = old.index(begin)
    finish = old.index(end, start) + len(end)
    return old[:start] + old[finish:]


def _read_js_string(source: str, index: int) -> tuple[str, int]:
    quote = source[index]
    index += 1
    value: list[str] = []
    escapes = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}
    while index < len(source):
        char = source[index]
        index += 1
        if char == quote:
            break
        if char != "\\":
            value.append(char)
            continue
        if index >= len(source):
            break
        escaped = source[index]
        index += 1
        if escaped in "\r\n":
            if escaped == "\r" and index < len(source) and source[index] == "\n":
                index += 1
            continue
        if escaped in escapes:
            value.append(escapes[escaped])
        elif escaped in ("x", "u"):
            if escaped == "u" and index < len(source) and source[index] == "{":
                close = source.find("}", index + 1)
                if close >= 0:
                    try:
                        value.append(chr(int(source[index + 1 : close], 16)))
                        index = close + 1
                        continue
                    except (ValueError, OverflowError):
                        pass
            width = 2 if escaped == "x" else 4
            digits = source[index : index + width]
            if len(digits) == width:
                try:
                    value.append(chr(int(digits, 16)))
                    index += width
                    continue
                except (ValueError, OverflowError):
                    pass
            value.extend(("\\", escaped))
        else:
            # In JavaScript, identity escapes yield the escaped character.
            value.append(escaped)
    return "".join(value), index


def _js_tokens(source: bytes):
    """Yield identifiers, strings, and punctuation while discarding JS comments."""
    text = source.decode("utf-8", errors="replace")
    index = 0
    while index < len(text):
        char = text[index]
        if char.isspace():
            index += 1
            continue
        if text.startswith("//", index):
            newline = text.find("\n", index + 2)
            index = len(text) if newline < 0 else newline + 1
            continue
        if text.startswith("/*", index):
            close = text.find("*/", index + 2)
            index = len(text) if close < 0 else close + 2
            continue
        if char in ("'", '"', "`"):
            value, index = _read_js_string(text, index)
            yield "string", value
            continue
        if char.isalpha() or char in "_$":
            finish = index + 1
            while finish < len(text) and (text[finish].isalnum() or text[finish] in "_$"):
                finish += 1
            yield "identifier", text[index:finish]
            index = finish
            continue
        yield "punctuation", char
        index += 1


def has_explicit_pref(source: bytes, pref: str) -> bool:
    # Comments are discarded and strings are emitted as opaque tokens, so a
    # textual example cannot masquerade as an active call. Whitespace/comments
    # between call tokens are naturally accepted, including across lines.
    tokens = iter(_js_tokens(source))
    pending = []
    for token in tokens:
        pending.append(token)
        if len(pending) > 3:
            pending.pop(0)
        if (
            len(pending) == 3
            and pending[0] == ("identifier", "user_pref")
            and pending[1] == ("punctuation", "(")
            and pending[2] == ("string", pref)
        ):
            return True
    return False


def prepare(path: Path, begin: bytes, end: bytes, content: bytes, label: str) -> tuple[bytes, int | None]:
    reject_symlink_components(path)
    try:
        old = path.read_bytes() if path.exists() else b""
        mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else None
    except OSError as error:
        raise SeedError(f"Cannot read {path}: {error}") from error
    return replace_block(old, begin, end, content, label), mode


def atomic_write(path: Path, content: bytes, mode: int | None) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    reject_symlink_components(path)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp = Path(temp_name)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temp, mode if mode is not None else 0o644)
        return temp
    except Exception:
        temp.unlink(missing_ok=True)
        raise


def main() -> int:
    if len(sys.argv) != 2:
        raise SeedError("usage: seed-thunderbird-ui.py USER_CHROME_CSS")
    css_source = Path(sys.argv[1])
    try:
        css = css_source.read_bytes()
    except OSError as error:
        raise SeedError(f"Cannot read Thunderbird CSS {css_source}: {error}") from error
    if not css.strip():
        raise SeedError("Thunderbird managed CSS is empty")

    root = profile_root()
    profile = default_profile(root)
    if profile is None:
        print(f"Thunderbird profile not initialized under {root}; skipping UI seed")
        return 0

    css_path = profile / "chrome" / "userChrome.css"
    prefs_path = profile / "user.js"
    # Validate both files and their markers before creating or replacing either.
    new_css, css_mode = prepare(css_path, CSS_BEGIN, CSS_END, css, "Thunderbird CSS")
    reject_symlink_components(prefs_path)
    try:
        old_prefs = prefs_path.read_bytes() if prefs_path.exists() else b""
        prefs_mode = stat.S_IMODE(prefs_path.stat().st_mode) if prefs_path.exists() else None
    except OSError as error:
        raise SeedError(f"Cannot read {prefs_path}: {error}") from error
    # Validate existing preference markers before examining their surrounding text.
    replace_block(old_prefs, PREF_BEGIN, PREF_END, b"", "Thunderbird preference")
    outside = without_block(old_prefs, PREF_BEGIN, PREF_END)
    prefs_js = profile / "prefs.js"
    reject_symlink_components(prefs_js)
    try:
        saved_prefs = prefs_js.read_bytes() if prefs_js.exists() else b""
    except OSError as error:
        raise SeedError(f"Cannot read {prefs_js}: {error}") from error
    prefs = [
        f'user_pref("{key}", {value});'.encode("ascii")
        for key, value in MANAGED_PREFS
        if not has_explicit_pref(outside, key) and not has_explicit_pref(saved_prefs, key)
    ]
    new_user = replace_block(old_prefs, PREF_BEGIN, PREF_END, b"\n".join(prefs), "Thunderbird preference")

    if new_css == (css_path.read_bytes() if css_path.exists() else b"") and new_user == old_prefs:
        return 0
    staged: list[tuple[Path, Path]] = []
    try:
        if new_css != (css_path.read_bytes() if css_path.exists() else b""):
            staged.append((css_path, atomic_write(css_path, new_css, css_mode)))
        if new_user != old_prefs:
            staged.append((prefs_path, atomic_write(prefs_path, new_user, prefs_mode)))
        for destination, temporary in staged:
            temporary.replace(destination)
    except Exception:
        for _, temporary in staged:
            temporary.unlink(missing_ok=True)
        raise
    print(f"Ensured managed Thunderbird UI settings in {profile}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, SeedError) as error:
        print(f"thunderbird-ui-seed: {error}", file=sys.stderr)
        raise SystemExit(1)
