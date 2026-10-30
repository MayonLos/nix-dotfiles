"""Exercise the actual Unix HTTP reader with isolated controller fixtures."""
import contextlib
import http.server
import json
import socketserver
import tempfile
import threading
import time
import unittest
from pathlib import Path

import status


@contextlib.contextmanager
def controller(path, traffic=None, valid=True, delay=0):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            if self.path == "/version":
                payload = {"version": "fixture"} if valid else {"error": "unauthorized"}
            elif self.path == "/traffic":
                # Locked Mihomo sends the first traffic frame after one second.
                time.sleep(delay)
                payload = traffic
            else:
                raise AssertionError("Status must never request sensitive endpoints")
            raw = json.dumps(payload).encode() + b"\n"
            self.send_response(200)
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    with socketserver.UnixStreamServer(str(path), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield
        finally:
            server.shutdown()
            thread.join()


class StatusTests(unittest.TestCase):
    def test_live_conflict_stale_and_absent(self):
        with tempfile.TemporaryDirectory() as folder:
            native, verge = (Path(folder) / name for name in ("native", "verge"))
            paths = [("原生", native), ("Verge", verge)]
            self.assertFalse(status.probe(paths)["active"])
            with controller(native, {"up": 1024, "down": 2048}, delay=1):
                result = status.probe(paths)
                self.assertEqual(result, {"label": "原生 · 运行中", "active": True,
                                          "traffic": "↑1.0KiB/s  ↓2.0KiB/s"})
                with controller(verge):
                    self.assertEqual(status.probe(paths), {"label": "双内核运行 · 请检查", "active": True})
            self.assertEqual(status.probe(paths)["label"], "状态不可用")

    def test_bad_or_unavailable_data_never_invents_traffic(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "core"
            with controller(path, {"up": -1, "down": "secret"}):
                self.assertNotIn("traffic", status.probe([("原生", path)]))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "core"
            with controller(path, valid=False):
                self.assertEqual(status.probe([("原生", path)]), {"label": "状态不可用", "active": False})


if __name__ == "__main__":
    unittest.main()
