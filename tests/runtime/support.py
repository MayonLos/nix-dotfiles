"""Shared support for the runtime E2E suite.

Standard library only. External commands are looked up on PATH or via the
NixOS system profile so the suite works both from a plain login shell and from
an isolated shell that only has /run/current-system/sw/bin.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

SYSTEM_PATH = "/run/current-system/sw/bin"
USER_PROFILE_PATH = os.path.expanduser("~/.nix-profile/bin")
EXTRA_PATHS = [SYSTEM_PATH, USER_PROFILE_PATH, "/run/wrappers/bin", "/usr/bin", "/bin"]

STATUS_PASS = "PASS"
STATUS_FAIL = "FAIL"
STATUS_SKIP = "SKIP"

# Palette from aspects/appearance/appearance/onedark.nix. Parsed at runtime
# from the repository so a palette edit is reflected without touching the
# suite; these values are only the fallback when the source cannot be read.
PALETTE_FALLBACK = {
    "black": "#0e1013",
    "bg": "#1e2228",
    "surface": "#272c33",
    "selection": "#323843",
    "border": "#5c6370",
    "deep": "#181b20",
    "fg": "#abb2bf",
    "muted": "#828a95",
    "purple": "#c678dd",
    "green": "#98c379",
    "orange": "#d19a66",
    "blue": "#61afef",
    "yellow": "#e5c07b",
    "cyan": "#56b6c2",
    "red": "#e06c75",
    "brightFg": "#d7dae0",
}


def which(name: str) -> str | None:
    """Resolve an executable, preferring the user profile then the system."""
    found = shutil.which(name)
    if found:
        return found
    for base in EXTRA_PATHS:
        candidate = Path(base) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    found = shutil.which(name, path=os.pathsep.join(EXTRA_PATHS))
    return found


def child_env(extra: dict[str, str] | None = None, base: dict[str, str] | None = None) -> dict[str, str]:
    env = dict(base if base is not None else os.environ)
    path_parts = [p for p in env.get("PATH", "").split(os.pathsep) if p]
    for part in EXTRA_PATHS:
        if part not in path_parts and Path(part).is_dir():
            path_parts.append(part)
    env["PATH"] = os.pathsep.join(path_parts)
    if extra:
        env.update(extra)
    return env


@dataclass
class CommandResult:
    argv: list[str]
    returncode: int
    stdout: str
    stderr: str
    duration: float
    timed_out: bool = False

    @property
    def ok(self) -> bool:
        return self.returncode == 0 and not self.timed_out

    def json(self):
        if not self.stdout.strip():
            return None
        return json.loads(self.stdout)


@dataclass
class Result:
    status: str
    detail: str = ""
    expected: str | None = None
    observed: str | None = None
    artifacts: list[str] = field(default_factory=list)
    data: dict = field(default_factory=dict)
    duration: float = 0.0

    @classmethod
    def passed(cls, detail: str = "", **kwargs) -> "Result":
        return cls(STATUS_PASS, detail=detail, **kwargs)

    @classmethod
    def failed(cls, detail: str, **kwargs) -> "Result":
        return cls(STATUS_FAIL, detail=detail, **kwargs)

    @classmethod
    def skipped(cls, reason: str, **kwargs) -> "Result":
        return cls(STATUS_SKIP, detail=reason, **kwargs)


class TestFailure(Exception):
    """Raised by helpers when a check conclusively fails."""


class SkipTest(Exception):
    """Raised when the environment cannot provide the tested surface."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


class Ctx:
    """Per-run context: paths, command logging, cached session probes."""

    def __init__(self, repo_root: Path, artifact_dir: Path, verbose: bool = False):
        self.repo_root = repo_root
        self.artifact_dir = artifact_dir
        self.verbose = verbose
        self.log_path = artifact_dir / "commands.log"
        self.commands: list[dict] = []
        self._cache: dict[str, object] = {}
        self.artifact_dir.mkdir(parents=True, exist_ok=True)

    # -- command execution -------------------------------------------------
    def exec(
        self,
        argv: list[str],
        *,
        timeout: float = 15.0,
        env: dict[str, str] | None = None,
        cwd: Path | None = None,
        check: bool = False,
        label: str | None = None,
    ) -> CommandResult:
        resolved = list(argv)
        binary = which(argv[0]) if "/" not in argv[0] else None
        if binary:
            resolved[0] = binary
        started = time.monotonic()
        timed_out = False
        try:
            proc = subprocess.run(
                resolved,
                capture_output=True,
                text=True,
                errors="replace",
                timeout=timeout,
                env=child_env(env),
                cwd=str(cwd or self.repo_root),
                stdin=subprocess.DEVNULL,
            )
            returncode = proc.returncode
            stdout, stderr = proc.stdout, proc.stderr
        except subprocess.TimeoutExpired as exc:
            timed_out = True
            returncode = -9
            stdout = (exc.stdout or "") if isinstance(exc.stdout, str) else ""
            stderr = (exc.stderr or "") if isinstance(exc.stderr, str) else ""
        except FileNotFoundError as exc:
            returncode = 127
            stdout, stderr = "", f"{exc}"
        duration = time.monotonic() - started
        result = CommandResult(
            resolved, returncode, stdout, stderr, duration, timed_out=timed_out
        )
        self.record_command(result, label)
        if check and not result.ok:
            raise TestFailure(
                f"命令失败: {' '.join(resolved)} (exit {result.returncode})\n"
                f"{result.stderr.strip()[:600]}"
            )
        return result

    def record_command(self, result: CommandResult, label: str | None) -> None:
        summary = {
            "label": label,
            "argv": result.argv,
            "exit": result.returncode,
            "timed_out": result.timed_out,
            "duration_s": round(result.duration, 3),
            "stdout": result.stdout[:4000],
            "stderr": result.stderr[:4000],
        }
        self.commands.append(summary)
        status = "TIMEOUT" if result.timed_out else f"exit={result.returncode}"
        with self.log_path.open("a", encoding="utf-8") as handle:
            handle.write(f"$ {' '.join(result.argv)}  ({status})\n")
            if result.stdout.strip():
                handle.write(result.stdout[-4000:] + "\n")
            if result.stderr.strip():
                handle.write("STDERR: " + result.stderr[-4000:] + "\n")

    # -- artifacts ---------------------------------------------------------
    def artifact(self, category: str, name: str) -> Path:
        directory = self.artifact_dir / category
        directory.mkdir(parents=True, exist_ok=True)
        return directory / name

    def write_text(self, category: str, name: str, text: str) -> Path:
        path = self.artifact(category, name)
        path.write_text(text, encoding="utf-8")
        return path

    def tmpdir(self) -> Path:
        root = Path("/tmp") / f"runtime-e2e-{uuid.uuid4().hex[:10]}"
        root.mkdir(parents=True, exist_ok=True)
        os.chmod(root, 0o700)
        return root

    # -- repository / palette ---------------------------------------------
    def palette(self) -> dict[str, str]:
        if "palette" in self._cache:
            return self._cache["palette"]  # type: ignore[return-value]
        values = dict(PALETTE_FALLBACK)
        source = self.repo_root / "aspects/appearance/appearance/onedark.nix"
        try:
            text = source.read_text(encoding="utf-8")
            for key in PALETTE_FALLBACK:
                match = re.search(
                    r'^\s*' + re.escape(key) + r'\s*=\s*"(#[0-9a-fA-F]{6})"\s*;',
                    text,
                    re.MULTILINE,
                )
                if match:
                    values[key] = match.group(1)
            values["_source"] = str(source) if source.is_file() else "fallback"
        except OSError:
            values["_source"] = "fallback"
        self._cache["palette"] = values
        return values

    # -- live session probes ----------------------------------------------
    def wayland_env(self) -> tuple[dict[str, str], str]:
        """Return an env for the live Wayland session and a skip reason."""
        env = dict(os.environ)
        display = env.get("WAYLAND_DISPLAY")
        runtime = env.get("XDG_RUNTIME_DIR")
        if not display:
            return env, "当前进程没有 WAYLAND_DISPLAY（不在 live 图形会话内）"
        if not runtime:
            return env, "当前进程没有 XDG_RUNTIME_DIR"
        if not (Path(runtime) / display).exists():
            return env, f"WAYLAND_DISPLAY={display} 在 {runtime} 下不存在"
        if not which("mmsg"):
            return env, "找不到 mmsg（不在 Mango 会话内）"
        return env, ""

    def live_ready(self) -> bool:
        return not self.wayland_env()[1]

    def mmsg(self, *args: str, timeout: float = 10.0) -> dict:
        result = self.exec(["mmsg", *args], timeout=timeout, label="mmsg " + " ".join(args))
        if not result.ok:
            raise TestFailure(f"mmsg {' '.join(args)} 失败: {result.stderr.strip()[:300]}")
        try:
            payload = json.loads(result.stdout.strip().splitlines()[-1])
        except (ValueError, IndexError) as exc:
            raise TestFailure(f"mmsg {' '.join(args)} 返回无法解析: {result.stdout[:300]}") from exc
        return payload

    def monitor(self) -> dict:
        if "monitor" not in self._cache:
            payload = self.mmsg("get", "all-monitors")
            monitors = payload.get("monitors") or []
            active = [m for m in monitors if m.get("active")]
            if not active:
                raise TestFailure("没有活动显示器")
            self._cache["monitor"] = active[0]
        return self._cache["monitor"]  # type: ignore[return-value]

    def focused_client(self) -> dict | None:
        if "focused" not in self._cache:
            payload = self.mmsg("get", "focusing-client")
            client = payload.get("id")
            self._cache["focused"] = payload if client is not None else None
        return self._cache["focused"]  # type: ignore[return-value]

    def layers(self) -> list[dict]:
        payload = self.mmsg("get", "all-layers")
        return payload.get("layers") or []

    def output_name(self) -> str:
        return str(self.monitor().get("name"))

    def scale(self) -> float:
        return float(self.monitor().get("scale") or 1.0)

    def logical_size(self) -> tuple[float, float]:
        monitor = self.monitor()
        scale = float(monitor.get("scale") or 1.0)
        return float(monitor["width"]), float(monitor["height"])

    # -- live screenshots --------------------------------------------------
    def screenshot(self, category: str, name: str, output: str | None = None) -> tuple[Path, tuple[int, int]]:
        from . import pixels  # local import keeps support import-light

        grim = which("grim")
        if not grim:
            raise TestFailure("找不到 grim")
        path = self.artifact(category, name)
        result = self.exec(
            [grim, "-o", output or self.output_name(), str(path)],
            timeout=20.0,
            label=f"grim {name}",
        )
        if not result.ok:
            raise TestFailure(f"grim 截图失败: {result.stderr.strip()[:300]}")
        size = pixels.image_size(path)
        recorded = self.artifact(category, "screenshots.jsonl")
        with recorded.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({"name": name, "path": str(path), "size": size}) + "\n")
        return path, size

    # -- generic helpers ---------------------------------------------------
    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)

    def wait_until(self, predicate, timeout: float, interval: float = 0.1) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if predicate():
                    return True
            except Exception:
                pass
            time.sleep(interval)
        return False


def read_json_file(path: Path):
    text = path.read_text(encoding="utf-8")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # mangobar writes JSONC; strip // comments conservatively.
        stripped = re.sub(r"(?m)^\s*//.*$", "", text)
        return json.loads(stripped)


def parse_kv_config(path: Path) -> dict[str, str]:
    """Parse mako-style key=value config (last value wins)."""
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


def parse_simple_toml(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    section = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if "=" in line:
            key, _, value = line.partition("=")
            full = f"{section}.{key.strip()}" if section else key.strip()
            values[full] = value.strip().strip('"')
    return values


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


def fmt(value) -> str:
    if isinstance(value, float):
        return f"{value:.2f}"
    return str(value)
