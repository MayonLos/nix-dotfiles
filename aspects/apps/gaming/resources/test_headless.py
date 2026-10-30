"""Run an SDL probe on a private compositor; never inherit a desktop session."""
import os
from pathlib import Path
import subprocess
import socket
import struct
import sys
import tempfile
import time


def virtual_pointer(path):
    # LWJGL's bundled SDL assumes the Wayland seat has a pointer during video
    # initialization. Give the private headless seat one without input events.
    connection = socket.socket(socket.AF_UNIX)
    connection.settimeout(5)
    connection.connect(str(path))

    def send(object_id, opcode, body):
        connection.sendall(struct.pack("II", object_id, ((len(body) + 8) << 16) | opcode) + body)

    send(1, 1, struct.pack("I", 2))  # wl_display.get_registry
    send(1, 0, struct.pack("I", 3))  # wl_display.sync
    buffer = b""
    manager = None
    done = False
    while not done:
        chunk = connection.recv(65536)
        if not chunk:
            raise RuntimeError("private Wayland connection closed during registry discovery")
        buffer += chunk
        while len(buffer) >= 8:
            object_id, header = struct.unpack("II", buffer[:8])
            length, opcode = header >> 16, header & 65535
            if length < 8:
                raise RuntimeError("invalid private Wayland message")
            if len(buffer) < length:
                break
            body, buffer = buffer[8:length], buffer[length:]
            if object_id == 2 and opcode == 0:
                name, size = struct.unpack("II", body[:8])
                if body[8:8 + size - 1] == b"zwlr_virtual_pointer_manager_v1":
                    manager = name
            if object_id == 3 and opcode == 0:
                done = True
    if manager is None:
        raise RuntimeError("headless compositor lacks the virtual pointer protocol")
    interface = b"zwlr_virtual_pointer_manager_v1\0"
    string = struct.pack("I", len(interface)) + interface + b"\0" * (-len(interface) % 4)
    send(2, 0, struct.pack("I", manager) + string + struct.pack("II", 1, 4))
    send(4, 0, struct.pack("II", 0, 5))  # create_virtual_pointer, default seat
    send(1, 0, struct.pack("I", 6))
    # Round-trip before starting the client to guarantee the seat capability.
    while True:
        chunk = connection.recv(65536)
        if not chunk:
            raise RuntimeError("private Wayland connection closed before pointer readiness")
        buffer += chunk
        while len(buffer) >= 8:
            object_id, header = struct.unpack("II", buffer[:8])
            length, opcode = header >> 16, header & 65535
            if length < 8:
                raise RuntimeError("invalid private Wayland message")
            if len(buffer) < length:
                break
            buffer = buffer[length:]
            if object_id == 6 and opcode == 0:
                return connection


with tempfile.TemporaryDirectory(prefix="gaming-headless-") as temporary:
    root = Path(temporary)
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    home = root / "home"
    home.mkdir()
    config = root / "sway.conf"
    config.write_text("output HEADLESS-1 mode 2560x1600 scale 1.5\n"
                      "seat seat0 fallback true\nxwayland disable\n")
    env = {
        "HOME": str(home), "XDG_RUNTIME_DIR": str(runtime),
        "XDG_CONFIG_HOME": str(home / ".config"), "PATH": os.environ["PATH"],
        "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman",
        "WLR_LIBINPUT_NO_DEVICES": "1", "LANG": "C.UTF-8",
        "SDL_VIDEODRIVER": "wayland", "SDL3_LIBRARY": os.environ["SDL3_LIBRARY"],
    }
    with (root / "sway.log").open("w+") as log:
        compositor = subprocess.Popen(["sway", "--config", str(config)], env=env,
                                      stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                sockets = list(runtime.glob("wayland-*"))
                sockets = [p for p in sockets if not p.name.endswith(".lock")]
                if sockets:
                    break
                if compositor.poll() is not None:
                    raise RuntimeError("private compositor exited")
                time.sleep(0.05)
            else:
                raise TimeoutError("private Wayland socket was not created")
            env["WAYLAND_DISPLAY"] = sockets[0].name
            with virtual_pointer(sockets[0]):
                subprocess.run(sys.argv[1:], env=env, check=True, timeout=30)
        except Exception:
            log.seek(0)
            print(log.read(), file=sys.stderr)
            raise
        finally:
            compositor.terminate()
            try:
                compositor.wait(timeout=5)
            except subprocess.TimeoutExpired:
                compositor.kill()
                compositor.wait()
