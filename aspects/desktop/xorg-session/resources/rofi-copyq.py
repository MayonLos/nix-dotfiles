#!/usr/bin/env python3
"""Rofi mode for CopyQ history with serialized, atomic item verification."""

from __future__ import annotations

import base64
import hashlib
import os
import re
import subprocess
import sys


COPYQ = os.environ.get("XORG_COPYQ", "copyq")
TOKEN = re.compile(r"^(0|[1-9][0-9]{0,8}):([0-9a-f]{64})$")
MAX_ITEM_BYTES = 4 * 1024 * 1024
MAX_ITEMS = 40
TIMEOUT = 1.5

# CopyQ's scripting API serializes the whole MIME map (including images and
# other non-text formats). The index is an argument, never interpolated into
# this script. One eval snapshot supplies both the Rofi label and its digest.
SNAPSHOT_SCRIPT = rf'''var row = Number(arguments[1]);
if (row < 0 || Math.floor(row) !== row || row >= size()) fail();
var item = getItem(row);
var packed = pack(item);
if (packed.length > {MAX_ITEM_BYTES}) fail();
var text = item["text/plain"] || item["text/uri-list"] || "";
var mime = "";
for (var type in item) {{
    if (!item.hasOwnProperty(type)) continue;
    if (type.indexOf("image/") === 0) {{ mime = type; break; }}
    if (!mime) mime = type;
}}
print(row + "\t" + toBase64(packed) + "\t" + toBase64(text) + "\t" + toBase64(mime));'''

# input() receives base64 on stdin, avoiding environment/argv size limits.
# Verification and select() execute in one serialized CopyQ eval request, so
# an item cannot change between the final equality check and being selected.
SELECT_SCRIPT = r'''var row = Number(arguments[1]);
if (row < 0 || Math.floor(row) !== row || row >= size()) fail();
var expected = str(input());
if (toBase64(pack(getItem(row))) !== expected) fail();
select(row);
print("selected");'''


def call(
    args: list[str], *, timeout: float = TIMEOUT, input_data: bytes | None = None
) -> subprocess.CompletedProcess[bytes] | None:
    try:
        return subprocess.run(
            [COPYQ, *args],
            input=input_data,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def item_snapshot(index: int) -> tuple[bytes, bytes, str] | None:
    result = call(["eval", "--", SNAPSHOT_SCRIPT, str(index)])
    if result is None or result.returncode != 0:
        return None
    try:
        fields = result.stdout.rstrip(b"\r\n").split(b"\t")
        if len(fields) != 4 or int(fields[0]) != index:
            return None
        packed = base64.b64decode(fields[1], validate=True)
        text = base64.b64decode(fields[2], validate=True)
        mime = base64.b64decode(fields[3], validate=True).decode("ascii")
        if not packed or len(packed) > MAX_ITEM_BYTES:
            return None
        return packed, text, mime
    except (ValueError, UnicodeDecodeError):
        return None


def preview(data: bytes, mime: str = "") -> str:
    text = data.decode("utf-8", errors="replace")
    text = " ".join("".join(ch for ch in text if ch.isprintable()).split())
    if mime.startswith("image/"):
        label = f"🖼 {mime}"
        return f"{label} · {text[:80]}" if text else label
    if text:
        return text[:120] + ("…" if len(text) > 120 else "")
    if mime:
        return f"[{mime}]"
    return "（非文本内容）"


def emit_history() -> int:
    result = call(["size"])
    if result is None or result.returncode != 0:
        return 0
    try:
        size = min(MAX_ITEMS, max(0, int(result.stdout.strip())))
    except ValueError:
        return 0
    for index in range(size):
        snapshot = item_snapshot(index)
        if snapshot is None:
            continue
        packed, text, mime = snapshot
        token = f"{index}:{hashlib.sha256(packed).hexdigest()}"
        # Rofi script-mode metadata is an opaque token, not executable text.
        sys.stdout.write(f"{preview(text, mime)}\0info\x1f{token}\n")
    return 0


def select_token(value: str) -> int:
    match = TOKEN.fullmatch(value)
    if not match:
        return 2
    index = int(match.group(1))
    expected_digest = match.group(2)
    snapshot = item_snapshot(index)
    if snapshot is None:
        return 2
    packed, _text, _mime = snapshot
    if hashlib.sha256(packed).hexdigest() != expected_digest:
        return 2
    encoded = base64.b64encode(packed)
    result = call(
        ["eval", "--", SELECT_SCRIPT, str(index), "-"],
        timeout=2.5,
        input_data=encoded,
    )
    return 0 if result is not None and result.returncode == 0 else 2


def main() -> int:
    if os.environ.get("ROFI_RETV", "0") == "0":
        return emit_history()
    return select_token(os.environ.get("ROFI_INFO", ""))


if __name__ == "__main__":
    raise SystemExit(main())
