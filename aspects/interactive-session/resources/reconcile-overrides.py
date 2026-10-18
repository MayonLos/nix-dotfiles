#!/usr/bin/env python3
"""Remove public Noctalia sidecar paths owned by the Nix settings renderer."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import time
from collections.abc import Mapping, MutableMapping
from typing import Any

import tomlkit


LEGACY_TEMPLATE_PATH = ("theme", "templates", "user", "noctalia-mango")


class ReconcileError(Exception):
    pass


def _plain(value: Any) -> Any:
    if hasattr(value, "unwrap"):
        value = value.unwrap()
    if isinstance(value, Mapping):
        return {str(key): _plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_plain(item) for item in value]
    if isinstance(value, (dt.datetime, dt.date, dt.time)):
        return value.isoformat()
    return value


def _node_at(document: Any, path: tuple[str, ...]) -> Any | None:
    node = document
    for part in path:
        if not isinstance(node, Mapping) or part not in node:
            return None
        node = node[part]
    return node


def _remove_at(document: Any, path: tuple[str, ...]) -> Any | None:
    parent = _node_at(document, path[:-1]) if len(path) > 1 else document
    if not isinstance(parent, MutableMapping) or path[-1] not in parent:
        return None
    node = parent[path[-1]]
    del parent[path[-1]]
    return node


def _managed_paths(sidecar: Any, managed: dict[str, Any], prefix: tuple[str, ...] = ()) -> list[tuple[str, ...]]:
    matches: list[tuple[str, ...]] = []
    for key, declaration in managed.items():
        if not isinstance(key, str):
            raise ReconcileError("managed JSON keys must be strings")
        path = prefix + (key,)
        current = _node_at(sidecar, path)
        if isinstance(declaration, dict):
            if isinstance(current, Mapping):
                matches.extend(_managed_paths(sidecar, declaration, path))
        elif current is not None:
            # Values describe public managed paths, not equality constraints.
            # Arrays and other non-table values are each one leaf.
            matches.append(path)
    return matches


def _fingerprint(path: Path) -> tuple[bytes, os.stat_result]:
    try:
        before = path.lstat()
    except FileNotFoundError:
        raise
    if stat.S_ISLNK(before.st_mode):
        raise ReconcileError(f"refusing symlink state file: {path}")
    if not stat.S_ISREG(before.st_mode):
        raise ReconcileError(f"state path is not a regular file: {path}")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    try:
        opened = os.fstat(fd)
        if (before.st_dev, before.st_ino) != (opened.st_dev, opened.st_ino):
            raise ReconcileError("state file changed while it was being opened")
        chunks = []
        while True:
            block = os.read(fd, 1024 * 1024)
            if not block:
                break
            chunks.append(block)
        return b"".join(chunks), opened
    finally:
        os.close(fd)


def _proc_has_noctalia(uid: int, proc_root: Path = Path("/proc")) -> bool:
    proc = proc_root
    try:
        entries = list(proc.iterdir())
    except OSError as exc:
        raise ReconcileError(f"cannot inspect /proc for the Noctalia safety guard: {exc}") from exc
    for entry in entries:
        if not entry.name.isdecimal():
            continue
        try:
            if entry.stat().st_uid != uid:
                continue
            # Inspect executable link metadata only. Do not read environ/cmdline.
            executable = os.readlink(entry / "exe")
            executable_name = Path(executable.removesuffix(" (deleted)")).name
            if executable_name in {"noctalia", ".noctalia-wrapped"}:
                return True
        except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
            continue
    return False


def _backup(directory: Path, paths_and_values: list[dict[str, Any]]) -> Path:
    if directory.is_symlink():
        raise ReconcileError(f"refusing symlink backup directory: {directory}")
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not directory.is_dir():
        raise ReconcileError(f"backup path is not a directory: {directory}")
    os.chmod(directory, 0o700)
    payload = {
        "format": 1,
        "source": "Noctalia settings.toml public managed overrides",
        "removed": paths_and_values,
    }
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
    for _ in range(5):
        stamp = time.time_ns()
        target = directory / f"noctalia-overrides-{stamp}.json"
        try:
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            continue
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb", closefd=False) as stream:
                stream.write(encoded)
                stream.flush()
                os.fsync(fd)
        finally:
            os.close(fd)
        dir_fd = os.open(directory, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
        return target
    raise ReconcileError(f"could not allocate a unique backup in {directory}")


def _atomic_replace(path: Path, original: bytes, info: os.stat_result, replacement: bytes) -> None:
    parent = path.parent
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=parent)
    temp = Path(temp_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(replacement)
            stream.flush()
            os.fsync(stream.fileno())

        os.chown(temp, info.st_uid, info.st_gid, follow_symlinks=False)
        os.chmod(temp, stat.S_IMODE(info.st_mode), follow_symlinks=False)
        try:
            names = os.listxattr(path, follow_symlinks=False)
            for name in names:
                value = os.getxattr(path, name, follow_symlinks=False)
                os.setxattr(temp, name, value, follow_symlinks=False)
        except OSError as exc:
            raise ReconcileError(f"cannot preserve state file extended attributes: {exc}") from exc

        # Recheck both identity and content immediately before replacement.
        current, current_info = _fingerprint(path)
        if current != original or (
            current_info.st_dev,
            current_info.st_ino,
            current_info.st_uid,
            current_info.st_gid,
            stat.S_IMODE(current_info.st_mode),
            current_info.st_mtime_ns,
            current_info.st_ctime_ns,
        ) != (
            info.st_dev,
            info.st_ino,
            info.st_uid,
            info.st_gid,
            stat.S_IMODE(info.st_mode),
            info.st_mtime_ns,
            info.st_ctime_ns,
        ):
            raise ReconcileError("state file changed during reconciliation; refusing to overwrite it")
        os.replace(temp, path)
        dir_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    finally:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass


def reconcile(state_path: Path, managed_path: Path, backup_dir: Path, require_no_noctalia: bool = False) -> list[tuple[str, ...]]:
    if managed_path.is_symlink():
        raise ReconcileError(f"refusing symlink managed JSON file: {managed_path}")
    try:
        managed = json.loads(managed_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ReconcileError(f"cannot read managed JSON: {exc}") from exc
    if not isinstance(managed, dict):
        raise ReconcileError("managed JSON root must be an object")

    current_uid = os.getuid()
    if require_no_noctalia and _proc_has_noctalia(current_uid):
        raise ReconcileError("Noctalia is still running for this user; gracefully stop the old shell writer before starting the managed service (no session logout is required)")

    if not state_path.exists() and not state_path.is_symlink():
        return []
    original, info = _fingerprint(state_path)
    if require_no_noctalia and info.st_uid != current_uid:
        raise ReconcileError("Noctalia state file is owned by a different UID; refusing to reconcile it")
    try:
        document = tomlkit.parse(original.decode("utf-8"))
    except (UnicodeError, tomlkit.exceptions.ParseError) as exc:
        raise ReconcileError(f"refusing invalid Noctalia TOML: {exc}") from exc

    paths = _managed_paths(document, managed)
    legacy = _node_at(document, LEGACY_TEMPLATE_PATH)
    if legacy is not None:
        paths.append(LEGACY_TEMPLATE_PATH)
    if not paths:
        return []

    # Deduplicate and retain only maximal removals. The old template table is
    # intentionally one explicit public path; no neighboring theme state is touched.
    paths = sorted(set(paths), key=lambda path: (len(path), path))
    selected: list[tuple[str, ...]] = []
    for path in paths:
        if not any(path[: len(parent)] == parent for parent in selected):
            selected.append(path)

    removed: list[dict[str, Any]] = []
    for path in selected:
        node = _remove_at(document, path)
        if node is not None:
            removed.append({"path": list(path), "value": _plain(node)})
    if not removed:
        return []

    # Back up only precisely selected public configuration values, never the state file.
    _backup(backup_dir, removed)
    rendered = tomlkit.dumps(document).encode("utf-8")
    _atomic_replace(state_path, original, info, rendered)
    return [tuple(record["path"]) for record in removed]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", required=True, type=Path, help="Noctalia settings.toml sidecar")
    parser.add_argument("--managed", required=True, type=Path, help="JSON tree of public Nix-managed paths (leaf values are ignored)")
    parser.add_argument("--backup-dir", required=True, type=Path, help="private directory for removed public keys")
    parser.add_argument("--require-no-noctalia", action="store_true", help="refuse writes while a same-UID noctalia executable is alive")
    args = parser.parse_args(argv)
    try:
        removed = reconcile(args.state, args.managed, args.backup_dir, args.require_no_noctalia)
    except (ReconcileError, OSError) as exc:
        print(f"reconcile-noctalia-overrides: {exc}", file=sys.stderr)
        return 1
    if removed:
        print(f"reconciled {len(removed)} managed Noctalia override(s)")
    else:
        print("Noctalia state unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
