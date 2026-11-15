#!/usr/bin/env python3
"""Pixel regression for mangobar's StatusNotifierItem DBusMenu popup.

The script runs the real mangobar package and the real generated stylesheet
inside a private headless sway (2560x1600 at scale 1.5) on a private D-Bus
session. Two independent StatusNotifierItem + DBusMenu services stand in for
background programs (fcitx, a media player, ...); each owns its own bus name
and menu tree. A virtual pointer injects real pointer moves and button events,
so the only thing under test is mangobar's own popup drawing, not a simulated
image.

Two modes:
  --mode assert   fail on any palette/geometry mismatch (used by the Nix check)
  --mode measure  only record metrics (used to compare the old stylesheet)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image

WIDTH = 2560
HEIGHT = 1600
SCALE = 1.5
WALLPAPER = (16, 20, 24)  # "output * bg #101418 solid_color"
BAR_H = 30  # services.mangobar.settings.height
MENU_PAD_V = 4  # mangobar.c MENU_PAD_V
ROW_COUNT = 4  # top-level rows in both fixture menus


class Failed(RuntimeError):
    pass


def rgb_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))


def parse_hex(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def median_color(image: Image.Image, box: tuple[int, int, int, int]) -> tuple[int, int, int]:
    crop = image.crop(box).convert("RGB")
    channels = [sorted(crop.getchannel(name).tobytes()) for name in ("R", "G", "B")]
    middle = len(channels[0]) // 2
    return tuple(channel[middle] for channel in channels)  # type: ignore[return-value]


def clamp_box(box: tuple[int, int, int, int], width: int, height: int) -> tuple[int, int, int, int]:
    # grim can leave the last physical row/column uninitialised on the
    # headless backend (the capture is one pixel shorter than the mode), so
    # keep every region two pixels away from the edge.
    x0, y0, x1, y1 = box
    return (
        max(0, min(x0, width - 2)),
        max(0, min(y0, height - 2)),
        max(0, min(x1, width - 2)),
        max(0, min(y1, height - 2)),
    )


def bbox_of(image: Image.Image, box: tuple[int, int, int, int], predicate) -> tuple[int, int, int, int] | None:
    x0, y0, x1, y1 = clamp_box(box, image.width, image.height)
    rgb = image.load()
    min_x = min_y = 1 << 30
    max_x = max_y = -1
    for y in range(y0, y1):
        for x in range(x0, x1):
            if predicate(rgb[x, y]):
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
    if max_x < 0:
        return None
    return (min_x, min_y, max_x + 1, max_y + 1)


def find_color_bbox(
    image: Image.Image,
    color: tuple[int, int, int],
    tolerance: int,
    region: tuple[int, int, int, int],
) -> tuple[int, int, int, int] | None:
    return bbox_of(image, region, lambda pixel: rgb_distance(pixel, color) <= tolerance)


def ink_pixels(
    image: Image.Image,
    box: tuple[int, int, int, int],
    background: tuple[int, int, int],
    threshold: int,
) -> list[tuple[int, int, tuple[int, int, int]]]:
    x0, y0, x1, y1 = clamp_box(box, image.width, image.height)
    rgb = image.load()
    pixels = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            pixel = rgb[x, y]
            if rgb_distance(pixel, background) > threshold:
                pixels.append((x, y, pixel))
    return pixels


def min_distance(pixels: list[tuple[int, int, tuple[int, int, int]]], target: tuple[int, int, int]) -> int:
    return min((rgb_distance(pixel, target) for _, _, pixel in pixels), default=999)


def count_near(pixels: list[tuple[int, int, tuple[int, int, int]]], target: tuple[int, int, int], tolerance: int) -> int:
    return sum(1 for _, _, pixel in pixels if rgb_distance(pixel, target) <= tolerance)


def run(argv: list[str], *, env: dict[str, str], timeout: float = 20.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)


def terminate(proc: subprocess.Popen | None) -> None:
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=3)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mangobar", required=True)
    parser.add_argument("--sway", required=True)
    parser.add_argument("--grim", required=True)
    parser.add_argument("--python", required=True)
    parser.add_argument("--vptr", required=True)
    parser.add_argument("--provider", required=True, type=Path)
    parser.add_argument("--config-dir", required=True, type=Path)
    parser.add_argument("--palette", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--mode", choices=["assert", "measure"], default="assert")
    parser.add_argument("--startup-timeout", type=float, default=30.0)
    parser.add_argument("--settle", type=float, default=0.5)
    return parser.parse_args()


def wait_for_socket(
    runtime: Path, prefix: str, before: set[str], proc: subprocess.Popen, timeout: float
) -> Path:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise Failed(f"compositor exited early: {proc.args}")
        candidates = [
            path
            for path in runtime.iterdir()
            if path.name.startswith(prefix)
            and path.name not in before
            and stat.S_ISSOCK(path.stat().st_mode)
        ]
        if candidates:
            return max(candidates, key=lambda path: path.stat().st_mtime_ns)
        time.sleep(0.1)
    raise Failed(f"no {prefix} socket after {timeout}s")


def write_sway_config(path: Path) -> None:
    path.write_text(
        "\n".join(
            [
                "output HEADLESS-1 mode 2560x1600 scale 1.5",
                "output * bg #101418 solid_color",
                "default_border none",
                "default_floating_border none",
                "focus_follows_mouse no",
                "mouse_warping none",
                "xwayland disable",
                "seat seat0 hide_cursor 1000000",
                "",
            ]
        ),
        encoding="utf-8",
    )


def wait_name_owner(name: str, timeout: float) -> bool:
    from gi.repository import Gio, GLib

    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        reply = connection.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            GLib.Variant("(s)", (name,)),
            None,
            Gio.DBusCallFlags.NONE,
            1000,
            None,
        )
        if reply.unpack()[0]:
            return True
        time.sleep(0.1)
    return False


class Session:
    """One private sway + mangobar + tray-service run."""

    def __init__(self, args: argparse.Namespace, root: Path) -> None:
        self.args = args
        self.root = root
        self.runtime = root / "rt"
        self.home = root / "home"
        self.config = root / "config"
        self.cache = root / "cache"
        self.state = root / "state"
        self.data = root / "data"
        for directory in (self.runtime, self.home, self.config, self.cache, self.state, self.data):
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.runtime.chmod(0o700)
        self.env: dict[str, str] = {}
        self.sway_proc: subprocess.Popen | None = None
        self.mangobar_proc: subprocess.Popen | None = None
        self.vptr_proc: subprocess.Popen | None = None
        self.provider_procs: list[subprocess.Popen] = []
        self.log_handles: list[object] = []
        self.wayland_name = ""

    def start(self) -> None:
        args = self.args
        mangobar_config = self.config / "mangobar"
        mangobar_config.mkdir(mode=0o700, parents=True, exist_ok=True)
        for name in ("config.jsonc", "style.css"):
            (mangobar_config / name).write_bytes((args.config_dir / name).read_bytes())
        sway_conf = self.root / "sway.conf"
        write_sway_config(sway_conf)
        logs = args.out / "logs"
        logs.mkdir(mode=0o700, parents=True, exist_ok=True)

        env = {
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_CACHE_HOME": str(self.cache),
            "XDG_STATE_HOME": str(self.state),
            "XDG_DATA_HOME": str(self.data),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "XDG_SESSION_TYPE": "wayland",
            "XDG_CURRENT_DESKTOP": "sway",
            "XDG_SESSION_DESKTOP": "sway",
            "WLR_BACKENDS": "headless",
            "WLR_RENDERER": "pixman",
            "WLR_LIBINPUT_NO_DEVICES": "1",
            "LIBGL_ALWAYS_SOFTWARE": "1",
            "DBUS_SYSTEM_BUS_ADDRESS": f"unix:path={self.runtime / 'unreachable-system-bus'}",
            "PATH": os.pathsep.join(
                [
                    str(Path(args.python).resolve().parent),
                    str(Path(args.sway).resolve().parent),
                    str(Path(args.grim).resolve().parent),
                    os.environ.get("PATH", ""),
                ]
            ),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "MANGOBAR_LOG_IPC": "1",
        }
        if os.environ.get("FONTCONFIG_FILE"):
            env["FONTCONFIG_FILE"] = os.environ["FONTCONFIG_FILE"]
        session_bus = os.environ.get("DBUS_SESSION_BUS_ADDRESS")
        if not session_bus:
            raise Failed("run this under dbus-run-session; no private session bus")
        env["DBUS_SESSION_BUS_ADDRESS"] = session_bus
        self.env = env

        self.sway_log = (logs / "sway.log").open("w", encoding="utf-8")
        self.mangobar_log = (logs / "mangobar.log").open("w", encoding="utf-8")
        self.log_handles = [self.sway_log, self.mangobar_log]

        before = {path.name for path in self.runtime.iterdir()}
        sway_env = {key: value for key, value in env.items() if key != "DBUS_SESSION_BUS_ADDRESS"}
        self.sway_proc = subprocess.Popen(
            [args.sway, "-c", str(sway_conf)],
            env=sway_env,
            stdout=self.sway_log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        wayland_socket = wait_for_socket(self.runtime, "wayland-", before, self.sway_proc, args.startup_timeout)
        sway_ipc = wait_for_socket(self.runtime, "sway-ipc.", before, self.sway_proc, 10)
        env["WAYLAND_DISPLAY"] = wayland_socket.name
        env["SWAYSOCK"] = str(sway_ipc)
        self.wayland_name = wayland_socket.name

        # The headless backend has no pointers. Creating a virtual pointer
        # makes the seat advertise WL_SEAT_CAPABILITY_POINTER, which is what
        # mangobar needs before it binds wl_pointer and accepts tray clicks.
        vptr_env = {key: value for key, value in env.items() if key != "SWAYSOCK"}
        self.vptr_proc = subprocess.Popen(
            [args.vptr, str(round(WIDTH / SCALE)), str(round(HEIGHT / SCALE))],
            env=vptr_env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
        assert self.vptr_proc.stdout is not None
        ready = self.vptr_proc.stdout.readline().strip()
        if ready != "READY":
            raise Failed(f"virtual pointer failed: {ready}")
        time.sleep(0.3)

        self.mangobar_proc = subprocess.Popen(
            [args.mangobar],
            env=env,
            stdout=self.mangobar_log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        if not wait_name_owner("org.kde.StatusNotifierWatcher", args.startup_timeout):
            raise Failed("mangobar never owned org.kde.StatusNotifierWatcher")
        time.sleep(args.settle)

        for variant, service in (("one", "org.mayon.BackendOne"), ("two", "org.mayon.BackendTwo")):
            log = (logs / f"provider-{variant}.log").open("w", encoding="utf-8")
            self.log_handles.append(log)
            self.provider_procs.append(
                subprocess.Popen(
                    [args.python, str(args.provider), "--service", service, "--variant", variant],
                    env=env,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
            )

    def stop(self) -> None:
        for provider in self.provider_procs:
            terminate(provider)
        terminate(self.mangobar_proc)
        terminate(self.vptr_proc)
        terminate(self.sway_proc)
        for handle in self.log_handles:
            handle.close()

    # --- input -----------------------------------------------------------
    def pointer(self, x: float, y: float) -> None:
        assert self.vptr_proc is not None and self.vptr_proc.stdin is not None
        self.vptr_proc.stdin.write(f"move {round(x)} {round(y)}\n")
        self.vptr_proc.stdin.flush()

    def button(self, code: int, pressed: bool) -> None:
        assert self.vptr_proc is not None and self.vptr_proc.stdin is not None
        self.vptr_proc.stdin.write(f"button {code} {1 if pressed else 0}\n")
        self.vptr_proc.stdin.flush()

    def right_click(self, x: float, y: float) -> None:
        self.pointer(x, y)
        time.sleep(0.3)
        self.button(0x111, True)  # BTN_RIGHT
        time.sleep(0.1)
        self.button(0x111, False)

    # --- capture ---------------------------------------------------------
    def capture(self, name: str) -> Image.Image:
        path = self.args.out / "screens" / f"{name}.png"
        result = run([self.args.grim, "-o", "HEADLESS-1", str(path)], env=self.env, timeout=20)
        if result.returncode:
            raise Failed(f"grim failed: {result.stderr.strip()}")
        with Image.open(path) as image:
            return image.convert("RGB")

    def layouts(self) -> list[tuple[int, int, int, int, int]]:
        text = (self.args.out / "logs" / "mangobar.log").read_text(encoding="utf-8", errors="replace")
        matches = re.findall(
            r"\[menu\] layout bar_h=(-?\d+) mt=(-?\d+) ml=(-?\d+) w=(\d+) h=(\d+)", text
        )
        return [tuple(int(value) for value in match) for match in matches]

    def wait_layout(self, count: int, timeout: float = 15.0) -> tuple[int, int, int, int, int]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            layouts = self.layouts()
            if len(layouts) >= count:
                return layouts[count - 1]
            time.sleep(0.1)
        raise Failed(f"mangobar never laid out menu #{count}; see logs/mangobar.log")

    def wait_icon(self, color: tuple[int, int, int], timeout: float) -> tuple[int, int, int, int]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            image = self.capture("icon-probe")
            bbox = find_color_bbox(image, color, 24, (0, 0, image.width, round(BAR_H * SCALE) + 4))
            if bbox:
                return bbox
            time.sleep(0.2)
        raise Failed(f"tray icon {color} never appeared in the bar")


def expected_rect(
    layout: tuple[int, int, int, int, int], image: Image.Image
) -> tuple[int, int, int, int]:
    bar_h, mt, ml, mw, mh = layout
    # The bar reserves its height as a layer-shell exclusive zone, so overlay
    # surfaces anchored to the output top start below it; the popup's own top
    # margin is mt below that edge.
    return (
        round(ml * SCALE),
        round((bar_h + mt) * SCALE),
        round((ml + mw) * SCALE),
        round((bar_h + mt + mh) * SCALE),
    )


def detect_rect(image: Image.Image, layout: tuple[int, int, int, int, int]) -> tuple[int, int, int, int] | None:
    bar_h, mt, ml, mw, mh = layout
    region = (
        max(0, round((ml - 40) * SCALE)),
        round(bar_h * SCALE) + 1,
        min(image.width, round((ml + mw + 40) * SCALE)),
        min(image.height, round((bar_h + mt + mh + 30) * SCALE)),
    )
    return bbox_of(image, region, lambda pixel: rgb_distance(pixel, WALLPAPER) > 10)


def analyze_menu(
    image: Image.Image,
    layout: tuple[int, int, int, int, int],
    palette: dict[str, tuple[int, int, int]],
    *,
    include_text: bool = True,
) -> dict:
    rect = expected_rect(layout, image)
    detected = detect_rect(image, layout)
    x0, y0, x1, y1 = rect
    result: dict = {
        "layout": {
            "bar_h": layout[0],
            "mt": layout[1],
            "ml": layout[2],
            "w": layout[3],
            "h": layout[4],
        },
        "expected_rect_px": list(rect),
        "detected_rect_px": list(detected) if detected else None,
        "screenshot_px": list(image.size),
    }
    if detected is None:
        return result

    result["rect_error_px"] = {
        name: rect[i] - detected[i] for i, name in enumerate(("x0", "y0", "x1", "y1"))
    }
    # Background: the menu's left padding strip never contains text.
    inner = (x0 + 3, y0 + 8, x0 + 12, y1 - 8)
    result["bg_median"] = list(median_color(image, inner))
    # Border: brightest (furthest from background) pixel in the top edge band.
    bg = tuple(result["bg_median"])
    border_pixels = []
    for x in range(x0 + 30, x1 - 30, 2):
        candidates = [
            image.getpixel((x, y))
            for y in range(max(0, y0 - 2), min(image.height, y0 + 4))
        ]
        border_pixels.append(max(candidates, key=lambda pixel: rgb_distance(pixel, bg)))
    border_pixels.sort(key=lambda pixel: rgb_distance(pixel, bg))
    result["border_median"] = list(border_pixels[len(border_pixels) // 2])
    # Rounded corner: sample the corner cut and the left-edge insets per row.
    result["corner_pixels"] = [
        list(image.getpixel((x0 + dx, y0 + dy))) for dx, dy in ((1, 1), (2, 2), (3, 3))
    ]
    insets = []
    for dy in range(0, 11):
        y = y0 + dy
        if y >= image.height - 2:
            break
        x = x0
        while x < x1 and rgb_distance(image.getpixel((x, y)), WALLPAPER) <= 10:
            x += 1
        insets.append({"dy_px": dy, "inset_px": x - x0})
    result["corner_insets"] = insets

    def predicted_inset(radius_logical: float, dy: int) -> float:
        # Each physical row covers 1/SCALE logical pixels; the rounded rect's
        # outer edge cuts in by r - sqrt(r^2 - (r - y)^2) at that height.
        y_center = (dy + 0.5) / SCALE
        if y_center >= radius_logical:
            return 0.0
        inset_logical = radius_logical - (
            radius_logical**2 - (radius_logical - y_center) ** 2
        ) ** 0.5
        return inset_logical * SCALE

    best_radius = None
    best_error = None
    for radius in (8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0, 11.5, 12.0, 12.5, 13.0, 13.5, 14.0):
        error = sum(abs(predicted_inset(radius, item["dy_px"]) - item["inset_px"]) for item in insets)
        for item in insets:
            if radius == 12.0:
                item["expected_inset_px"] = round(predicted_inset(radius, item["dy_px"]), 1)
        if best_error is None or error < best_error:
            best_radius, best_error = radius, error
    result["fitted_radius_logical"] = best_radius
    result["fitted_radius_error_px"] = round(best_error, 2) if best_error is not None else None

    if include_text:
        item_h = (layout[4] - 2 * MENU_PAD_V) / ROW_COUNT
        origin_y = (layout[0] + layout[1]) * SCALE
        text_box = (x0 + round(10 * SCALE), y0, x1 - round(10 * SCALE), y1)
        background = bg
        rows = []
        for index in range(ROW_COUNT):
            row_top = round(origin_y + (MENU_PAD_V + index * item_h) * SCALE)
            row_bottom = round(origin_y + (MENU_PAD_V + (index + 1) * item_h) * SCALE)
            row_box = (text_box[0], max(text_box[1], row_top), text_box[2], min(text_box[3], row_bottom))
            pixels = ink_pixels(image, row_box, background, 40)
            rows.append(
                {
                    "row": index,
                    "ink_bbox_px": (
                        [
                            min(p[0] for p in pixels),
                            min(p[1] for p in pixels),
                            max(p[0] for p in pixels) + 1,
                            max(p[1] for p in pixels) + 1,
                        ]
                        if pixels
                        else None
                    ),
                    "ink_count": len(pixels),
                    "core_count": count_near(pixels, palette["brightFg"], 14)
                    + count_near(pixels, palette["muted"], 14),
                    "min_distance_brightFg": min_distance(pixels, palette["brightFg"]),
                    "min_distance_muted": min_distance(pixels, palette["muted"]),
                    "count_near_brightFg_14": count_near(pixels, palette["brightFg"], 14),
                    "count_near_muted_14": count_near(pixels, palette["muted"], 14),
                }
            )
        result["rows"] = rows
    return result


def analyze_hover(
    image: Image.Image,
    layout: tuple[int, int, int, int, int],
    palette: dict[str, tuple[int, int, int]],
    row: int,
) -> dict:
    rect = expected_rect(layout, image)
    x0, y0, x1, y1 = rect
    bar_h, mt, ml, mw, mh = layout
    item_h = (mh - 2 * MENU_PAD_V) / ROW_COUNT
    origin_y = (bar_h + mt) * SCALE
    row_top = round(origin_y + (MENU_PAD_V + row * item_h) * SCALE)
    row_bottom = round(origin_y + (MENU_PAD_V + (row + 1) * item_h) * SCALE)
    hover_box = (x1 - round(12 * SCALE), row_top + 2, x1 - round(4 * SCALE), row_bottom - 2)
    result = {
        "row": row,
        "hover_bg_median": list(median_color(image, hover_box)),
        "expected_rect_px": list(rect),
    }
    background = tuple(result["hover_bg_median"])
    pixels = ink_pixels(
        image,
        (x0 + round(10 * SCALE), row_top, x1 - round(10 * SCALE), row_bottom),
        background,
        40,
    )
    result["ink_count"] = len(pixels)
    result["min_distance_brightFg"] = min_distance(pixels, palette["brightFg"])
    result["min_distance_muted"] = min_distance(pixels, palette["muted"])
    result["count_near_brightFg_14"] = count_near(pixels, palette["brightFg"], 14)
    result["count_near_muted_14"] = count_near(pixels, palette["muted"], 14)
    return result


def analyze_submenu(
    image: Image.Image, layout: tuple[int, int, int, int, int], palette: dict[str, tuple[int, int, int]]
) -> dict:
    rect = expected_rect(layout, image)
    x0, y0, x1, y1 = rect
    bar_h = layout[0]
    region = (x1 + 1, round(bar_h * SCALE) + 1, x1 + round(400 * SCALE), y1 + round(200 * SCALE))
    detected = bbox_of(image, region, lambda pixel: rgb_distance(pixel, WALLPAPER) > 10)
    result: dict = {"detected_rect_px": list(detected) if detected else None}
    if detected is None:
        return result
    sx0, sy0, sx1, sy1 = detected
    result["bg_median"] = list(median_color(image, (sx0 + 3, sy0 + 8, sx0 + 12, sy1 - 8)))
    border_pixels = [
        max(
            [image.getpixel((x, y)) for y in range(max(0, sy0 - 2), min(image.height, sy0 + 4))],
            key=lambda pixel: rgb_distance(pixel, tuple(result["bg_median"])),
        )
        for x in range(sx0 + 10, sx1 - 10, 2)
    ]
    border_pixels.sort(key=lambda pixel: rgb_distance(pixel, tuple(result["bg_median"])))
    result["border_median"] = list(border_pixels[len(border_pixels) // 2])
    pixels = ink_pixels(image, (sx0 + round(10 * SCALE), sy0, sx1 - round(10 * SCALE), sy1), tuple(result["bg_median"]), 40)
    result["ink_count"] = len(pixels)
    result["min_distance_brightFg"] = min_distance(pixels, palette["brightFg"])
    result["min_distance_muted"] = min_distance(pixels, palette["muted"])
    return result


def main() -> int:
    args = parse_args()
    palette_raw = json.loads(args.palette.read_text(encoding="utf-8"))
    palette = {name: parse_hex(value) for name, value in palette_raw.items()}
    root = Path(tempfile.mkdtemp(prefix="mangobar-tray-", dir=os.environ.get("TMPDIR")))
    (args.out / "screens").mkdir(mode=0o755, parents=True, exist_ok=True)
    (args.out / "logs").mkdir(mode=0o755, parents=True, exist_ok=True)
    session = Session(args, root)
    metrics: dict = {
        "mode": args.mode,
        "wayland_display": "",
        "palette": {name: list(value) for name, value in palette.items()},
    }
    errors: list[str] = []
    try:
        session.start()
        metrics["wayland_display"] = session.wayland_name

        # Tray icons are solid magenta / cyan pixmaps, so the click target is
        # found from the rendered bar instead of guessing module widths.
        icon_one = session.wait_icon((255, 0, 255), args.startup_timeout)
        icon_two = session.wait_icon((0, 255, 255), 10)
        metrics["icon_one_bbox_px"] = list(icon_one)
        metrics["icon_two_bbox_px"] = list(icon_two)
        click_one = ((icon_one[0] + icon_one[2]) / 2 / SCALE, (icon_one[1] + icon_one[3]) / 2 / SCALE)
        click_two = ((icon_two[0] + icon_two[2]) / 2 / SCALE, (icon_two[1] + icon_two[3]) / 2 / SCALE)

        # --- menu A ------------------------------------------------------
        session.right_click(*click_one)
        layout_one = session.wait_layout(1)
        time.sleep(args.settle)
        session.pointer(200, 900)  # grab layer: keeps the menu open, no row hover
        time.sleep(args.settle)
        menu_one = session.capture("menu-one-open")
        metrics["menu-one"] = analyze_menu(menu_one, layout_one, palette)

        current = {"layout": layout_one}

        def hover_row(row: int, name: str) -> dict:
            bar_h, mt, ml, mw, mh = current["layout"]
            item_h = (mh - 2 * MENU_PAD_V) / ROW_COUNT
            x = (ml + mw / 2) * SCALE
            y = ((bar_h + mt) * SCALE) + (MENU_PAD_V + row * item_h + item_h / 2) * SCALE
            session.pointer(x / SCALE, y / SCALE)
            time.sleep(args.settle)
            image = session.capture(name)
            return analyze_hover(image, current["layout"], palette, row)

        metrics["menu-one-hover-row0"] = hover_row(0, "menu-one-hover-row0")
        session.pointer(200, 900)
        time.sleep(args.settle)
        metrics["menu-one-hover-disabled"] = hover_row(2, "menu-one-hover-disabled")
        session.pointer(200, 900)
        time.sleep(args.settle)
        # Row 1 has a submenu; hovering it opens the side popup after 300 ms.
        bar_h, mt, ml, mw, mh = layout_one
        item_h = (mh - 2 * MENU_PAD_V) / ROW_COUNT
        session.pointer(
            (ml + mw / 2),
            (bar_h + mt) + MENU_PAD_V + 1.5 * item_h,
        )
        time.sleep(0.9)
        submenu_image = session.capture("menu-one-submenu")
        metrics["menu-one-submenu"] = analyze_submenu(submenu_image, layout_one, palette)
        session.pointer(200, 900)
        time.sleep(args.settle)

        # --- menu B (independent program, same stylesheet) ---------------
        session.right_click(*click_two)
        layout_two = session.wait_layout(2)
        time.sleep(args.settle)
        session.pointer(200, 900)
        time.sleep(args.settle)
        menu_two = session.capture("menu-two-open")
        metrics["menu-two"] = analyze_menu(menu_two, layout_two, palette)
        current["layout"] = layout_two
        metrics["menu-two-hover-row0"] = hover_row(0, "menu-two-hover-row0")
        session.pointer(200, 900)
        time.sleep(args.settle)
        metrics["menu-two-hover-disabled"] = hover_row(2, "menu-two-hover-disabled")
        session.pointer(200, 900)
        time.sleep(args.settle)

        # --- assertions --------------------------------------------------
        def require(condition: bool, message: str) -> None:
            if args.mode == "assert" and not condition:
                errors.append(message)

        def check_color(label: str, actual, expected, tolerance: int) -> None:
            if args.mode != "assert":
                return
            if actual is None:
                errors.append(f"{label}: missing sample")
                return
            distance = rgb_distance(tuple(actual), expected)
            if distance > tolerance:
                errors.append(f"{label}: {tuple(actual)} is {distance} away from {expected}")

        expected_surface = palette["surface"]
        expected_selection = palette["selection"]
        expected_border = palette["border"]
        expected_bright = palette["brightFg"]
        expected_muted = palette["muted"]

        for name, label in (("one", "backend one"), ("two", "backend two")):
            menu = metrics[f"menu-{name}"]
            require(menu["expected_rect_px"][0] > 0, f"{label}: menu did not render")
            require(menu.get("detected_rect_px") is not None, f"{label}: menu rect not detected")
            if menu.get("rect_error_px"):
                for edge, delta in menu["rect_error_px"].items():
                    require(abs(delta) <= 3, f"{label}: menu {edge} edge off by {delta}px")
            check_color(f"{label}: menu background", menu.get("bg_median"), expected_surface, 3)
            check_color(f"{label}: menu border", menu.get("border_median"), expected_border, 24)
            # Rounded corner: the physical corner must show wallpaper, and the
            # 12px radius must cut roughly 12*scale*(1-1/sqrt2) into the edge.
            for dx, dy in ((1, 1), (2, 2)):
                pixel = menu["corner_pixels"][0 if (dx, dy) == (1, 1) else 1]
                require(
                    rgb_distance(tuple(pixel), WALLPAPER) <= 12,
                    f"{label}: corner ({dx},{dy}) is not wallpaper: {tuple(pixel)}",
                )
            require(
                menu.get("fitted_radius_logical") is not None
                and 11.5 <= menu["fitted_radius_logical"] <= 12.5,
                f"{label}: fitted corner radius {menu.get('fitted_radius_logical')} logical px, expected 12px",
            )
            require(
                (menu.get("fitted_radius_error_px") or 99) <= 4.0,
                f"{label}: corner profile does not follow the 12px radius (error {menu.get('fitted_radius_error_px')}px)",
            )
            rows = menu["rows"]
            require(len(rows) == ROW_COUNT, f"{label}: expected {ROW_COUNT} menu rows")
            if len(rows) == ROW_COUNT:
                normal, disabled = rows[0], rows[2]
                require(
                    normal["count_near_brightFg_14"] >= 50,
                    f"{label}: normal row text is not brightFg ({normal['count_near_brightFg_14']} px)",
                )
                require(normal["min_distance_brightFg"] <= 12, f"{label}: normal row text colour differs from brightFg")
                require(
                    normal["count_near_brightFg_14"] > 2 * normal["count_near_muted_14"],
                    f"{label}: normal row text is not dominated by brightFg",
                )
                require(
                    disabled["count_near_muted_14"] >= 50,
                    f"{label}: disabled row text is not palette muted ({disabled['count_near_muted_14']} px)",
                )
                require(disabled["min_distance_muted"] <= 14, f"{label}: disabled row text colour differs from muted")
                require(
                    disabled["count_near_brightFg_14"] * 4 < disabled["count_near_muted_14"],
                    f"{label}: disabled row text is not dimmer than normal text",
                )
            hover = metrics[f"menu-{name}-hover-row0"]
            check_color(f"{label}: hover background", hover.get("hover_bg_median"), expected_selection, 3)
            require(
                hover["count_near_brightFg_14"] >= 50, f"{label}: hovered row text is not brightFg"
            )
            disabled_hover = metrics[f"menu-{name}-hover-disabled"]
            check_color(f"{label}: disabled hover background", disabled_hover.get("hover_bg_median"), expected_selection, 3)
            require(
                disabled_hover["count_near_muted_14"] >= 50,
                f"{label}: hovered disabled row text is not muted",
            )

        submenu = metrics["menu-one-submenu"]
        require(submenu.get("detected_rect_px") is not None, "submenu did not render")
        if submenu.get("detected_rect_px"):
            check_color("submenu background", submenu.get("bg_median"), expected_surface, 3)
            check_color("submenu border", submenu.get("border_median"), expected_border, 28)
            require(submenu["min_distance_brightFg"] <= 14, "submenu text is not brightFg")

        metrics["checks"] = {
            "row_count": ROW_COUNT,
            "menu_rect_tolerance_px": 3,
            "border_tolerance": 24,
            "text_tolerance": 14,
        }
    except Failed as exc:
        errors.append(str(exc))
        metrics["error"] = str(exc)
    finally:
        session.stop()
    metrics["errors"] = errors
    (args.out / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    if errors:
        print("FAILED:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print(json.dumps({"ok": True, "out": str(args.out), "screens": sorted(p.name for p in (args.out / "screens").glob("*.png"))}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
