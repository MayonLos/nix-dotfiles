#!/usr/bin/env python3
"""Small, privacy-preserving status producer for the dwm root window."""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence


ROOT_CLOCK_PROPERTY = "_MAYON_DWM_CLOCK"
WEEKDAYS = ("周一", "周二", "周三", "周四", "周五", "周六", "周日")


def run(argv: Sequence[str], *, timeout: float = 1.0) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            list(argv),
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=os.environ.copy(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def color(text: str, value: str) -> str:
    """Use only Nix-provided palette colors, never command output as markup."""
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        value = "#abb2bf"
    return f"^c{value}^{text}^d^"


def cpu_percent(previous: tuple[int, int] | None, current: tuple[int, int]) -> tuple[int | None, tuple[int, int]]:
    if previous is None:
        return None, current
    total_delta = current[0] - previous[0]
    idle_delta = current[1] - previous[1]
    if total_delta <= 0 or idle_delta < 0:
        return None, current
    busy = max(0, min(100, round(100 * (total_delta - idle_delta) / total_delta)))
    return busy, current


def read_cpu(path: str = "/proc/stat") -> tuple[int, int] | None:
    try:
        fields = Path(path).read_text(encoding="ascii").splitlines()[0].split()
        if fields[0] != "cpu":
            return None
        values = [int(value) for value in fields[1:]]
        if len(values) < 4:
            return None
        return sum(values[:8]), values[3] + (values[4] if len(values) > 4 else 0)
    except (OSError, ValueError, IndexError):
        return None


def memory_gib(path: str = "/proc/meminfo") -> float | None:
    try:
        fields = {}
        for line in Path(path).read_text(encoding="ascii").splitlines():
            name, value, *_ = line.split()
            if name in {"MemTotal:", "MemAvailable:"}:
                fields[name] = int(value)
        if "MemTotal:" not in fields or "MemAvailable:" not in fields:
            return None
        used = max(0, fields["MemTotal:"] - fields["MemAvailable:"])
        return used / 1024 / 1024
    except (OSError, ValueError):
        return None


def default_route(path: str = "/proc/net/route") -> bool:
    try:
        lines = Path(path).read_text(encoding="ascii").splitlines()[1:]
        return any(
            len(row := line.split()) > 3
            and row[1] == "00000000"
            and bool(int(row[3], 16) & 0x1)
            for line in lines
        )
    except (OSError, ValueError):
        return False


def batteries(
    power_supply: str = "/sys/class/power_supply",
    conservation_root: str = "/sys/bus/platform/drivers/ideapad_acpi",
) -> list[tuple[int, str, bool]]:
    result = []
    for supply in glob.glob(os.path.join(power_supply, "*")):
        try:
            root = Path(supply)
            if (root / "type").read_text(encoding="ascii").strip() != "Battery":
                continue
            capacity = int((root / "capacity").read_text(encoding="ascii").strip())
            if not 0 <= capacity <= 100:
                continue
            state = (root / "status").read_text(encoding="ascii").strip()
            result.append((capacity, state, conservation_enabled(conservation_root)))
        except (OSError, ValueError):
            continue
    return result


def conservation_enabled(root: str = "/sys/bus/platform/drivers/ideapad_acpi") -> bool:
    values = []
    # Inspect only device roots: recursively following sysfs subsystem symlinks
    # would walk cycles and unrelated hardware.
    for path in [str(Path(root) / "conservation_mode"), *glob.glob(os.path.join(root, "*", "conservation_mode"))]:
        try:
            value = Path(path).read_text(encoding="ascii").strip()
            if value in {"0", "1"}:
                values.append(value)
        except OSError:
            continue
    return bool(values) and all(value == "1" for value in values)


def clock_label(now: dt.datetime | None = None) -> str:
    now = now or dt.datetime.now()
    return f"{now.month}月{now.day:02d}日 {WEEKDAYS[now.weekday()]} {now:%H:%M}"


@dataclass(frozen=True)
class Palette:
    blue: str = "#61afef"
    cyan: str = "#56b6c2"
    green: str = "#98c379"
    red: str = "#e06c75"
    muted: str = "#828a95"
    fg: str = "#abb2bf"


def render_status(
    *,
    cpu: int | None,
    memory: float | None,
    online: bool,
    volume: int | None,
    muted: bool,
    battery: list[tuple[int, str, bool]],
    ime_active: bool | None,
    palette: Palette = Palette(),
    notifications: int = 0,
    paused: bool = False,
) -> str:
    groups = [color("󰻠", palette.blue) + (f" {cpu}%" if cpu is not None else " --%")]
    groups += [color("󰍛", palette.cyan) + (f" {memory:.1f}G" if memory is not None else " --G")]
    groups += [color("│", palette.muted), color("󰖩" if online else "󰖪", palette.blue)]
    if muted:
        groups += [color("󰝟 muted", palette.muted)]
    elif volume is None:
        groups += [color("󰕾 --%", palette.muted)]
    else:
        groups += [color("󰕾", palette.blue) + f" {volume}%"]
    battery_icons = ("󰂄", "󰂃", "󰂂", "󰂁", "󰂀")
    for capacity, state, care in battery:
        icon = battery_icons[min(4, (100 - capacity) // 21)]
        tint = palette.red if capacity <= 20 and state == "Discharging" else palette.green
        group = color(icon, tint) + f" {capacity}%"
        if care:
            group += " " + color("养护", palette.green)
        groups.append(group)
    # Fcitx's engine state is not Rime's internal Chinese/ASCII mode. The
    # native tray icon remains the authoritative submode display.
    groups += [color("│", palette.muted), color("中" if ime_active else "英" if ime_active is False else "·", palette.cyan if ime_active else palette.muted)]
    groups += [color("󰂛" if paused else "󰂚", palette.muted) + (f" {notifications}" if notifications else "")]
    return " " + "  ".join(groups) + " "


@dataclass
class Sampler:
    xsetroot: str = "xsetroot"
    xprop: str = "xprop"
    wpctl: str = "wpctl"
    fcitx_remote: str = "fcitx5-remote"
    palette: Palette = Palette()
    proc_stat: str = "/proc/stat"
    proc_meminfo: str = "/proc/meminfo"
    proc_route: str = "/proc/net/route"
    power_supply: str = "/sys/class/power_supply"
    conservation_root: str = "/sys/bus/platform/drivers/ideapad_acpi"
    runner: Callable[..., subprocess.CompletedProcess[str] | None] = run
    previous_cpu: tuple[int, int] | None = None
    last_root: tuple[str, str] | None = None

    def collect(self) -> tuple[str, str]:
        current = read_cpu(self.proc_stat)
        cpu = None
        if current is not None:
            cpu, self.previous_cpu = cpu_percent(self.previous_cpu, current)

        volume_result = self.runner([self.wpctl, "get-volume", "@DEFAULT_AUDIO_SINK@"], timeout=1.0)
        volume, muted = None, False
        if volume_result is not None and volume_result.returncode == 0:
            muted = "[MUTED]" in volume_result.stdout
            match = re.search(r"\bVolume:\s+([0-9]+(?:\.[0-9]+)?)", volume_result.stdout)
            if match:
                volume = max(0, min(200, round(float(match.group(1)) * 100)))

        fcitx_result = self.runner([self.fcitx_remote], timeout=1.0)
        ime_active = None
        if fcitx_result is not None and fcitx_result.returncode == 0:
            state = fcitx_result.stdout.strip()
            if state in {"1", "2"}:
                ime_active = state == "2"

        count_result = self.runner(["dunstctl", "count", "waiting"], timeout=0.5)
        notifications = 0
        if count_result and count_result.returncode == 0 and re.fullmatch(r"[0-9]{1,5}\s*", count_result.stdout):
            notifications = min(999, int(count_result.stdout))
        paused_result = self.runner(["dunstctl", "is-paused"], timeout=0.5)
        paused = bool(paused_result and paused_result.stdout.strip() == "true")
        status = render_status(
            cpu=cpu,
            memory=memory_gib(self.proc_meminfo),
            online=default_route(self.proc_route),
            volume=volume,
            muted=muted,
            battery=batteries(self.power_supply, self.conservation_root),
            ime_active=ime_active,
            palette=self.palette,
            notifications=notifications,
            paused=paused,
        )
        return status, clock_label()

    def publish(self) -> None:
        status, clock = self.collect()
        value = (status, clock)
        if value == self.last_root:
            return
        self.runner([self.xsetroot, "-name", status], timeout=1.0)
        self.runner([self.xprop, "-root", "-f", ROOT_CLOCK_PROPERTY, "8u", "-set", ROOT_CLOCK_PROPERTY, clock], timeout=1.0)
        self.last_root = value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blue", default="#61afef")
    parser.add_argument("--cyan", default="#56b6c2")
    parser.add_argument("--green", default="#98c379")
    parser.add_argument("--red", default="#e06c75")
    parser.add_argument("--muted", default="#828a95")
    parser.add_argument("--fg", default="#abb2bf")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sampler = Sampler(palette=Palette(args.blue, args.cyan, args.green, args.red, args.muted, args.fg))
    try:
        while True:
            deadline = time.monotonic() + 5
            sampler.publish()
            time.sleep(max(0, deadline - time.monotonic()))
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
