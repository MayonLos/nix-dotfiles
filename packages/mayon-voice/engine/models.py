#!/usr/bin/env python3
"""Explicit, hash-verified model fetcher; never called by the ASR worker."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path, PurePosixPath

MODELS = {
    "sensevoice": (
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/"
        "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2",
        "7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e",
        "model.int8.onnx",
    ),
    "paraformer": (
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/"
        "sherpa-onnx-paraformer-zh-small-2024-03-09.tar.bz2",
        "da92b3db5218c5be53aad53e57d1b6e63e7fc98a0e054fbdd6dbe18e9c6b1450",
        "model.int8.onnx",
    ),
}


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def unpack_verified(archive: Path, destination: Path, expected: str, required_model: str) -> None:
    destination = destination.expanduser()
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if destination.exists() or destination.is_symlink():
        raise RuntimeError(f"refusing to overwrite existing model path: {destination}")
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix=".mayon-voice-model-") as scratch:
        scratch_path = Path(scratch)
        actual = digest(archive)
        if actual != expected:
            raise RuntimeError(f"SHA-256 mismatch: got {actual}")
        staging = scratch_path / "unpacked"
        staging.mkdir(mode=0o700)
        with tarfile.open(archive, "r:bz2") as tar:
            for member in tar.getmembers():
                relative = PurePosixPath(member.name)
                if relative.is_absolute() or ".." in relative.parts or not (member.isfile() or member.isdir()):
                    raise RuntimeError(f"unsafe archive member: {member.name}")
                parts = relative.parts[1:]
                if not parts:
                    continue
                member.name = str(PurePosixPath(*parts))
                tar.extract(member, staging, filter="data")
        models = list(staging.rglob(required_model))
        tokens = list(staging.rglob("tokens.txt"))
        if len(models) != 1 or len(tokens) != 1:
            raise RuntimeError(f"archive does not have the expected {required_model} and tokens.txt")
        root = models[0].parent
        if tokens[0].parent != root:
            raise RuntimeError("model and tokens.txt are not in one directory")
        for item in [root, *root.rglob("*")]:
            os.chmod(item, 0o700 if item.is_dir() else 0o600)
        root.rename(destination)


def fetch(engine: str, destination: Path) -> None:
    url, expected, required_model = MODELS[engine]
    destination = destination.expanduser()
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if destination.exists() or destination.is_symlink():
        raise RuntimeError(f"refusing to overwrite existing model path: {destination}")
    # Download and staging share the destination filesystem. The final rename
    # is atomic and cannot fail with EXDEV when /tmp is a separate tmpfs.
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix=".mayon-voice-download-") as scratch:
        archive = Path(scratch) / "model.tar.bz2"
        request = urllib.request.Request(url, headers={"User-Agent": "mayon-voice-model-fetch/1"})
        with urllib.request.urlopen(request, timeout=60) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        unpack_verified(archive, destination, expected, required_model)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", choices=tuple(MODELS), required=True)
    parser.add_argument("--model-dir", required=True)
    args = parser.parse_args()
    try:
        fetch(args.engine, Path(args.model_dir))
        print(f"Installed {args.engine} under {Path(args.model_dir).expanduser()}")
        return 0
    except Exception as exc:
        print(f"model fetch failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
