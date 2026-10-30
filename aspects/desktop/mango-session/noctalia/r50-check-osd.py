#!/usr/bin/env python3
"""Pixel regression for Noctalia's compact horizontal OSD.

The harness starts a private D-Bus session and a private headless Sway output.
It never inherits the caller's environment. Pillow is the only Python package
required by the analyzer.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time
from typing import Any

try:
    from PIL import Image, ImageChops
except ImportError as exc:  # pragma: no cover - exercised by CLI users
    raise SystemExit("r50-check-osd.py requires Pillow in the Python environment") from exc


WIDTH = 2560
HEIGHT = 1600
SCALE = 1.5
CARD_W = 246.0
CARD_H = 46.0
CARD_W_PX = round(CARD_W * SCALE)
CARD_H_PX = round(CARD_H * SCALE)
PAD_PX = round(20.0 * SCALE)
CELL_PX = round(36.0 * SCALE)
GLYPH_PX = round(18.0 * SCALE)
GAP_PX = round(12.0 * SCALE)
RAIL_H_PX = round(3.0 * SCALE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--noctalia", required=True, help="Noctalia executable")
    parser.add_argument("--sway", required=True, help="Sway executable")
    parser.add_argument("--grim", required=True, help="grim executable")
    parser.add_argument("--dbus-run-session", required=True, help="dbus-run-session executable")
    parser.add_argument("--coreutils", required=True, help="Nix coreutils bin directory (provides uname and helpers)")
    parser.add_argument("--out", required=True, type=Path, help="directory for screenshots and metrics.json")
    parser.add_argument("--fontconfig", type=Path, help="optional isolated fontconfig file (fonts.conf)")
    parser.add_argument("--egl-vendor", type=Path, help="optional EGL vendor JSON for llvmpipe")
    parser.add_argument("--palette", type=Path, help="optional Nix-generated Noctalia custom palette JSON")
    parser.add_argument("--startup-timeout", type=float, default=30.0)
    parser.add_argument("--settle-time", type=float, default=0.35)
    parser.add_argument("--_worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--_root", type=Path, help=argparse.SUPPRESS)
    return parser.parse_args()


def run_checked(argv: list[str], *, env: dict[str, str], timeout: float = 15.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)


def terminate_group(proc: subprocess.Popen[Any] | None) -> None:
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


def capture(grim: str, path: Path, env: dict[str, str]) -> tuple[int, int]:
    result = run_checked([grim, "-o", "HEADLESS-1", str(path)], env=env, timeout=15)
    if result.returncode:
        raise RuntimeError(f"grim failed ({result.returncode}): {result.stderr.strip()}")
    with Image.open(path) as captured:
        source_size = captured.size
        if source_size not in {(WIDTH, HEIGHT - 1), (WIDTH, HEIGHT)}:
            raise AssertionError(f"expected physical screenshot {WIDTH}x{HEIGHT - 1} or {WIDTH}x{HEIGHT}; got {source_size}")
    return source_size


def show_osd(
    noctalia: str,
    env: dict[str, str],
    icon: str,
    progress: float,
    value: str,
    inactive: bool,
) -> None:
    payload = json.dumps(
        {"icon": icon, "value": value, "progress": progress, "inactive": inactive}, separators=(",", ":")
    )
    result = run_checked([noctalia, "msg", "osd-show", payload], env=env, timeout=8)
    if result.returncode or result.stdout.lstrip().lower().startswith("error"):
        raise RuntimeError(
            "Noctalia osd-show failed; expected the locked CLI's JSON positional argument. "
            f"stdout={result.stdout.strip()!r} stderr={result.stderr.strip()!r}"
        )


def rgb_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    return max(abs(a[i] - b[i]) for i in range(3))


def median_rgb(image: Image.Image, box: tuple[int, int, int, int]) -> tuple[int, int, int]:
    crop = image.crop(box).convert("RGB")
    channels = [sorted(crop.getchannel(name).getdata()) for name in ("R", "G", "B")]
    mid = len(channels[0]) // 2
    return tuple(channel[mid] for channel in channels)  # type: ignore[return-value]


def changed_bbox(base: Image.Image, shot: Image.Image) -> tuple[int, int, int, int] | None:
    # Limit analysis to the expected bottom-center OSD neighborhood. This
    # excludes unrelated compositor/output changes and keeps memory bounded.
    height = shot.height
    roi = (WIDTH // 2 - 360, height - 280, WIDTH // 2 + 360, height - 40)
    diff = ImageChops.difference(base.crop(roi).convert("RGB"), shot.crop(roi).convert("RGB"))
    mask = diff.convert("L").point(lambda px: 255 if px >= 7 else 0)
    bounds = mask.getbbox()
    if bounds is None:
        return None
    return bounds[0] + roi[0], bounds[1] + roi[1], bounds[2] + roi[0], bounds[3] + roi[1]


def foreground_bbox(
    image: Image.Image,
    bounds: tuple[int, int, int, int],
    surface: tuple[int, int, int],
) -> tuple[int, int, int, int] | None:
    crop = image.crop(bounds).convert("RGB")
    pix = crop.load()
    mask = Image.new("L", crop.size)
    out = mask.load()
    for y in range(crop.height):
        for x in range(crop.width):
            # Detect ink by contrast to the actual rendered capsule surface;
            # this works for both light and dark theme defaults and avoids
            # assuming a particular glyph color in the pixel assertion.
            out[x, y] = 255 if rgb_distance(pix[x, y], surface) >= 48 else 0
    local = mask.getbbox()
    if local is None:
        return None
    return local[0] + bounds[0], local[1] + bounds[1], local[2] + bounds[0], local[3] + bounds[1]


def analyze_case(
    baseline: Image.Image,
    shot: Image.Image,
    *,
    label: str,
    volume: bool,
    progress: float,
    check_progress: bool,
    compare_value_pixels: bool,
    previous_value_right: int | None,
    previous_value_crop: Image.Image | None,
    previous_progress_fill: int | None,
    previous_numeric_geometry: tuple[int, int, int, int] | None,
) -> tuple[dict[str, Any], int | None, list[str], Image.Image | None, int | None, tuple[int, int, int, int] | None]:
    errors: list[str] = []
    detected = changed_bbox(baseline, shot)
    if detected is None:
        return (
            {"changed_bbox_px": None},
            previous_value_right,
            [f"{label}: no OSD pixels changed from the blank baseline"],
            previous_value_crop,
            previous_progress_fill,
            previous_numeric_geometry,
        )
    x0, y0, x1, y1 = detected
    expected_x0 = (WIDTH - CARD_W_PX) // 2
    expected_y0 = shot.height - round(96 * SCALE) - CARD_H_PX
    measured_w, measured_h = x1 - x0, y1 - y0
    # Changed pixels include capsule antialiasing and possible shadow, so allow
    # a narrow fringe around the exact 246x46 logical surface.
    if abs(measured_w - CARD_W_PX) > 3 or abs(measured_h - CARD_H_PX) > 3:
        errors.append(
            f"{label}: changed OSD footprint {measured_w}x{measured_h}px; expected near "
            f"{CARD_W_PX}x{CARD_H_PX}px (246x46 logical at scale 1.5)"
        )
    if abs((x0 + x1) / 2 - WIDTH / 2) > 4:
        errors.append(f"{label}: OSD horizontal center shifted: {(x0 + x1) / 2:.1f}px")

    # Use the specified panel geometry for cell-level pixel checks. The
    # capsule's rounded corners do not change these content-box coordinates.
    card = (expected_x0, expected_y0, expected_x0 + CARD_W_PX, expected_y0 + CARD_H_PX)
    card_crop = shot.crop(card).convert("RGB")
    # Card background is sampled below the content row, away from rounded ends.
    surface = median_rgb(card_crop, (CARD_W_PX // 2 - 4, CARD_H_PX - 11, CARD_W_PX // 2 + 4, CARD_H_PX - 4))

    # Locate the thin progress rail by its long contiguous contrast run in the
    # center lane. Sampling across nearby rows accommodates 1.5x antialiasing.
    # Search wider than the expected rail so a misplaced rail cannot be
    # cropped into an apparently centered one. Icon/value cells are outside
    # this vertical band except for glyph edges; the long-run criterion picks
    # the actual track across its full extent.
    rail_lane = (
        expected_x0 + PAD_PX - 8,
        expected_y0 + 9,
        expected_x0 + CARD_W_PX - PAD_PX + 8,
        expected_y0 + CARD_H_PX - 9,
    )
    sx0, sy0, sx1, sy1 = rail_lane
    rgb = shot.convert("RGB").load()
    rail_candidates: list[tuple[int, int, int, int]] = []
    for y in range(sy0, sy1):
        runs: list[tuple[int, int]] = []
        run_start: int | None = None
        for x in range(sx0, sx1):
            contrasted = rgb_distance(rgb[x, y], surface) >= 9
            if contrasted and run_start is None:
                run_start = x
            elif not contrasted and run_start is not None:
                runs.append((run_start, x))
                run_start = None
        if run_start is not None:
            runs.append((run_start, sx1))
        if runs:
            start, end = max(runs, key=lambda pair: pair[1] - pair[0])
            if end - start >= (sx1 - sx0) * 0.35:
                rail_candidates.append((end - start, start, end, y))
    if not rail_candidates:
        errors.append(f"{label}: could not locate the rendered progress rail in the pixel output")
        rail_len = 0
        rail_left = rail_right = rail_y = 0
    else:
        rail_len, rail_left, rail_right, rail_y = max(rail_candidates)
    if rail_candidates and (rail_left <= sx0 or rail_right >= sx1):
        errors.append(f"{label}: rail analysis reached its broad search boundary; endpoint may be clipped")
    if rail_candidates and (rail_len < 90 or rail_len > 168):
        errors.append(f"{label}: measured rail width {rail_len}px is outside the allowed 90..168px range")
    rail_center_error = abs((rail_left + rail_right) / 2 - WIDTH / 2)
    if rail_candidates and rail_center_error > 3:
        errors.append(f"{label}: rail endpoints are asymmetric by {rail_center_error:.1f}px")

    left_cell_width: int | None = None
    right_cell_width: int | None = None
    numeric_geometry: tuple[int, int, int, int] | None = None
    if rail_candidates:
        left_cell_start = expected_x0 + PAD_PX
        right_cell_end = expected_x0 + CARD_W_PX - PAD_PX
        left_cell_width = rail_left - GAP_PX - left_cell_start
        right_cell_width = right_cell_end - (rail_right + GAP_PX)
        numeric_geometry = (left_cell_width, right_cell_width, rail_left, rail_right)
        if abs(left_cell_width - right_cell_width) > 3:
            errors.append(
                f"{label}: inferred end cells are asymmetric ({left_cell_width}px vs {right_cell_width}px)"
            )
        if min(left_cell_width, right_cell_width) < CELL_PX - 2:
            errors.append(
                f"{label}: inferred end cell is narrower than 36px logical ({left_cell_width}px, {right_cell_width}px)"
            )
        if check_progress and previous_numeric_geometry is not None:
            names = ("left cell width", "right cell width", "rail left", "rail right")
            for name, current, previous in zip(names, numeric_geometry, previous_numeric_geometry):
                if abs(current - previous) > 2:
                    errors.append(
                        f"{label}: {name} shifted between 0/7/15/100% samples ({previous}px -> {current}px)"
                    )

    fill_length = 0
    fill_run: list[int] | None = None
    if rail_candidates:
        fill_runs: list[tuple[int, int, int]] = []
        # At the rail's center, the active OnSurface fill is high contrast
        # against the capsule, while the dim outline track remains below this
        # threshold. Sampling several center rows avoids AA sensitivity.
        for y in range(max(sy0, rail_y - 2), min(sy1, rail_y + 3)):
            active_x = [x for x in range(rail_left, rail_right) if rgb_distance(rgb[x, y], surface) >= 48]
            if active_x:
                start = last = active_x[0]
                row_runs: list[tuple[int, int, int]] = []
                for x in active_x[1:]:
                    if x != last + 1:
                        row_runs.append((last - start + 1, start, last + 1))
                        start = x
                    last = x
                row_runs.append((last - start + 1, start, last + 1))
                fill_runs.append(max(row_runs))
        if fill_runs:
            fill_length, fill_start, fill_end = max(fill_runs)
            fill_run = [fill_start, fill_end]
        if check_progress:
            expected_fill = round(progress * rail_len)
            if abs(fill_length - expected_fill) > 6:
                errors.append(
                    f"{label}: active rail fill measured {fill_length}px, expected {expected_fill}px "
                    f"for progress={progress:.2f} (6px AA/rounded-cap allowance)"
                )
            if previous_progress_fill is not None and fill_length <= previous_progress_fill:
                errors.append(
                    f"{label}: active fill did not increase from the previous progress sample "
                    f"({previous_progress_fill}px -> {fill_length}px)"
                )

    # Measure icon ink from a broad region first. This catches pixels that
    # trespass into the capsule padding instead of cropping them away at the
    # expected 20px inset or viewport boundary.
    icon_roi_left = expected_x0 + 5
    icon_roi_right = rail_left - 8 if rail_candidates else expected_x0 + PAD_PX + CELL_PX
    icon_roi = (
        icon_roi_left,
        expected_y0 + CARD_H_PX // 2 - 20,
        icon_roi_right,
        expected_y0 + CARD_H_PX // 2 + 20,
    )
    icon_box = foreground_bbox(shot, icon_roi, surface)
    icon_viewport = (expected_x0 + PAD_PX, expected_x0 + PAD_PX + GLYPH_PX)
    icon_viewport_y = (
        expected_y0 + CARD_H_PX // 2 - GLYPH_PX // 2,
        expected_y0 + CARD_H_PX // 2 - GLYPH_PX // 2 + GLYPH_PX,
    )
    if icon_box is None:
        errors.append(f"{label}: no visible OSD icon pixels found in the uncut left-side region")
        ix0 = iy0 = ix1 = iy1 = 0
        icon_center = float(sum(icon_viewport) / 2)
    else:
        ix0, iy0, ix1, iy1 = icon_box
        icon_center = (ix0 + ix1) / 2
    viewport_center = sum(icon_viewport) / 2
    if icon_box is not None and (ix0 < icon_viewport[0] or ix1 > icon_viewport[1]):
        errors.append(f"{label}: visible icon ink falls outside the 18px viewport: {icon_box}")
    if icon_box is not None and (iy0 < icon_viewport_y[0] or iy1 > icon_viewport_y[1]):
        errors.append(f"{label}: visible icon ink falls outside the 18px viewport vertically: {icon_box}")
    if abs(icon_center - viewport_center) > 6:
        errors.append(
            f"{label}: icon ink center {icon_center:.1f}px differs from 18px viewport center {viewport_center:.1f}px"
        )
    icon_center_y = (iy0 + iy1) / 2 if icon_box is not None else sum(icon_viewport_y) / 2
    viewport_center_y = sum(icon_viewport_y) / 2
    if abs(icon_center_y - viewport_center_y) > 6:
        errors.append(
            f"{label}: icon ink vertical center {icon_center_y:.1f}px differs from viewport center {viewport_center_y:.1f}px"
        )

    value_right: int | None = None
    value_box = None
    outer_margin_difference: int | None = None
    value_crop: Image.Image | None = None
    if volume:
        right_cell = (
            rail_right + GAP_PX,
            expected_y0 + 5,
            expected_x0 + CARD_W_PX - PAD_PX,
            expected_y0 + CARD_H_PX - 5,
        )
        # Find the full ink before applying the intended value-cell bounds;
        # ink that trespasses into the outer padding must remain detectable.
        value_roi = (
            rail_right + 8,
            expected_y0 + CARD_H_PX // 2 - 20,
            expected_x0 + CARD_W_PX - 5,
            expected_y0 + CARD_H_PX // 2 + 20,
        )
        value_box = foreground_bbox(shot, value_roi, surface)
        if value_box is not None and (value_box[0] < right_cell[0] - 1 or value_box[2] > right_cell[2] + 1):
            errors.append(f"{label}: percentage ink extends beyond its trailing cell: {value_box}")
        if value_box is None:
            errors.append(f"{label}: no visible percentage ink found in the inferred trailing cell")
        else:
            value_crop = shot.crop(right_cell).convert("RGB")
            value_right = value_box[2] - 1
            expected_right = right_cell[2] - 1
            if abs(value_right - expected_right) > 5:
                errors.append(
                    f"{label}: percentage is not right-aligned in its fixed cell ({value_right}px vs {expected_right}px)"
                )
            if previous_value_right is not None and abs(value_right - previous_value_right) > 2:
                errors.append(
                    f"{label}: percentage right edge moved across values ({previous_value_right}px -> {value_right}px)"
                )
            if compare_value_pixels and previous_value_crop is not None:
                value_diff = ImageChops.difference(previous_value_crop, value_crop).convert("L")
                changed_ink = value_diff.point(lambda px: 255 if px >= 10 else 0).getbbox()
                if changed_ink is None:
                    errors.append(f"{label}: percentage ink crop did not change from the preceding numeric sample")
        if icon_box is not None and value_box is not None:
            left_visible_margin = ix0 - expected_x0
            right_visible_margin = expected_x0 + CARD_W_PX - value_box[2]
            outer_margin_difference = abs(left_visible_margin - right_visible_margin)
            if outer_margin_difference > 5:
                errors.append(
                    f"{label}: visible outer ink margins differ by {outer_margin_difference}px "
                    f"(icon left={left_visible_margin}px, value right={right_visible_margin}px)"
                )

    return (
        {
            "changed_bbox_px": [x0, y0, x1, y1],
            "changed_size_px": [measured_w, measured_h],
            "expected_surface_px": [expected_x0, expected_y0, CARD_W_PX, CARD_H_PX],
            "surface_rgb_sample": list(surface),
            "icon_ink_bbox_px": [ix0, iy0, ix1, iy1],
            "icon_viewport_px": list(icon_viewport),
            "icon_viewport_y_px": [icon_viewport_y[0], icon_viewport_y[1]],
            "icon_viewport_center_error_px": round(abs(icon_center - viewport_center), 2),
            "rail_run_px": [rail_left, rail_right],
            "rail_length_px": rail_len,
            "inferred_left_cell_width_px": left_cell_width,
            "inferred_right_cell_width_px": right_cell_width,
            "rail_center_error_px": round(rail_center_error, 2),
            "rail_center_y_px": rail_y,
            "progress_fill_run_px": fill_run,
            "progress_fill_length_px": fill_length,
            "progress_fill_expected_px": round(progress * rail_len),
            "value_right_px": value_right,
            "value_ink_bbox_px": list(value_box) if value_box is not None else None,
            "visible_outer_margin_difference_px": outer_margin_difference,
            "errors": errors,
        },
        value_right if volume else previous_value_right,
        errors,
        value_crop if compare_value_pixels and value_crop is not None else previous_value_crop,
        fill_length if check_progress else previous_progress_fill,
        numeric_geometry if check_progress and numeric_geometry is not None else previous_numeric_geometry,
    )


def worker(args: argparse.Namespace) -> int:
    root = args._root
    if root is None:
        raise RuntimeError("internal worker root directory missing")
    # Keep the compositor runtime path short enough for Sway's Unix IPC socket.
    runtime = args.out / f"rt-{os.getpid() % 100000:05d}"
    home = root / "home"
    config = root / "config"
    cache = root / "cache"
    state = root / "state"
    for directory in (runtime, home, config, cache, state):
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    runtime.chmod(0o700)

    config_file = root / "sway.conf"
    config_file.write_text(
        "\n".join(
            [
                "output HEADLESS-1 mode 2560x1600 scale 1.5",
                "output * bg #202124 solid_color",
                "default_border none",
                "default_floating_border none",
                "font pango:Sans 10",
                "focus_follows_mouse no",
                "mouse_warping none",
                "xwayland disable",
                "seat seat0 hide_cursor 1000000",
                "",
            ]
        ),
        encoding="utf-8",
    )
    env = {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(config),
        "XDG_CACHE_HOME": str(cache),
        "XDG_STATE_HOME": str(state),
        "XDG_DATA_HOME": str(root / "data"),
        "XDG_RUNTIME_DIR": str(runtime),
        "XDG_SESSION_TYPE": "wayland",
        "XDG_CURRENT_DESKTOP": "sway",
        "XDG_SESSION_DESKTOP": "sway",
        "WLR_BACKENDS": "headless",
        "WLR_RENDERER": "pixman",
        "WLR_LIBINPUT_NO_DEVICES": "1",
        "LIBGL_ALWAYS_SOFTWARE": "1",
        "QT_QPA_PLATFORM": "wayland",
        "QT_WAYLAND_DISABLE_WINDOWDECORATION": "1",
        "DBUS_SYSTEM_BUS_ADDRESS": f"unix:path={runtime / 'unreachable-system-bus'}",
        "PATH": os.pathsep.join(
            [
                str(Path(args.noctalia).resolve().parent),
                str(Path(args.sway).resolve().parent),
                str(Path(args.grim).resolve().parent),
                str(Path(args.dbus_run_session).resolve().parent),
                str(Path(args.coreutils).expanduser().resolve()),
            ]
        ),
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
    }
    if args.fontconfig:
        env["FONTCONFIG_FILE"] = str(args.fontconfig.expanduser().resolve())
    if args.egl_vendor:
        env["__EGL_VENDOR_LIBRARY_FILENAMES"] = str(args.egl_vendor.expanduser().resolve())
    session_bus = os.environ.get("DBUS_SESSION_BUS_ADDRESS")
    if not session_bus:
        raise RuntimeError("dbus-run-session did not provide a private DBUS_SESSION_BUS_ADDRESS")
    noctalia_env = dict(env)
    noctalia_env["DBUS_SESSION_BUS_ADDRESS"] = session_bus

    noctalia_config_dir = config / "noctalia"
    noctalia_config_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    palette_dir = noctalia_config_dir / "palettes"
    if args.palette:
        palette_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        (palette_dir / "onedark.json").write_bytes(args.palette.expanduser().resolve().read_bytes())
    (noctalia_config_dir / "config.toml").write_text(
        """[brightness]
enable_ddcutil = false

[audio]
enable_sounds = false

[bar.main]
enabled = false

[desktop_widgets]
enabled = false

[dock]
enabled = false

[idle.behavior.lock]
enabled = false

[idle.behavior.screen-off]
enabled = false

[idle.behavior.suspend]
enabled = false

[osd]
background_opacity = 1.0
border = true
border_width = 1
hide_delay_ms = 10000
offset_y = 96
orientation = "horizontal"
position = "bottom_center"

[plugins]
enabled = []

[shell]
offline_mode = true
animation = { enabled = false, speed = 1.0 }
clipboard_enabled = false
font_family = "Inter"
polkit_agent = false

[theme]
source = "custom"
custom_palette = "onedark"
mode = "dark"

[wallpaper]
enabled = false
""",
        encoding="utf-8",
    )
    (state / "noctalia").mkdir(mode=0o700, exist_ok=True)
    (state / "noctalia" / ".setup-complete").touch()
    data = root / "data"
    data.mkdir(mode=0o700, exist_ok=True)
    logs = args.out / "logs"
    logs.mkdir(mode=0o700, parents=True, exist_ok=True)
    sway_log = (logs / "sway.log").open("w", encoding="utf-8")
    noctalia_log = (logs / "noctalia.log").open("w", encoding="utf-8")
    sway_proc: subprocess.Popen[Any] | None = None
    noctalia_proc: subprocess.Popen[Any] | None = None
    try:
        sockets_before = {p.name for p in runtime.iterdir()}
        sway_env = {
            key: value
            for key, value in env.items()
            if key not in {"DBUS_SESSION_BUS_ADDRESS", "WAYLAND_DISPLAY", "SWAYSOCK"}
        }
        sway_proc = subprocess.Popen(
            [args.sway, "-c", str(config_file)],
            env=sway_env,
            stdout=sway_log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        deadline = time.monotonic() + args.startup_timeout
        while time.monotonic() < deadline:
            if sway_proc.poll() is not None:
                raise RuntimeError(f"headless sway exited early; see {logs / 'sway.log'}")
            wayland_sockets = [
                p for p in runtime.iterdir()
                if p.name.startswith("wayland-") and p.name not in sockets_before and stat.S_ISSOCK(p.stat().st_mode)
            ]
            if wayland_sockets:
                break
            time.sleep(0.1)
        else:
            raise TimeoutError(f"headless sway did not create a private Wayland socket; see {logs / 'sway.log'}")

        wayland_socket = max(wayland_sockets, key=lambda p: p.stat().st_mtime_ns)
        noctalia_env["WAYLAND_DISPLAY"] = wayland_socket.name
        ipc_sockets = [p for p in runtime.glob("sway-ipc.*.sock") if stat.S_ISSOCK(p.stat().st_mode)]
        if ipc_sockets:
            noctalia_env["SWAYSOCK"] = str(max(ipc_sockets, key=lambda p: p.stat().st_mtime_ns))
        display_env = dict(noctalia_env)

        noctalia_proc = subprocess.Popen(
            [args.noctalia],
            env=noctalia_env,
            stdout=noctalia_log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        deadline = time.monotonic() + args.startup_timeout
        while time.monotonic() < deadline:
            if noctalia_proc.poll() is not None:
                raise RuntimeError(f"Noctalia exited early; see {logs / 'noctalia.log'}")
            try:
                ready = run_checked([args.noctalia, "msg", "panel-close"], env=noctalia_env, timeout=2)
                if ready.returncode == 0 and ready.stdout.startswith("ok"):
                    break
            except subprocess.TimeoutExpired:
                pass
            time.sleep(0.1)
        else:
            raise TimeoutError(f"Noctalia private IPC did not become ready; see {logs / 'noctalia.log'}")
        time.sleep(args.settle_time)

        args.out.mkdir(mode=0o700, parents=True, exist_ok=True)
        baseline_path = args.out / "baseline.png"
        baseline_capture_size = capture(args.grim, baseline_path, display_env)
        with Image.open(baseline_path) as baseline_source:
            baseline = baseline_source.convert("RGB")

        cases = [
            ("volume-0", "volume-mute", 0.0, "0%", False, True),
            ("volume-7", "volume-low", 0.07, "7%", False, True),
            ("volume-15", "volume-low", 0.15, "15%", False, True),
            ("volume-100", "volume-high", 1.0, "100%", False, True),
            ("volume-muted", "volume-mute", 0.15, "15%", True, True),
            ("brightness", "brightness-high", 0.57, "57%", False, True),
            ("microphone-muted", "microphone-mute", 0.0, "0%", True, True),
        ]
        results: list[dict[str, Any]] = []
        failures: list[str] = []
        previous_right: int | None = None
        previous_numeric_crop: Image.Image | None = None
        previous_progress_fill: int | None = None
        previous_numeric_geometry: tuple[int, int, int, int] | None = None
        progress_cases = {"volume-0", "volume-7", "volume-15", "volume-100"}
        for name, icon, progress, value, inactive, is_volume in cases:
            show_osd(args.noctalia, noctalia_env, icon, progress, value, inactive)
            time.sleep(args.settle_time)
            screenshot = args.out / f"{name}.png"
            source_capture_size = capture(args.grim, screenshot, display_env)
            with Image.open(screenshot) as shot_source:
                (
                    details,
                    previous_right,
                    case_errors,
                    previous_numeric_crop,
                    previous_progress_fill,
                    previous_numeric_geometry,
                ) = analyze_case(
                    baseline,
                    shot_source.convert("RGB"),
                    label=name,
                    volume=is_volume,
                    progress=progress,
                    check_progress=name in progress_cases,
                    compare_value_pixels=name in progress_cases,
                    previous_value_right=previous_right,
                    previous_value_crop=previous_numeric_crop,
                    previous_progress_fill=previous_progress_fill,
                    previous_numeric_geometry=previous_numeric_geometry,
                )
            results.append(
                {
                    "case": name,
                    "icon": icon,
                    "progress": progress,
                    "value": value,
                    "inactive": inactive,
                    "grim_source_size_px": list(source_capture_size),
                    **details,
                }
            )
            failures.extend(case_errors)

        manifest = {
            "resolution_px": [WIDTH, HEIGHT],
            "scale": SCALE,
            "logical_resolution": [WIDTH / SCALE, HEIGHT / SCALE],
            "target_card_logical": [CARD_W, CARD_H],
            "target_card_physical": [CARD_W_PX, CARD_H_PX],
            "baseline_grim_source_size_px": list(baseline_capture_size),
            "cell_padding_logical": 20,
            "minimum_dynamic_end_cell_logical": 36,
            "rail_logical": {"height": 3, "gap": 12},
            "wayland_display": wayland_socket.name,
            "dbus_system_bus": noctalia_env["DBUS_SYSTEM_BUS_ADDRESS"],
            "fontconfig_file": env.get("FONTCONFIG_FILE"),
            "egl_vendor_file": env.get("__EGL_VENDOR_LIBRARY_FILENAMES"),
            "custom_palette_file": str(palette_dir / "onedark.json") if args.palette else None,
            "cases": results,
            "checks": [
                "real Noctalia pixels changed from private blank baseline",
                "246x46 logical OSD footprint at scale 1.5",
                "uncropped icon ink lies inside and centers in its 18px viewport",
                "progress rail has symmetric endpoints",
                "volume percentage right edge remains stable across 0/7/15/100%",
                "0/7/15/100 percentage crops differ and active fill matches progress within 6 physical pixels",
                "visible icon-left and value-right ink margins differ by at most 5 physical pixels",
            ],
            "failures": failures,
        }
        (args.out / "metrics.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"ok": not failures, "out": str(args.out), "cases": len(results), "failures": failures}, ensure_ascii=False))
        return 1 if failures else 0
    finally:
        terminate_group(noctalia_proc)
        terminate_group(sway_proc)
        sway_log.close()
        noctalia_log.close()


def main() -> int:
    args = parse_args()
    args.out = args.out.expanduser().resolve()
    if args._worker:
        return worker(args)
    args.out.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Persist only private harness state and debug logs under --out, as the
    # parent may need to inspect startup diagnostics after a failed assertion.
    private = args.out / "p"
    private.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Clear all inherited variables. dbus-run-session adds only its fresh
    # session-bus address; system-bus activation remains pointed at a
    # deliberately nonexistent private socket in the worker.
    outer_env = {
        "HOME": str(private / "outer-home"),
        "PATH": os.pathsep.join(
            [str(Path(args.dbus_run_session).resolve().parent), str(Path(sys.executable).resolve().parent)]
        ),
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
    }
    Path(outer_env["HOME"]).mkdir(mode=0o700, exist_ok=True)
    private_bus_dir = private / "dbus"
    private_bus_dir.mkdir(mode=0o700, exist_ok=True)
    no_services = private / "no-dbus-services"
    no_services.mkdir(mode=0o700, exist_ok=True)
    bus_config = private / "dbus-session.conf"
    bus_config.write_text(
        "\n".join(
            [
                "<!DOCTYPE busconfig PUBLIC '-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN'",
                " 'http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd'>",
                "<busconfig>",
                "  <type>session</type>",
                f"  <listen>unix:dir={private_bus_dir}</listen>",
                "  <auth>EXTERNAL</auth>",
                f"  <servicedir>{no_services}</servicedir>",
                "  <policy context='default'>",
                "    <allow user='*'/>",
                "    <allow own='*'/>",
                "    <allow send_destination='*'/>",
                "    <allow receive_sender='*'/>",
                "  </policy>",
                "</busconfig>",
                "",
            ]
        ),
        encoding="utf-8",
    )
    argv = [
        args.dbus_run_session,
        "--config-file",
        str(bus_config),
        "--",
        sys.executable,
        str(Path(__file__).resolve()),
        "--noctalia",
        args.noctalia,
        "--sway",
        args.sway,
        "--grim",
        args.grim,
        "--dbus-run-session",
        args.dbus_run_session,
        "--coreutils",
        args.coreutils,
        "--out",
        str(args.out),
        "--startup-timeout",
        str(args.startup_timeout),
        "--settle-time",
        str(args.settle_time),
        "--_worker",
        "--_root",
        str(private / "s"),
    ]
    if args.fontconfig:
        argv += ["--fontconfig", str(args.fontconfig)]
    if args.egl_vendor:
        argv += ["--egl-vendor", str(args.egl_vendor)]
    if args.palette:
        argv += ["--palette", str(args.palette)]
    result = subprocess.run(argv, env=outer_env, text=True)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
