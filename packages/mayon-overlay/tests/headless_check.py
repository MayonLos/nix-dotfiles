#!/usr/bin/env python3
"""Behavioural check for mayon-overlay.

The test starts private headless compositors (Sway and, when available, Mango),
builds a real cliphist history with `wl-copy` + `wl-paste` + `cliphist store`,
opens the overlay, drives it with synthetic keyboard input (`wtype`), a control
socket and simulated clicks, then verifies the result with `wl-paste`, `grim`
screenshots and the overlay's JSON-lines log.

Every environment detail is private: HOME, XDG_* and the Wayland runtime live
under --out, nothing is inherited from the caller's session.

Requirements are passed explicitly so the same script runs from a Nix check or
from a development shell. Only Pillow is needed beyond the tools themselves.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import warnings
from pathlib import Path
from typing import Any

warnings.filterwarnings("ignore", category=DeprecationWarning)

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover
    raise SystemExit("headless_check.py requires Pillow") from exc

PALETTE = {
    "bg": (0x1E, 0x22, 0x28),
    "surface": (0x27, 0x2C, 0x33),
    "selection": (0x32, 0x38, 0x43),
    "deep": (0x18, 0x1B, 0x20),
    "fg": (0xAB, 0xB2, 0xBF),
    "brightFg": (0xD7, 0xDA, 0xE0),
    "blue": (0x61, 0xAF, 0xEF),
    "red": (0xE0, 0x6C, 0x75),
}
THUMB_RED = (220, 40, 60)
THUMB_GREEN = (40, 200, 90)


def near(pixel: tuple[int, int, int], target: tuple[int, int, int], tolerance: int = 5) -> bool:
    return all(abs(int(pixel[i]) - target[i]) <= tolerance for i in range(3))


def count_near(image: Image.Image, box: tuple[int, int, int, int], target: tuple[int, int, int], tolerance: int = 5) -> int:
    crop = image.crop(box).convert("RGB")
    return sum(1 for pixel in crop.getdata() if near(pixel, target, tolerance))


def colorful(pixel: tuple[int, int, int], minimum: int = 28) -> bool:
    return max(pixel) - min(pixel) > minimum


def has_ink(image: Image.Image, box: tuple[int, int, int, int], tolerance: int = 40) -> bool:
    """Any pixel that is clearly lighter than the One Dark surfaces."""
    crop = image.crop(box).convert("RGB")
    for pixel in crop.getdata():
        if min(pixel) > 0x70:
            return True
        # antialiased glyphs may be dimmer than fg but still above surfaces
        if sum(pixel) > sum(PALETTE["surface"]) + tolerance * 3 and not colorful(pixel, 20):
            return True
    return False


class Result:
    def __init__(self) -> None:
        self.checks: list[dict[str, Any]] = []

    def add(self, name: str, ok: bool, detail: str = "") -> bool:
        self.checks.append({"name": name, "ok": ok, "detail": detail})
        print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f": {detail}" if detail else ""))
        return ok

    @property
    def failures(self) -> list[dict[str, Any]]:
        return [check for check in self.checks if not check["ok"]]


class Session:
    """Private headless compositor + XDG runtime."""

    def __init__(self, args: argparse.Namespace, result: Result, compositor: str) -> None:
        self.args = args
        self.result = result
        self.compositor = compositor
        # The compositor runtime path must stay short: Sway's IPC socket
        # does not fit into sun_path under a deep worktree directory.
        self.root = Path(tempfile.mkdtemp(prefix=f"mo-{compositor}-"))
        self.out_dir = Path(args.out) / f"private-{compositor}"
        self.logs = self.out_dir / "logs"
        self.shots = self.out_dir / "shots"
        for directory in ("home", "config", "cache", "state", "data", "runtime"):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        for directory in (self.logs, self.shots):
            directory.mkdir(parents=True, exist_ok=True)
        (self.root / "runtime").chmod(0o700)
        self.env = self._environment()
        self.proc: subprocess.Popen[Any] | None = None
        self.wev: subprocess.Popen[Any] | None = None
        self.keepalive: subprocess.Popen[Any] | None = None
        self.wev_log = self.logs / "wev.log"

    def _environment(self) -> dict[str, str]:
        path_parts = [
            str(Path(self.args.glib).parent),
            str(Path(self.args.fontconfig).parent),
            str(Path(self.args.coreutils)),
        ]
        for tool in (self.args.grim, self.args.wl_copy, self.args.wl_paste, self.args.cliphist, self.args.wtype):
            path_parts.append(str(Path(tool).parent))
        path_parts.append(os.environ.get("PATH", "/run/current-system/sw/bin"))
        env = {
            "HOME": str(self.root / "home"),
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_DATA_DIRS": str(self.root / "data"),
            "XDG_SESSION_TYPE": "wayland",
            "XDG_CURRENT_DESKTOP": self.compositor,
            "XDG_SESSION_DESKTOP": self.compositor,
            "WLR_BACKENDS": "headless",
            "WLR_RENDERER": "pixman",
            "WLR_LIBINPUT_NO_DEVICES": "1",
            "LIBGL_ALWAYS_SOFTWARE": "1",
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "PATH": ":".join(path_parts),
        }
        return env

    def start(self) -> None:
        if self.compositor == "sway":
            config = self.root / "sway.conf"
            config.write_text(
                "\n".join(
                    [
                        "output HEADLESS-1 mode 1280x800",
                        "output * bg #202124 solid_color",
                        "xwayland disable",
                        "seat seat0 hide_cursor 1000000",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            argv = [self.args.sway, "-c", str(config)]
        else:
            mango_config = self.root / "config" / "mango" / "config.conf"
            mango_config.parent.mkdir(parents=True, exist_ok=True)
            mango_config.write_text("output * bg #202124 solid_color\nxwayland 0\n", encoding="utf-8")
            argv = [self.args.mango, "-c", str(mango_config), "-d"]
        log = (self.logs / f"{self.compositor}.log").open("w", encoding="utf-8")
        self.proc = subprocess.Popen(
            argv,
            env=self.env,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        deadline = time.monotonic() + 20.0
        sockets: list[Path] = []
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"{self.compositor} exited early; see {self.logs}")
            sockets = list((self.root / "runtime").glob("wayland-*"))
            if sockets:
                break
            time.sleep(0.1)
        else:
            raise RuntimeError(f"{self.compositor} did not create a Wayland socket")
        socket = max(sockets, key=lambda path: path.stat().st_mtime_ns)
        self.env["WAYLAND_DISPLAY"] = socket.name
        if self.compositor == "sway":
            ipc_sockets = sorted((self.root / "runtime").glob("sway-ipc.*.sock"))
            if ipc_sockets:
                self.env["SWAYSOCK"] = str(ipc_sockets[-1])
        time.sleep(0.4)
        # A headless seat has no physical keyboard until an injection creates a
        # virtual one. Keep one alive for the whole session so the overlay can
        # bind its wl_keyboard up front, exactly like a real session where a
        # keyboard is always present. Without this the first synthetic key of
        # every wtype invocation races the keyboard bind.
        self.keepalive = subprocess.Popen(
            [self.args.wtype, "-d", "600000", "-k", "Shift_L"],
            env=self.env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        time.sleep(0.8)
        # Start the key-observation toplevel before any overlay exists, like a
        # focused application in a real session. Starting it while overlays are
        # being opened and destroyed makes sway leave the seat without a
        # focus-restore target.
        if self.args.wev:
            log = open(self.wev_log, "w", encoding="utf-8")
            self.wev = subprocess.Popen(
                [self.args.coreutils + "/stdbuf", "-o0", self.args.wev],
                env=self.env,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            deadline = time.monotonic() + 8.0
            while time.monotonic() < deadline:
                text = self.wev_log.read_text(errors="replace")
                if "configure: width: 127" in text or "activated" in text:
                    break
                time.sleep(0.05)
            time.sleep(0.3)

    def run(self, argv: list[str], *, timeout: float = 20.0, check: bool = False, **kwargs: Any) -> subprocess.CompletedProcess[Any]:
        kwargs.setdefault("capture_output", True)
        result = subprocess.run(argv, env={**self.env, **kwargs.pop("extra_env", {})}, timeout=timeout, **kwargs)
        if check and result.returncode != 0:
            raise RuntimeError(f"command failed ({result.returncode}): {' '.join(argv)}")
        return result

    def grim(self, path: Path) -> None:
        result = self.run([self.args.grim, "-o", "HEADLESS-1", str(path)])
        if result.returncode != 0 or not path.exists():
            self.run([self.args.grim, str(path)])
        if not path.exists():
            raise RuntimeError(f"grim failed: {result.stderr.decode(errors='replace')}")

    def stop_wev(self) -> None:
        if self.wev and self.wev.poll() is None:
            self.wev.terminate()
            try:
                self.wev.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.wev.kill()

    def stop(self) -> None:
        self.stop_wev()
        if self.keepalive and self.keepalive.poll() is None:
            self.keepalive.terminate()
            try:
                self.keepalive.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.keepalive.kill()
        if self.proc and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(self.proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                self.proc.wait(timeout=3)
        shutil.rmtree(self.root, ignore_errors=True)

    # ---- clipboard helpers -------------------------------------------------

    def wl_copy(self, data: bytes, mime: str | None = None) -> None:
        argv = [self.args.wl_copy]
        if mime:
            argv += ["--type", mime]
        # wl-copy forks a selection-owner child that keeps every inherited pipe
        # open, so its stdout/stderr must be /dev/null and must not be captured.
        self.run(
            argv,
            input=data,
            check=True,
            capture_output=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def wl_paste(self, mime: str | None = None) -> bytes:
        argv = [self.args.wl_paste]
        if mime:
            argv += ["--type", mime]
        else:
            argv += ["--no-newline"]
        return self.run(argv, check=True).stdout

    def cliphist_store(self) -> None:
        data = self.wl_paste()
        self.run([self.args.cliphist, "store"], input=data, check=True)

    def cliphist_store_mime(self, mime: str) -> None:
        data = self.wl_paste(mime)
        self.run([self.args.cliphist, "store"], input=data, check=True)

    def make_png(self, path: Path, width: int = 160, height: int = 100) -> None:
        image = Image.new("RGB", (width, height), THUMB_RED)
        for x in range(width):
            for y in range(height):
                if x >= width // 2:
                    image.putpixel((x, y), THUMB_GREEN if y < height // 2 else (40, 200, 60))
        image.save(path)


class Overlay:
    def __init__(
        self,
        session: Session,
        args: argparse.Namespace,
        mode: str,
        *,
        extra_args: list[str] | None = None,
        env_overrides: dict[str, str] | None = None,
        socket_name: str = "overlay.sock",
        bin_override: str | None = None,
    ) -> None:
        self.session = session
        self.args = args
        self.mode = mode
        self.socket = session.root / "runtime" / socket_name
        stamp = int(time.time() * 1000)
        self.log = session.logs / f"overlay-{mode}-{stamp}.log"
        self.ready = session.root / "runtime" / f"ready-{mode}-{stamp}.json"
        self.extra_args = extra_args or []
        self.env_overrides = env_overrides or {}
        self.bin_override = bin_override
        self.proc: subprocess.Popen[Any] | None = None
        self.out_path = session.logs / f"overlay-{mode}-{int(time.time() * 1000)}.stdout"

    def binary(self) -> str:
        return self.bin_override or self.args.overlay_bin

    def start(self) -> None:
        env = {**self.session.env, **self.env_overrides}
        argv = [self.binary(), self.mode, "--socket", str(self.socket), "--log", str(self.log), "--ready-file", str(self.ready)]
        if self.args.font:
            argv += ["--font", self.args.font]
        if self.args.font_fallback:
            argv += ["--font-fallback", self.args.font_fallback]
        argv += self.extra_args
        self.out = open(self.out_path, "wb")
        self.proc = subprocess.Popen(argv, env=env, stdout=self.out, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + 20.0
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"overlay exited early ({self.proc.returncode}); output: {self.output_text()}")
            if self.ready.exists():
                return
            time.sleep(0.05)
        raise RuntimeError(f"overlay never became ready; output: {self.output_text()}")

    def output_text(self) -> str:
        if self.out_path.exists():
            return self.out_path.read_text(errors="replace")[-2000:]
        return "<no output>"

    def ctl(self, request: str) -> dict[str, Any]:
        result = self.session.run([self.binary(), "ctl", "--socket", str(self.socket), *request.split(" ")], timeout=10)
        text = result.stdout.decode(errors="replace").strip()
        if not text:
            raise RuntimeError(f"ctl {request!r} returned nothing; stderr={result.stderr.decode(errors='replace')}")
        return json.loads(text)

    def state(self) -> dict[str, Any]:
        return self.ctl("state")

    def wait_exit(self, timeout: float = 10.0) -> int | None:
        assert self.proc is not None
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                return self.proc.returncode
            time.sleep(0.05)
        return None

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(self.proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                self.proc.wait(timeout=3)
        if hasattr(self, "out"):
            self.out.close()

    def log_events(self) -> list[dict[str, Any]]:
        if not self.log.exists():
            return []
        events = []
        for line in self.log.read_text(errors="replace").splitlines():
            line = line.strip()
            if line.startswith("{"):
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
        return events


def finish(overlay: Overlay, timeout: float = 10.0) -> int | None:
    code = overlay.wait_exit(timeout)
    overlay.stop()
    return code


def find_entry(state: dict[str, Any], kind: str, preview_part: str | None = None) -> dict[str, Any] | None:
    for entry in state.get("entries", []):
        if entry.get("kind") != kind:
            continue
        if preview_part is None or preview_part in entry.get("preview", ""):
            return entry
    return None


def row_rect(state: dict[str, Any], index: int) -> tuple[float, float, float, float] | None:
    layout = state.get("layout") or {}
    rows = layout.get("rows") or []
    items = layout.get("row_items") or []
    for position, item in enumerate(items):
        if item == index and position < len(rows):
            row = rows[position]
            return (row["x"], row["y"], row["w"], row["h"])
    return None


def thumb_box(state: dict[str, Any], index: int) -> tuple[int, int, int, int] | None:
    row = row_rect(state, index)
    if row is None:
        return None
    layout = state["layout"]
    card_x = layout["card"]["x"]
    list_x = card_x + 22.0
    box_x = list_x + 12.0
    box_y = row[1] + (row[3] - 56.0) / 2.0
    return (int(box_x), int(box_y), int(box_x + 84), int(box_y + 56))


# --------------------------------------------------------------------------- #
# Sway scenarios
# --------------------------------------------------------------------------- #


def sway_scenarios(session: Session, args: argparse.Namespace, result: Result) -> None:
    session.start()
    shots = session.shots

    # Build a real history through the clipboard protocol, exactly like the
    # cliphist watcher does: copy with wl-copy, read back with wl-paste, store.
    text_old = "mayon overlay text alpha"
    text_new = "second text beta"
    session.wl_copy(text_old.encode() + b"\n")
    time.sleep(0.15)
    session.cliphist_store()
    source_png = session.root / "source.png"
    session.make_png(source_png)
    session.wl_copy(source_png.read_bytes(), "image/png")
    time.sleep(0.15)
    session.cliphist_store_mime("image/png")
    session.wl_copy(text_new.encode() + b"\n")
    time.sleep(0.15)
    session.cliphist_store()
    history = session.run([args.cliphist, "list"], check=True).stdout.decode()
    result.add("sway/history-built", history.count("\n") >= 3, history.replace("\n", " | ")[:200])

    # ---- clipboard UI rendering ------------------------------------------
    overlay = Overlay(session, args, "clipboard", extra_args=["--no-paste"])
    overlay.start()
    state = overlay.state()
    result.add("sway/clipboard-total", state.get("total") == 3, f"total={state.get('total')}")
    image_entry = find_entry(state, "image")
    old_entry = find_entry(state, "text", "alpha")
    new_entry = find_entry(state, "text", "beta")
    result.add("sway/clipboard-image-entry", image_entry is not None, "PNG entry detected from cliphist preview")
    result.add("sway/clipboard-text-entries", old_entry is not None and new_entry is not None, "both text entries visible")
    result.add("sway/clipboard-layout", bool(state.get("layout")), "layout is available for hit testing")

    screenshot = shots / "sway-clipboard.png"
    session.grim(screenshot)
    image = Image.open(screenshot).convert("RGB")
    layout = state.get("layout") or {}
    card = layout.get("card") or {}
    card_box = (
        int(card.get("x", 0)),
        int(card.get("y", 0)),
        int(card.get("x", 0) + card.get("w", 0)),
        int(card.get("y", 0) + card.get("h", 0)),
    )
    backdrop_ok = near(image.getpixel((4, 4)), PALETTE["bg"], 3) and near(image.getpixel((1275, 795)), PALETTE["bg"], 3)
    result.add("sway/render-backdrop", backdrop_ok, f"pixel={image.getpixel((4, 4))} expected={PALETTE['bg']}")
    surface_pixels = count_near(image, card_box, PALETTE["surface"], 4)
    result.add("sway/render-card-surface", surface_pixels > 10000, f"surface pixels={surface_pixels}")
    selected_row = row_rect(state, 0)
    if selected_row:
        sel_box = (int(selected_row[0]), int(selected_row[1]), int(selected_row[0] + selected_row[2]), int(selected_row[1] + selected_row[3]))
        sel_pixels = count_near(image, sel_box, PALETTE["selection"], 4)
        result.add("sway/render-selected-row", sel_pixels > 500, f"selection pixels={sel_pixels}")
    if image_entry is not None:
        box = thumb_box(state, image_entry["index"])
        if box:
            red = count_near(image, box, THUMB_RED, 4)
            green = count_near(image, box, THUMB_GREEN, 4)
            result.add(
                "sway/render-image-thumbnail",
                red > 200 and green > 200,
                f"red={red} green={green} box={box}",
            )
    search_box = (int(card.get("x", 0)) + 22, int(card.get("y", 0)) + 50, int(card.get("x", 0) + card.get("w", 0)) - 22, int(card.get("y", 0)) + 100)
    result.add("sway/render-title-ink", has_ink(image, search_box), "title/search text is rasterised")
    overlay.stop()

    # ---- keyboard navigation + text copy ---------------------------------
    overlay = Overlay(session, args, "clipboard", extra_args=["--no-paste"], socket_name="kbd.sock")
    overlay.start()
    state = overlay.state()
    target = find_entry(state, "text", "alpha")
    assert target is not None
    # Drive the UI with synthetic keys from the compositor: Down twice reaches
    # the oldest text entry, Return copies it.
    session.run([args.wtype, "-k", "Down"], check=True)
    time.sleep(0.2)
    session.run([args.wtype, "-k", "Down"], check=True)
    time.sleep(0.3)
    state = overlay.state()
    result.add("sway/keyboard-moves-selection", state.get("selected") == target["index"], f"selected={state.get('selected')}")
    session.run([args.wtype, "-k", "Return"], check=True)
    code = finish(overlay)
    result.add("sway/keyboard-return-exits", code == 0, f"exit={code}")
    copied = session.wl_paste()
    result.add("sway/keyboard-copy-text", copied.decode(errors="replace").strip() == text_old, copied.decode(errors="replace").strip()[:80])
    events = overlay.log_events()
    result.add("sway/log-copy-event", any(event.get("event") == "copy" for event in events), str(events[-3:])[:300])

    # ---- auto-paste: copy then inject Ctrl+V into the focused wev toplevel --
    overlay = Overlay(session, args, "clipboard", socket_name="paste.sock")
    overlay.start()
    target = find_entry(overlay.state(), "text", "beta")
    assert target is not None
    overlay.ctl(f"activate {target['index']}")
    code = finish(overlay)
    time.sleep(0.8)
    events = overlay.log_events()
    paste_event = next((event for event in events if event.get("event") == "paste"), None)
    result.add(
        "sway/auto-paste-log",
        paste_event is not None and paste_event.get("injected") is True,
        json.dumps(paste_event, ensure_ascii=False) if paste_event else f"no paste event in {events[-4:]}",
    )
    if args.wev:
        wev_text = session.wev_log.read_text(errors="replace")
        injected = "Control" in wev_text and "sym: v" in wev_text
        detail = "wev saw Control + v"
        if not injected:
            detail = wev_text[-500:]
            tree = session.run(
                [str(Path(args.sway).parent / "swaymsg"), "-t", "get_tree"], timeout=5
            )
            if tree.returncode == 0:
                detail += "\ntree: " + tree.stdout.decode(errors="replace")[-1200:]
        result.add("sway/auto-paste-observed", injected, detail)
    result.add("sway/auto-paste-text", session.wl_paste().decode(errors="replace").strip() == text_new, "clipboard holds the selected text")

    # ---- image copy -------------------------------------------------------
    overlay = Overlay(session, args, "clipboard", extra_args=["--no-paste"], socket_name="image.sock")
    overlay.start()
    state = overlay.state()
    image_entry = find_entry(state, "image")
    assert image_entry is not None
    overlay.ctl(f"activate {image_entry['index']}")
    code = finish(overlay)
    result.add("sway/image-copy-exits", code == 0, f"exit={code}")
    copied_png = session.wl_paste("image/png")
    decoded_path = session.root / "copied.png"
    decoded_path.write_bytes(copied_png)
    try:
        expected = Image.open(source_png).convert("RGB")
        actual = Image.open(decoded_path).convert("RGB")
        from PIL import ImageChops

        same = actual.size == expected.size and ImageChops.difference(expected, actual).getbbox() is None
        result.add("sway/image-copy-pixels", same, f"size={actual.size}")
    except Exception as error:  # noqa: BLE001
        result.add("sway/image-copy-pixels", False, f"cannot decode copied PNG: {error}")

    # ---- launcher: search by keyboard, Enter launches --------------------
    apps_dir = session.root / "data" / "applications"
    apps_dir.mkdir(parents=True, exist_ok=True)
    marker_one = session.root / "launched-one.txt"
    marker_two = session.root / "launched-two.txt"
    target_script = session.root / "launch-target.sh"
    target_script.write_text(
        f"#!{args.shell}\n"
        f'printf "one launched\\n" > "{marker_one}"\n',
        encoding="utf-8",
    )
    target_script.chmod(0o755)
    second_script = session.root / "launch-second.sh"
    second_script.write_text(
        f"#!{args.shell}\n"
        f'printf "two launched\\n" > "{marker_two}"\n',
        encoding="utf-8",
    )
    second_script.chmod(0o755)
    (apps_dir / "mayon-smoke-target.desktop").write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=Mayon Smoke Target\n"
        "GenericName=Overlay launcher target\n"
        "Comment=Writes a marker file from the desktop entry Exec line\n"
        f"Exec={target_script}\n"
        "Icon=utilities-terminal\n"
        "Terminal=false\n"
        "Categories=Utility;Development;\n"
        "Keywords=smoke;overlay;mayon;\n",
        encoding="utf-8",
    )
    (apps_dir / "mayon-smoke-second.desktop").write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=Mayon Smoke Second\n"
        "GenericName=Another launcher entry\n"
        f"Exec={second_script}\n"
        "Terminal=false\n"
        "Categories=System;\n"
        "Keywords=running;second;\n",
        encoding="utf-8",
    )
    overlay = Overlay(session, args, "launcher", extra_args=["--data-dir", str(session.root / "data")], socket_name="launch.sock")
    overlay.start()
    state = overlay.state()
    result.add("sway/launcher-index", state.get("total") == 2, f"total={state.get('total')}")
    screenshot = shots / "sway-launcher.png"
    session.grim(screenshot)
    image = Image.open(screenshot).convert("RGB")
    layout = state.get("layout") or {}
    rows = layout.get("rows") or []
    if rows:
        first_row = rows[0]
        row_box = (int(first_row["x"]), int(first_row["y"]), int(first_row["x"] + first_row["w"]), int(first_row["y"] + first_row["h"]))
        # Icon launchers paint a coloured glyph in the left gutter. This
        # launcher only has the 3px accent bar at x+6..9 (a selection marker,
        # not an icon), so the rest of the gutter must be colour-free and the
        # row must still contain text ink.
        gutter_box = (row_box[0] + 12, row_box[1] + 4, row_box[0] + 40, row_box[3] - 4)
        colourful_pixels = sum(
            1 for pixel in image.crop(gutter_box).convert("RGB").getdata() if colorful(pixel, 24)
        )
        accent_pixels = count_near(image, row_box, PALETTE["blue"], 6)
        result.add(
            "sway/launcher-no-icons",
            colourful_pixels == 0 and accent_pixels > 40,
            f"coloured gutter pixels={colourful_pixels} blue accent pixels={accent_pixels} (accent is the selection bar)",
        )
        result.add("sway/launcher-row-ink", has_ink(image, row_box), "application names are rasterised")
    session.run([args.wtype, "target"], check=True)
    deadline = time.monotonic() + 5.0
    query_state: dict[str, Any] = {}
    while time.monotonic() < deadline:
        query_state = overlay.state()
        if query_state.get("query") == "target":
            break
        time.sleep(0.1)
    result.add("sway/launcher-keyboard-query", query_state.get("query") == "target", f"query={query_state.get('query')!r}")
    result.add("sway/launcher-filter", query_state.get("total") == 1, f"total={query_state.get('total')}")
    session.grim(shots / "sway-launcher-query.png")
    session.run([args.wtype, "-k", "Return"], check=True)
    code = finish(overlay)
    time.sleep(0.8)
    result.add("sway/launcher-keyboard-enter", code == 0 and marker_one.exists(), f"exit={code} marker={marker_one.exists()}")
    events = overlay.log_events()
    launch_event = next((event for event in events if event.get("event") == "launch"), None)
    result.add("sway/launcher-log", launch_event is not None and launch_event.get("ok") is True, json.dumps(launch_event, ensure_ascii=False) if launch_event else "missing")

    # ---- Escape dismiss ---------------------------------------------------
    overlay = Overlay(session, args, "launcher", extra_args=["--data-dir", str(session.root / "data")], socket_name="escape.sock")
    overlay.start()
    session.run([args.wtype, "-k", "Escape"], check=True)
    code = finish(overlay)
    events = overlay.log_events()
    result.add("sway/keyboard-escape", code == 0 and any(event.get("event") == "close" for event in events), f"exit={code}")

    # ---- simulated click activates a row ---------------------------------
    overlay = Overlay(session, args, "launcher", extra_args=["--data-dir", str(session.root / "data")], socket_name="click.sock")
    overlay.start()
    state = overlay.state()
    second = find_entry(state, "app", "Second")
    assert second is not None
    rect = row_rect(state, second["index"])
    assert rect is not None
    reply = overlay.ctl(f"click {rect[0] + rect[2] / 2} {rect[1] + rect[3] / 2}")
    code = finish(overlay)
    time.sleep(0.8)
    result.add(
        "sway/click-activates",
        reply.get("action") == "launch" and reply.get("result_ok") is True and code == 0 and marker_two.exists(),
        f"reply={reply} marker={marker_two.exists()}",
    )

    # ---- toggle: second invocation closes the running overlay ------------
    overlay = Overlay(session, args, "launcher", extra_args=["--data-dir", str(session.root / "data")], socket_name="toggle.sock")
    overlay.start()
    second_run = session.run([args.overlay_bin, "launcher", "--socket", str(overlay.socket), "--data-dir", str(session.root / "data")], timeout=10)
    code = finish(overlay)
    result.add(
        "sway/single-instance-toggle",
        second_run.returncode == 0 and code == 0,
        f"second exit={second_run.returncode} first exit={code}",
    )

    # ---- degraded paste when wtype is unavailable ------------------------
    unwrapped = args.overlay_unwrapped
    if unwrapped and Path(unwrapped).exists():
        degrade_path = ":".join(
            [
                str(Path(args.wl_copy).parent),
                str(Path(args.cliphist).parent),
                str(Path(args.glib).parent),
                str(Path(args.fontconfig).parent),
                args.coreutils,
                "/run/current-system/sw/bin",
            ]
        )
        # Use the unwrapped binary so the wrapper's PATH cannot re-add wtype.
        overlay = Overlay(
            session,
            args,
            "clipboard",
            socket_name="degrade.sock",
            extra_args=["--paste-keys", "ctrl+v"],
            bin_override=unwrapped,
            env_overrides={"PATH": degrade_path},
        )
        overlay.start()
        state = overlay.state()
        target = find_entry(state, "text", "beta") or find_entry(state, "text")
        assert target is not None
        overlay.ctl(f"activate {target['index']}")
        code = finish(overlay)
        time.sleep(0.5)
        events = overlay.log_events()
        failed = next((event for event in events if event.get("event") == "paste_failed"), None)
        notify = next((event for event in events if event.get("event") == "notify"), None)
        result.add(
            "sway/degraded-copy-and-notify",
            code == 0 and failed is not None and notify is not None and session.wl_paste().decode(errors="replace").strip() == text_new,
            f"paste_failed={json.dumps(failed)[:160]} notify={json.dumps(notify)[:120]}",
        )
    else:
        result.add("sway/degraded-copy-and-notify", False, "unwrapped binary not provided")

    session.stop()


# --------------------------------------------------------------------------- #
# Mango scenario
# --------------------------------------------------------------------------- #


def mango_scenarios(session: Session, args: argparse.Namespace, result: Result) -> None:
    session.start()
    shots = session.shots
    globals_path = session.logs / "wayland-info.txt"
    info = session.run([args.wayland_info], check=True).stdout.decode(errors="replace")
    globals_path.write_text(info, encoding="utf-8")
    has_virtual_keyboard = "zwp_virtual_keyboard_manager_v1" in info
    has_layer_shell = "zwlr_layer_shell_v1" in info
    result.add("mango/virtual-keyboard-global", has_virtual_keyboard, "zwp_virtual_keyboard_manager_v1 advertised")
    result.add("mango/layer-shell-global", has_layer_shell, "zwlr_layer_shell_v1 advertised")

    # Real copy history and an auto-paste target.
    text = "mango auto paste target 你好"
    session.wl_copy(text.encode())
    time.sleep(0.2)
    session.cliphist_store()
    overlay = Overlay(session, args, "clipboard", socket_name="mango-paste.sock")
    overlay.start()
    state = overlay.state()
    target = find_entry(state, "text", "mango")
    result.add("mango/overlay-runs", target is not None, f"total={state.get('total')}")
    screenshot = shots / "mango-clipboard.png"
    session.grim(screenshot)
    image = Image.open(screenshot).convert("RGB")
    layout = state.get("layout") or {}
    card = layout.get("card") or {}
    card_box = (
        int(card.get("x", 0)),
        int(card.get("y", 0)),
        int(card.get("x", 0) + card.get("w", 0)),
        int(card.get("y", 0) + card.get("h", 0)),
    )
    surface_pixels = count_near(image, card_box, PALETTE["surface"], 4)
    result.add("mango/render-card", surface_pixels > 5000, f"surface pixels={surface_pixels} size={image.size}")
    corners = [(4, 4), (image.width - 5, 4), (4, image.height - 5), (image.width - 5, image.height - 5)]
    backdrop_ok = all(near(image.getpixel(point), PALETTE["bg"], 3) for point in corners)
    result.add(
        "mango/render-backdrop",
        backdrop_ok,
        f"corners={[image.getpixel(point) for point in corners]}",
    )
    if target is not None:
        overlay.ctl(f"activate {target['index']}")
        code = finish(overlay)
        time.sleep(0.9)
        events = overlay.log_events()
        paste_event = next((event for event in events if event.get("event") == "paste"), None)
        result.add(
            "mango/auto-paste-log",
            code == 0 and paste_event is not None and paste_event.get("injected") is True,
            json.dumps(paste_event, ensure_ascii=False) if paste_event else f"exit={code} events={events[-4:]}",
        )
        if args.wev:
            wev_text = session.wev_log.read_text(errors="replace")
            result.add("mango/auto-paste-observed", "Control" in wev_text and "sym: v" in wev_text, wev_text[-400:])
        result.add("mango/clipboard-content", session.wl_paste().decode(errors="replace").strip() == text, "clipboard holds the selected text")

    # Launcher also has to run under Mango's layer-shell v4.
    apps_dir = session.root / "data" / "applications"
    apps_dir.mkdir(parents=True, exist_ok=True)
    marker = session.root / "mango-launched.txt"
    script = session.root / "mango-target.sh"
    script.write_text(
        f"#!{args.shell}\n" f'printf "mango launched\\n" > "{marker}"\n',
        encoding="utf-8",
    )
    script.chmod(0o755)
    (apps_dir / "mayon-mango-target.desktop").write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=Mayon Mango Target\n"
        "GenericName=Launcher under Mango\n"
        f"Exec={script}\n"
        "Terminal=false\n"
        "Categories=Utility;\n"
        "Keywords=mango;target;\n",
        encoding="utf-8",
    )
    overlay = Overlay(session, args, "launcher", extra_args=["--data-dir", str(session.root / "data")], socket_name="mango-launch.sock")
    overlay.start()
    state = overlay.state()
    entry = find_entry(state, "app", "Mango")
    result.add("mango/launcher-runs", entry is not None, f"total={state.get('total')}")
    if entry is not None:
        overlay.ctl(f"activate {entry['index']}")
        code = finish(overlay)
        time.sleep(0.8)
        events = overlay.log_events()
        launch_event = next((event for event in events if event.get("event") == "launch"), None)
        result.add(
            "mango/launcher-launch",
            code == 0 and marker.exists() and launch_event is not None and launch_event.get("ok") is True,
            f"exit={code} marker={marker.exists()} event={json.dumps(launch_event, ensure_ascii=False)[:200]}",
        )
    session.grim(shots / "mango-launcher.png")
    session.stop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overlay-bin", required=True, help="wrapped mayon-overlay executable")
    parser.add_argument("--overlay-unwrapped", help="unwrapped executable (for the degraded-paste check)")
    parser.add_argument("--sway", help="sway executable")
    parser.add_argument("--mango", help="mango executable")
    parser.add_argument("--grim", required=True)
    parser.add_argument("--wl-copy", required=True, dest="wl_copy")
    parser.add_argument("--wl-paste", required=True, dest="wl_paste")
    parser.add_argument("--cliphist", required=True)
    parser.add_argument("--wtype", required=True)
    parser.add_argument("--wev")
    parser.add_argument("--wayland-info", dest="wayland_info")
    parser.add_argument("--glib", required=True, help="gio executable")
    parser.add_argument("--fontconfig", required=True, help="fc-match executable")
    parser.add_argument("--coreutils", required=True, help="coreutils bin directory")
    parser.add_argument("--font", help="UI font file")
    parser.add_argument("--font-fallback", dest="font_fallback", help="fallback font file")
    parser.add_argument("--shell", default="/bin/sh", help="interpreter for generated test launch targets (runtimeShell inside Nix builds)")
    parser.add_argument("--out", required=True, help="output directory for screenshots, logs and metrics.json")
    parser.add_argument("--only", choices=["sway", "mango"], help="run a single compositor scenario")
    args = parser.parse_args()

    out = Path(args.out).resolve()
    args.out = str(out)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    result = Result()

    if args.sway and args.only != "mango":
        session = Session(args, result, "sway")
        try:
            sway_scenarios(session, args, result)
        except Exception as error:  # noqa: BLE001
            result.add("sway/scenario", False, f"uncaught error: {error}")
            import traceback

            traceback.print_exc()
        finally:
            session.stop()
    if args.mango and args.only != "sway":
        session = Session(args, result, "mango")
        try:
            mango_scenarios(session, args, result)
        except Exception as error:  # noqa: BLE001
            result.add("mango/scenario", False, f"uncaught error: {error}")
            import traceback

            traceback.print_exc()
        finally:
            session.stop()

    metrics = {
        "checks": result.checks,
        "failures": result.failures,
        "ok": not result.failures,
        "out": str(out),
    }
    (out / "metrics.json").write_text(json.dumps(metrics, indent=2, ensure_ascii=False), encoding="utf-8")
    print()
    print(f"{len(result.checks) - len(result.failures)}/{len(result.checks)} checks passed; metrics: {out / 'metrics.json'}")
    return 0 if not result.failures else 1


if __name__ == "__main__":
    sys.exit(main())
