"""Exercise generated CLI configuration in an isolated build HOME and tmux socket."""
import json
import os
import pathlib
import pty
import re
import select
import struct
import shutil
import signal
import subprocess
import sys
import termios
import fcntl
import time
import tomllib

settings = json.loads(pathlib.Path(sys.argv[1]).read_text())
out = pathlib.Path(sys.argv[2])


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout


# Native Starship parsing and output, including a real untracked-file count.
env = os.environ.copy()
# TUI fixtures must not reach the real desktop clipboard or session bus.
env.update(DISPLAY="", WAYLAND_DISPLAY="", DBUS_SESSION_BUS_ADDRESS="unix:path=" + os.environ["TMPDIR"] + "/no-session-bus")
env["TERMINFO_DIRS"] = os.pathsep.join(settings["terminfoDirs"])
for name in ("SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY", "IN_NIX_SHELL"):
    env.pop(name, None)
env["PATH"] = str(pathlib.Path(settings["git"]).parent) + os.pathsep + env["PATH"]
env.update(STARSHIP_CONFIG=settings["starshipConfig"], STARSHIP_LOG="error", TERM="xterm-256color")
repo = pathlib.Path(os.environ["TMPDIR"]) / "prompt-fixture"
repo.mkdir()
env["PWD"] = str(repo)
env.pop("NO_COLOR", None)
env["YAZI_CONFIG_HOME"] = os.environ["XDG_CONFIG_HOME"] + "/yazi"
run(settings["git"], "init", "--initial-branch=fixture", str(repo))
(repo / "untracked.txt").write_text("fixture\n")
ansi = re.compile(r"\x1b\[[0-9;]*m")


def prompt(duration=5000, **changes):
    result = subprocess.run(
        [settings["starship"], "prompt", "--status=42", f"--cmd-duration={duration}", "--terminal-width=120"],
        cwd=repo, env=env | changes, check=True, capture_output=True, text=True,
    )
    assert not result.stderr, result.stderr
    return ansi.sub("", result.stdout)


normal = prompt()
assert normal.count("\n") == 1 and "❯" in normal, repr(normal)
assert "42" in normal and "?1" in normal, repr(normal)
if os.geteuid() != 0:
    assert "@" not in normal, repr(normal)
slow = prompt(duration=12000)
assert "· 12s" in slow, repr(slow)
starship_config = tomllib.loads(pathlib.Path(settings["starshipConfig"]).read_text())
assert starship_config["cmd_duration"]["min_time"] == 3000
assert "· $duration" in starship_config["cmd_duration"]["format"]
ssh = prompt(SSH_CONNECTION="127.0.0.1 22 127.0.0.2 2222")
assert "@" in ssh, repr(ssh)
nix = prompt(IN_NIX_SHELL="impure")
assert "❄" in nix and "impure" in nix, repr(nix)
(out / "starship.txt").write_text(normal + "\nSSH: " + ssh + "\nNix: " + nix)

# Use a real attached client so root-table key dispatch and client_prefix are
# exercised; this socket is created by the surrounding runtime derivation.
socket = os.environ["TMPDIR"] + "/tmux.sock"


def tmux(*args):
    return run(settings["tmux"], "-S", socket, *args).strip()


master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 120, 0, 0))
client = subprocess.Popen(
    [settings["tmux"], "-S", socket, "attach-session", "-t", "validate"],
    stdin=slave, stdout=slave, stderr=slave, env=env,
)
os.close(slave)


def settle():
    # Drain terminal output to avoid blocking the tmux client.
    until = time.monotonic() + 0.2
    while time.monotonic() < until:
        if select.select([master], [], [], 0.02)[0]:
            os.read(master, 65536)


def press(keys):
    os.write(master, keys)
    settle()


def status():
    return tmux("display-message", "-p", "#{E:status-right}")


def check_terminal_usstyle(term):
    session = "usstyle-" + term
    tmux("new-session", "-d", "-s", session, "-n", "Focused", "sleep", "30")
    client_master, client_slave = pty.openpty()
    fcntl.ioctl(client_slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
    client_env = env | {"TERM": term, "TMUX": "", "TMUX_PANE": ""}
    terminal_client = subprocess.Popen(
        [settings["tmux"], "-S", socket, "attach-session", "-t", session],
        stdin=client_slave, stdout=client_slave, stderr=client_slave, env=client_env,
    )
    os.close(client_slave)
    captured = bytearray()
    try:
        deadline = time.monotonic() + 2
        features = None
        red, green, blue = bytes.fromhex(settings["tmuxUnderlineColor"].removeprefix("#"))
        blue_underline = b"\x1b[58:2:" + b":".join(str(value).encode() for value in (red, green, blue)) + b"m"
        while time.monotonic() < deadline:
            if select.select([client_master], [], [], 0.05)[0]:
                try:
                    captured.extend(os.read(client_master, 65536))
                except OSError:
                    break
            clients = tmux("list-clients", "-F", "#{client_pid}|#{client_termname}|#{client_termfeatures}")
            for row in clients.splitlines():
                pid, client_term, client_features = row.split("|", 2)
                if pid == str(terminal_client.pid):
                    assert client_term == term, (term, row)
                    features = client_features.split(",")
                    break
            if features is None and terminal_client.poll() is not None:
                break
            if features is not None and blue_underline in captured:
                break
        assert features is not None, (
            term,
            "attached tmux client not found",
            f"returncode={terminal_client.poll()}",
            f"captured={bytes(captured)!r}",
        )
        assert "usstyle" in features, (term, features)
        assert blue_underline in captured, (term, blue_underline, bytes(captured))
        return f"{term}: usstyle negotiated; blue SGR underline {blue_underline!r}"
    finally:
        terminal_client.terminate()
        terminal_client.wait(timeout=5)
        os.close(client_master)
        tmux("kill-session", "-t", session)


try:
    settle()
    underline_results = [
        check_terminal_usstyle("xterm-kitty"),
        check_terminal_usstyle("tmux-256color"),
    ]
    active_format = tmux("show-window-option", "-gv", "window-status-current-format")
    assert active_format == settings["tmuxCurrentFormat"], active_format
    assert "underscore" in active_format and "#[bg=" not in active_format, active_format
    tmux("split-window", "-h", "-t", "validate", "-c", str(repo))
    panes = tmux("list-panes", "-F", "#{pane_id}").splitlines()
    left, right = panes
    tmux("select-pane", "-t", right)
    press(b"\x08")  # Ctrl+h selects the left tmux pane.
    assert tmux("display-message", "-p", "#{pane_id}") == left
    tmux("set-option", "-p", "-t", left, "@pane-is-vim", "1")
    press(b"\x0c")  # Ctrl+l is forwarded instead of changing panes.
    assert tmux("display-message", "-p", "#{pane_id}") == left
    before = tmux("display-message", "-p", "#{pane_width}")
    press(b"\x1bl")
    assert tmux("display-message", "-p", "#{pane_width}") == before
    tmux("set-option", "-pu", "-t", left, "@pane-is-vim")
    press(b"\x1bl")  # Alt+l grows a non-Neovim pane.
    assert int(tmux("display-message", "-p", "#{pane_width}")) == int(before) + 3
    press(b"\x01")
    prefix = status()
    assert "PREFIX" in prefix, prefix
    tmux("switch-client", "-T", "root")
    settle()
    tmux("copy-mode")
    copy = status()
    assert "COPY" in copy, copy
    tmux("send-keys", "-X", "cancel")
    tmux("resize-pane", "-Z")
    zoom = status()
    assert "ZOOM" in zoom, zoom
    tmux("resize-pane", "-Z")
    flat = tmux("display-message", "-p", "#{E:status-left}")
    assert "" not in flat and "" not in flat, flat
    long_dir = repo / ("long-path-" + "x" * 90)
    long_dir.mkdir()
    tmux("new-window", "-n", "Terminal", "-c", str(long_dir))
    widths = []
    for width in (79, 80, 99, 100, 120):
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 32, width, 0, 0))
        os.kill(client.pid, signal.SIGWINCH)
        settle()
        rendered = status()
        assert ("long-path-" in rendered) == (width >= 80), (width, rendered)
        assert re.search(r"\d{2}:\d{2}", rendered), rendered
        assert "x" * 30 not in rendered, (width, rendered)
        widths.append(f"{width}: {rendered}")
    (out / "tmux-states.txt").write_text("\n".join([*underline_results, prefix, copy, zoom, flat, *widths]))
finally:
    client.terminate()
    client.wait(timeout=5)
    os.close(master)


# Native parsers also run for TUI-only programs. All configs/state live under the
# build HOME; btop receives a writable copy since it persists settings on exit.
for relative, source in settings["configs"].items():
    target = pathlib.Path(os.environ["XDG_CONFIG_HOME"]) / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    if relative == "btop/btop.conf":
        target.write_text(re.sub(r'^color_theme = .*$', 'color_theme = "One Dark"', target.read_text(), flags=re.M))


def smoke(name, args, quit_key):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))
    def controlling_tty():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    process = subprocess.Popen(
        [settings[name], *args], stdin=slave, stdout=slave, stderr=slave,
        cwd=repo, env=env | {"LC_ALL": "C.UTF-8", "TERM": "xterm-256color", "COLORTERM": "truecolor"},
        preexec_fn=controlling_tty,
    )
    os.close(slave)
    data = bytearray()
    def drain(seconds):
        until = time.monotonic() + seconds
        while time.monotonic() < until:
            if select.select([master], [], [], 0.02)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                data.extend(chunk)
                if name in ("yazi", "atuin"):
                    # Minimal xterm replies let the native parser/UI start on a
                    # PTY. This fixture does not claim real Kitty protocol QA.
                    background = tomllib.loads(pathlib.Path(settings["configs"]["yazi/theme.toml"]).read_text())["mode"]["normal_alt"]["bg"]
                    rgb = "/".join(background[i:i+2] * 2 for i in (1, 3, 5))
                    replies = {
                        b"\x1b[>q": b"\x1bP>|XTerm(399)\x1b\\",
                        b"\x1b[16t": b"\x1b[6;22;11t",
                        b"\x1b]11;?": f"\x1b]11;rgb:{rgb}\x1b\\".encode(),
                        b"\x1b[0c": b"\x1b[?62;4;22c",
                        b"\x1bP$q q": b"\x1bP1$r2 q\x1b\\",
                        b"\x1b[?12$p": b"\x1b[?12;2$y",
                        b"\x1b[?u": b"\x1b[?0u",
                        b"\x1b[6n": b"\x1b[1;1R",
                    }
                    for query, response in replies.items():
                        if query in chunk:
                            os.write(master, response)
    try:
        drain(1)
        if process.poll() is None:
            os.write(master, quit_key)
            drain(1)
        if process.poll() is None:
            process.terminate()
        code = process.wait(timeout=5)
        text = data.decode(errors="replace")
        recorded = "\n".join(sorted(set(re.findall(r"\x1b\[(?:38|48);2;[0-9;]+m", text)))) if name == "btop" else text
        (out / (name + ".terminal.txt")).write_text(recorded)
        assert b"\x1b[" in data, (name, code, text)
        assert not re.search(r"(?i)(failed to (parse|load)|unknown (field|color)|invalid (theme|color)|error parsing|panic|traceback)", text), (name, text)
        # Atuin may return a cancellation status; other apps should exit cleanly.
        assert code in ([0, 1, 130] if name == "atuin" else [0]), (name, code, text)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)


smoke("btop", [], b"q")
smoke("yazi", [], b"q")
smoke("lazygit", [], b"q")
# Seed only the isolated database, so the picker has one harmless row to render.
os.environ["ATUIN_SESSION"] = run(settings["atuin"], "uuid").strip()
env["ATUIN_SESSION"] = os.environ["ATUIN_SESSION"]
entry = run(settings["atuin"], "history", "start", "visual fixture").strip()
run(settings["atuin"], "history", "end", "--exit", "0", entry)
smoke("atuin", ["search", "--interactive"], b"\x1b")
