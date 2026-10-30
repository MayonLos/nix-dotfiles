"""Bounded, read-only Mihomo Unix controller status for the desktop.

Only /version and one /traffic sample are read. Never load configuration,
subscriptions, credentials, connection lists or the TCP controller.
"""

import http.client
import json
import os
import socket
from pathlib import Path


class UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path, timeout):
        # The Host header must stay a valid name: Mihomo rejects a socket path.
        super().__init__("localhost", timeout=timeout)
        self.socket_path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.socket_path)


def request(path, endpoint):
    conn = UnixHTTP(str(path), timeout=1.3 if endpoint == "/traffic" else 0.25)
    try:
        conn.request("GET", endpoint)
        response = conn.getresponse()
        if response.status != 200:
            return None
        # /traffic is a newline-delimited stream. Read one bounded sample.
        raw = response.readline(4097)
        if len(raw) > 4096:
            return None
        return json.loads(raw)
    except (OSError, ValueError, http.client.HTTPException):
        return None
    finally:
        conn.close()


def probe(paths):
    live = []
    uncertain = False
    for label, path in paths:
        version = request(path, "/version")
        if isinstance(version, dict) and isinstance(version.get("version"), str):
            live.append((label, path))
        elif path.exists():
            uncertain = True
    if len(live) > 1:
        return {"label": "双内核运行 · 请检查", "active": True}
    if not live:
        return {"label": "状态不可用" if uncertain else "控制器未连接", "active": False}
    label, path = live[0]
    result = {"label": label + " · 运行中", "active": True}
    traffic = request(path, "/traffic")
    if isinstance(traffic, dict) and all(
        isinstance(traffic.get(k), (int, float)) and not isinstance(traffic[k], bool)
        and 0 <= traffic[k] < 1e15 for k in ("up", "down")
    ):
        result["traffic"] = f"↑{rate(traffic['up'])}  ↓{rate(traffic['down'])}"
    return result


def rate(value):
    for unit in ("B/s", "KiB/s", "MiB/s", "GiB/s"):
        if value < 1024 or unit == "GiB/s":
            return f"{value:.1f}{unit}"
        value /= 1024


if __name__ == "__main__":
    paths = [("原生", Path("/run/mayon-clash/mihomo.sock"))]
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        paths.append(("Verge", Path(runtime) / "clash-verge-rev/verge-mihomo.sock"))
    print(json.dumps(probe(paths), ensure_ascii=False))
