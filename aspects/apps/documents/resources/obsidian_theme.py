#!/usr/bin/env python3
"""Render paths and enable the managed snippet only for registered vaults."""

from __future__ import annotations

import json
import os
import stat
import tempfile
from pathlib import Path
from typing import Any


SNIPPET_NAME = "noctalia"


class UnsafePathError(RuntimeError):
    pass


def _absolute(path: Path) -> Path:
    if not path.is_absolute():
        raise ValueError(f"expected an absolute path: {path}")
    return Path(os.path.abspath(path))


def _assert_no_symlink_components(path: Path) -> Path:
    path = _absolute(path)
    for component in reversed((path, *path.parents)):
        try:
            mode = component.lstat().st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode):
            raise UnsafePathError(f"refusing symlink path component: {component}")
    return path


def _config_home() -> Path:
    configured = os.environ.get("XDG_CONFIG_HOME")
    path = Path(configured) if configured else Path.home() / ".config"
    path = _assert_no_symlink_components(path)
    if not path.is_dir():
        raise FileNotFoundError(f"XDG config directory does not exist: {path}")
    return path


def _registered_vaults() -> list[Path]:
    config_home = _config_home()
    registry = config_home / "obsidian" / "obsidian.json"
    _assert_no_symlink_components(registry)
    if not registry.exists():
        return []
    with registry.open(encoding="utf-8") as stream:
        data = json.load(stream)
    if not isinstance(data, dict) or not isinstance(data.get("vaults", {}), dict):
        raise ValueError(f"invalid Obsidian vault registry: {registry}")

    vaults: list[Path] = []
    seen: set[Path] = set()
    for entry in data.get("vaults", {}).values():
        if not isinstance(entry, dict) or "path" not in entry:
            continue
        raw_path = entry["path"]
        if not isinstance(raw_path, str) or not raw_path:
            raise ValueError("vault registry contains a non-path entry")
        if "\n" in raw_path or "\r" in raw_path:
            raise ValueError("vault path cannot contain line breaks")
        vault = _assert_no_symlink_components(Path(raw_path))
        # Obsidian retains moved/offline vaults in its registry. Skip only
        # missing paths so one disconnected vault does not block the others.
        if not vault.exists():
            continue
        if not vault.is_dir():
            raise NotADirectoryError(f"registered vault is not a directory: {vault}")
        if vault.resolve(strict=True) != vault:
            raise UnsafePathError(f"registered vault is not a real directory: {vault}")
        if vault not in seen:
            seen.add(vault)
            vaults.append(vault)
    return vaults


def _mkdir_checked(path: Path) -> Path:
    path = _absolute(path)
    for component in reversed((path, *path.parents)):
        try:
            mode = component.lstat().st_mode
        except FileNotFoundError:
            component.mkdir()
            mode = component.lstat().st_mode
        if stat.S_ISLNK(mode):
            raise UnsafePathError(f"refusing symlink path component: {component}")
        if not stat.S_ISDIR(mode):
            raise NotADirectoryError(component)
    return path


def _vault_files(vault: Path) -> tuple[Path, Path]:
    vault = _assert_no_symlink_components(vault)
    if not vault.is_dir():
        raise FileNotFoundError(f"registered vault is not a directory: {vault}")
    obsidian = vault / ".obsidian"
    snippets = _mkdir_checked(obsidian / "snippets")
    _assert_no_symlink_components(obsidian)
    css = snippets / f"{SNIPPET_NAME}.css"
    _assert_no_symlink_components(css)
    try:
        css_mode = css.lstat().st_mode
    except FileNotFoundError:
        pass
    else:
        if not stat.S_ISREG(css_mode):
            raise UnsafePathError(f"refusing non-regular snippet target: {css}")
    appearance = obsidian / "appearance.json"
    _assert_no_symlink_components(appearance)
    return css, appearance


def output_paths() -> list[Path]:
    return [_vault_files(vault)[0] for vault in _registered_vaults()]


def enable_snippet() -> None:
    for vault in _registered_vaults():
        _, appearance = _vault_files(vault)
        if appearance.exists():
            mode = appearance.lstat().st_mode
            if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
                raise UnsafePathError(f"refusing non-regular appearance file: {appearance}")
            with appearance.open(encoding="utf-8") as stream:
                data: Any = json.load(stream)
            if not isinstance(data, dict):
                raise ValueError(f"appearance data must be a JSON object: {appearance}")
            snippets = data.get("enabledCssSnippets", [])
            if not isinstance(snippets, list) or any(not isinstance(x, str) for x in snippets):
                raise ValueError(f"enabledCssSnippets must be a list of strings: {appearance}")
            if SNIPPET_NAME in snippets:
                continue
            data["enabledCssSnippets"] = [*snippets, SNIPPET_NAME]
            mode_bits = stat.S_IMODE(mode)
        else:
            data = {"enabledCssSnippets": [SNIPPET_NAME]}
            mode_bits = 0o600

        fd, temporary = tempfile.mkstemp(prefix=".appearance.json.", dir=appearance.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(data, stream, indent=2, ensure_ascii=False)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, mode_bits)
            _assert_no_symlink_components(appearance.parent)
            if appearance.is_symlink():
                raise UnsafePathError(f"refusing symlink appearance file: {appearance}")
            os.replace(temporary, appearance)
        finally:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("outputs", "enable"))
    args = parser.parse_args()
    if args.action == "outputs":
        for path in output_paths():
            print(path)
    else:
        enable_snippet()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
