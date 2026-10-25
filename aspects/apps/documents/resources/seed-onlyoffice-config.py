#!/usr/bin/env python3
"""Seed ONLYOFFICE's app-owned config without replacing existing user state."""

import os
import sys
from pathlib import Path


DEFAULT_CONFIG = "UITheme=theme-dark\n"


def seed(target: Path) -> None:
    # Existing file/parent links remain app/user-owned; never seed through them.
    absolute = Path(os.path.abspath(target))
    if any(parent.is_symlink() for parent in absolute.parents):
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(
            target,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o644,
        )
    except FileExistsError:
        return

    with os.fdopen(descriptor, "w", encoding="utf-8") as config:
        config.write(DEFAULT_CONFIG)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: seed-onlyoffice-config.py CONFIG_PATH")
    seed(Path(sys.argv[1]))
