"""Transactional, serialized GameMode first/last-client hooks (per user)."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time

UNIT = "gaming-idle-inhibit.service"
PROFILES = {"power-saver", "balanced", "performance"}


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True, timeout=15).stdout.strip()


def save(path, data):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data))
    temporary.replace(path)


def restore(path, state):
    # Always release our own inhibitor, even if PPD has gone away. Keep a retry
    # record on restoration failure rather than losing the user's old choice.
    state["active"] = False
    save(path, state)
    errors = []
    if state.get("profile"):
        try:
            run("powerprofilesctl", "set", state["profile"])
        except (OSError, subprocess.SubprocessError) as error:
            errors.append(error)
    try:
        run("systemctl", "--user", "stop", UNIT)
    except (OSError, subprocess.SubprocessError) as error:
        errors.append(error)
    if errors:
        raise RuntimeError("restoration pending: " + "; ".join(map(str, errors)))
    path.unlink(missing_ok=True)


def main():
    action = sys.argv[1] if len(sys.argv) == 2 else ""
    if action not in {"start", "end"}:
        sys.exit("usage: gaming-mode-hook start|end")
    root = Path(os.environ["XDG_RUNTIME_DIR"]) / "gaming-mode"
    root.mkdir(mode=0o700, exist_ok=True)
    with (root / "lock").open("a") as lock:
        deadline = time.monotonic() + 10
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("another GameMode hook still holds the lock")
                time.sleep(0.05)
        path = root / "state.json"
        state = json.loads(path.read_text()) if path.exists() else None
        if action == "end":
            if state:
                restore(path, state)
            return
        if state:
            if state.get("active"):
                return
            restore(path, state)
        profile = run("powerprofilesctl", "get")
        if profile not in PROFILES:
            raise RuntimeError("unexpected power profile: " + profile)
        state = {"profile": profile, "active": False}
        # Journal before either side effect; ExecStopPost can recover a killed hook.
        save(path, state)
        try:
            run("systemctl", "--user", "start", UNIT)
            run("powerprofilesctl", "set", "performance")
            state["active"] = True
            save(path, state)
        except (OSError, subprocess.SubprocessError):
            restore(path, state)
            raise


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"gaming-mode-hook: {error}", file=sys.stderr)
        sys.exit(1)
