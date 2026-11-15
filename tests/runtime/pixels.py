"""PNG inspection helpers built on ImageMagick's raw RGBA stream.

The suite deliberately avoids Python imaging dependencies. ImageMagick is in
the live user profile (and is also built by the repository's checks), and it
decodes PNG to a flat ``rgba:-`` buffer that is trivial to scan.

Every helper takes an :class:`Image` and works in *physical device pixels*, the
same coordinate space as ``grim`` output.
"""

from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

from .support import TestFailure, which

MAGICK_CANDIDATES = ("magick", "convert")


def magick_binary() -> str:
    for name in MAGICK_CANDIDATES:
        found = which(name)
        if found:
            return found
    raise TestFailure("找不到 ImageMagick（magick/convert），无法分析截图像素")


@dataclass
class Image:
    width: int
    height: int
    data: bytes

    def pixel(self, x: int, y: int) -> tuple[int, int, int, int]:
        offset = (y * self.width + x) * 4
        return (
            self.data[offset],
            self.data[offset + 1],
            self.data[offset + 2],
            self.data[offset + 3],
        )

    def rgb(self, x: int, y: int) -> tuple[int, int, int]:
        return self.pixel(x, y)[:3]


def load(path: Path) -> Image:
    magick = magick_binary()
    result = subprocess.run(
        [magick, str(path), "-depth", "8", "rgba:-"],
        capture_output=True,
        timeout=120,
    )
    if result.returncode != 0:
        raise TestFailure(f"ImageMagick 解码失败: {result.stderr.decode('utf-8', 'replace')[:300]}")
    identity = subprocess.run(
        [magick, "identify", "-format", "%w %h", str(path)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if identity.returncode != 0:
        raise TestFailure(f"ImageMagick identify 失败: {identity.stderr[:300]}")
    width_text, height_text = identity.stdout.split()
    width, height = int(width_text), int(height_text)
    data = result.stdout
    expected = width * height * 4
    if len(data) != expected:
        raise TestFailure(
            f"ImageMagick 输出 {len(data)} 字节, 期望 {expected} ({width}x{height}) — 可能含 alpha 附加通道"
        )
    return Image(width, height, data)


def image_size(path: Path) -> tuple[int, int]:
    magick = magick_binary()
    identity = subprocess.run(
        [magick, "identify", "-format", "%w %h", str(path)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if identity.returncode != 0:
        raise TestFailure(f"ImageMagick identify 失败: {identity.stderr[:300]}")
    parts = identity.stdout.split()
    return int(parts[0]), int(parts[1])


def near(color: tuple[int, int, int], target: tuple[int, int, int], tolerance: int = 6) -> bool:
    return (
        abs(color[0] - target[0]) <= tolerance
        and abs(color[1] - target[1]) <= tolerance
        and abs(color[2] - target[2]) <= tolerance
    )


def count_near(
    image: Image,
    target: tuple[int, int, int],
    *,
    tolerance: int = 6,
    x0: int = 0,
    y0: int = 0,
    x1: int | None = None,
    y1: int | None = None,
    step: int = 1,
) -> int:
    x1 = image.width if x1 is None else min(x1, image.width)
    y1 = image.height if y1 is None else min(y1, image.height)
    count = 0
    data = image.data
    for y in range(max(0, y0), y1, step):
        row = y * image.width
        for x in range(max(0, x0), x1, step):
            offset = (row + x) * 4
            if (
                abs(data[offset] - target[0]) <= tolerance
                and abs(data[offset + 1] - target[1]) <= tolerance
                and abs(data[offset + 2] - target[2]) <= tolerance
            ):
                count += 1
    return count


def bbox_near(
    image: Image,
    target: tuple[int, int, int],
    *,
    tolerance: int = 6,
    x0: int = 0,
    y0: int = 0,
    x1: int | None = None,
    y1: int | None = None,
) -> tuple[int, int, int, int] | None:
    x1 = image.width if x1 is None else min(x1, image.width)
    y1 = image.height if y1 is None else min(y1, image.height)
    min_x = min_y = None
    max_x = max_y = -1
    data = image.data
    for y in range(max(0, y0), y1):
        row = y * image.width
        for x in range(max(0, x0), x1):
            offset = (row + x) * 4
            if (
                abs(data[offset] - target[0]) <= tolerance
                and abs(data[offset + 1] - target[1]) <= tolerance
                and abs(data[offset + 2] - target[2]) <= tolerance
            ):
                min_x = x if min_x is None else min(min_x, x)
                max_x = max(max_x, x)
                min_y = y if min_y is None else min(min_y, y)
                max_y = max(max_y, y)
    if min_x is None or min_y is None:
        return None
    return min_x, min_y, max_x, max_y


def row_counts(
    image: Image,
    target: tuple[int, int, int],
    *,
    tolerance: int = 6,
    x0: int = 0,
    x1: int | None = None,
    y0: int = 0,
    y1: int | None = None,
) -> dict[int, int]:
    x1 = image.width if x1 is None else min(x1, image.width)
    y1 = image.height if y1 is None else min(y1, image.height)
    data = image.data
    counts: dict[int, int] = {}
    for y in range(max(0, y0), y1):
        row = y * image.width
        count = 0
        for x in range(max(0, x0), x1):
            offset = (row + x) * 4
            if (
                abs(data[offset] - target[0]) <= tolerance
                and abs(data[offset + 1] - target[1]) <= tolerance
                and abs(data[offset + 2] - target[2]) <= tolerance
            ):
                count += 1
        counts[y] = count
    return counts


def col_counts(
    image: Image,
    target: tuple[int, int, int],
    *,
    tolerance: int = 6,
    x0: int = 0,
    x1: int | None = None,
    y0: int = 0,
    y1: int | None = None,
) -> dict[int, int]:
    x1 = image.width if x1 is None else min(x1, image.width)
    y1 = image.height if y1 is None else min(y1, image.height)
    data = image.data
    counts: dict[int, int] = {}
    for x in range(max(0, x0), x1):
        count = 0
        for y in range(max(0, y0), y1):
            offset = (y * image.width + x) * 4
            if (
                abs(data[offset] - target[0]) <= tolerance
                and abs(data[offset + 1] - target[1]) <= tolerance
                and abs(data[offset + 2] - target[2]) <= tolerance
            ):
                count += 1
        counts[x] = count
    return counts


def contiguous_bands(
    counts: dict[int, int], *, minimum: int, dimensions: tuple[int, int]
) -> list[tuple[int, int]]:
    """Return runs of consecutive keys whose count is >= minimum."""
    start, stop = dimensions
    bands: list[tuple[int, int]] = []
    current: list[int] = []
    ordered = sorted(counts)
    for index, key in enumerate(ordered):
        value = counts[key]
        if value >= minimum:
            if not current or key == current[-1] + 1:
                current.append(key)
            else:
                if len(current) >= 2:
                    bands.append((current[0], current[-1]))
                current = [key]
        else:
            if len(current) >= 2:
                bands.append((current[0], current[-1]))
            current = []
    if len(current) >= 2:
        bands.append((current[0], current[-1]))
    return bands


def mode_fraction(
    image: Image, y: int, *, x0: int = 0, x1: int | None = None, step: int = 2, quantize: int = 4
) -> float:
    """Fraction of the row covered by its most common quantized color."""
    x1 = image.width if x1 is None else min(x1, image.width)
    buckets: dict[tuple[int, int, int], int] = {}
    total = 0
    for x in range(x0, x1, step):
        r, g, b, _ = image.pixel(x, y)
        key = (r // quantize, g // quantize, b // quantize)
        buckets[key] = buckets.get(key, 0) + 1
        total += 1
    if total == 0:
        return 0.0
    return max(buckets.values()) / total


def luminance(pixel: tuple[int, int, int, int]) -> float:
    return 0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]


def mean_luminance(
    image: Image, *, x0: int, y0: int, x1: int, y1: int, step: int = 4
) -> float:
    total = 0.0
    count = 0
    for y in range(max(0, y0), min(y1, image.height), step):
        for x in range(max(0, x0), min(x1, image.width), step):
            total += luminance(image.pixel(x, y))
            count += 1
    return total / count if count else 0.0


def png_magic(path: Path) -> str:
    with path.open("rb") as handle:
        return handle.read(8).hex()


def sha256(path: Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_header_size(path: Path) -> tuple[int, int] | None:
    """Read width/height straight from the PNG IHDR chunk.

    Works even when a clipboard or pipe delivered a truncated tail (the header
    is the first 24 bytes), which is exactly the failure mode the mark-shot copy
    check has to observe without crashing ImageMagick.
    """
    try:
        with path.open("rb") as handle:
            header = handle.read(33)
    except OSError:
        return None
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    if header[12:16] != b"IHDR":
        return None
    width = int.from_bytes(header[16:20], "big")
    height = int.from_bytes(header[20:24], "big")
    return width, height


def mean_abs_diff(
    before: "Image",
    after: "Image",
    *,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    step: int = 4,
) -> float:
    """Mean absolute per-channel difference (0..255) between two frames."""
    x1 = min(x1, before.width, after.width)
    y1 = min(y1, before.height, after.height)
    total = 0
    count = 0
    for y in range(max(0, y0), y1, step):
        for x in range(max(0, x0), x1, step):
            a = before.pixel(x, y)
            b = after.pixel(x, y)
            total += abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
            count += 1
    return total / (count * 3) if count else 0.0
