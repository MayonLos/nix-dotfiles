#!/usr/bin/env python3
"""Migrate repository-owned qt6ct defaults while preserving GUI choices."""

import os
import re
import stat
import sys
from pathlib import Path


def safe_regular_file(path: Path) -> bool:
    """Reject symlinks at the file and every existing parent component."""
    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for component in absolute.parts[1:-1]:
        current /= component
        try:
            if stat.S_ISLNK(current.lstat().st_mode):
                return False
        except FileNotFoundError:
            return False
    try:
        return stat.S_ISREG(absolute.lstat().st_mode)
    except FileNotFoundError:
        return False


def safe_destination(path: Path) -> bool:
    """Allow missing parents, but never follow symlink components on writes."""
    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for component in absolute.parts[1:-1]:
        current /= component
        try:
            if stat.S_ISLNK(current.lstat().st_mode):
                return False
        except FileNotFoundError:
            continue
    try:
        return not stat.S_ISLNK(absolute.lstat().st_mode)
    except FileNotFoundError:
        return True


def split_qt_string_list(value: str) -> list[str] | None:
    # QSettings::IniFormat encodes QStringList as ordinary comma-separated
    # values (quoting entries containing separators). @StringList is not a
    # QSettings metatype and would be read back as literal path text.
    value = value.strip()
    if value == "@Invalid()":
        return []
    if value.startswith("@"):
        # Preserve typed values and @@-escaped strings without re-encoding them.
        return None
    if not value:
        return []
    items: list[str] = []
    item: list[str] = []
    escaped = False
    quoted = False
    was_quoted = False
    after_quote = False
    for char in value:
        if escaped:
            escapes = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v", "\\": "\\", '"': '"'}
            if char not in escapes:
                # QSettings also accepts hexadecimal escapes. Preserve any
                # syntax this bounded migration cannot round-trip exactly.
                return None
            item.append(escapes[char])
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            if not quoted and not "".join(item).strip():
                item = []
            quoted = not quoted
            was_quoted = True
            after_quote = not quoted
        elif char in ";#" and not quoted:
            # Do not consume a possible trailing INI comment as path text.
            return None
        elif char == "," and not quoted:
            part = "".join(item)
            items.append(part if was_quoted else part.strip())
            item = []
            was_quoted = False
            after_quote = False
        elif after_quote and char in " \t":
            continue
        else:
            item.append(char)
            after_quote = False
    if escaped or quoted:
        return None
    part = "".join(item)
    items.append(part if was_quoted else part.strip())
    if any(entry.startswith("@") for entry in items):
        return None
    return items


def encode_qt_string_list(items: list[str]) -> str:
    def escape(item: str) -> str:
        replacements = {"\\": "\\\\", '"': '\\"', "\a": "\\a", "\b": "\\b", "\f": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\v": "\\v"}
        value = "".join(replacements.get(char, char) for char in item)
        if any(char in item for char in ",;=") or item.startswith((" ", "\t")) or item.endswith((" ", "\t")):
            return '"' + value + '"'
        return value

    return ", ".join(escape(item) for item in items)


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--safe-destination":
        sys.exit(0 if safe_destination(Path(sys.argv[2])) else 1)
    path = Path(sys.argv[1])
    stylesheet, icon_theme, sans, mono = sys.argv[2:]
    if not safe_regular_file(path):
        return

    raw = path.read_bytes()
    text = raw.decode("utf-8")
    lines = text.splitlines(keepends=True)
    newline = "\r\n" if b"\r\n" in raw else "\n"
    section = ""
    interface_insert: int | None = None
    interface_found = False
    stylesheet_found = False
    output = []

    font_defaults = {
        "general": (
            {"Noto Sans CJK SC,11,-1,5,400,0,0,0,0,0", f"{sans},11,-1,5,400,0,0,0,0,0"},
            f"{sans},11,-1,5,50,0,0,0,0,0",
        ),
        "fixed": (
            {"JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0", f"{mono},11,-1,5,400,0,0,0,0,0"},
            f"{mono},11,-1,5,50,0,0,0,0,0",
        ),
    }
    for line in lines:
        bare = line.rstrip("\r\n")
        match = re.fullmatch(r"\[([^]]+)\]", bare.strip())
        if match:
            if section == "Interface" and interface_insert is None:
                interface_insert = len(output)
            section = match.group(1)
            if section == "Interface":
                interface_found = True
                interface_insert = len(output) + 1
            output.append(line)
            continue

        if section == "Fonts" and "=" in bare:
            key, _, value = bare.partition("=")
            default = font_defaults.get(key)
            if default is not None and (
                value in default[0] or split_qt_string_list(value) in [[item] for item in default[0]]
            ):
                line = f"{key}={encode_qt_string_list([default[1]])}" + ("\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else "")
        elif section == "Appearance" and bare == "icon_theme=Papirus-Dark":
            line = f"icon_theme={icon_theme}" + ("\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else "")
        elif section == "Interface" and bare.startswith("stylesheets="):
            stylesheet_found = True
            existing = split_qt_string_list(bare.partition("=")[2])
            if existing is not None and stylesheet not in existing:
                value = encode_qt_string_list(existing + [stylesheet])
                line = f"stylesheets={value}" + ("\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else "")
        output.append(line)

    if not interface_found:
        if output and not output[-1].endswith(("\n", "\r")):
            output[-1] += newline
        output.extend([f"[Interface]{newline}", f"stylesheets={stylesheet}{newline}"])
    elif not stylesheet_found:
        if interface_insert is None:
            interface_insert = len(output)
        if interface_insert > 0 and not output[interface_insert - 1].endswith(("\n", "\r")):
            output[interface_insert - 1] += newline
        output.insert(interface_insert, f"stylesheets={stylesheet}{newline}")

    result = "".join(output).encode("utf-8")
    if result != raw:
        path.write_bytes(result)


if __name__ == "__main__":
    main()
