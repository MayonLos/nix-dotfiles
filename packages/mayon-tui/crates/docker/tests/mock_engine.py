#!/usr/bin/env python3
"""Safe, deterministic Unix-socket Docker Engine fixture for dockertui-mayon.

Run with --socket .work/docker-mock/engine.sock. This server never connects to
or starts Docker; it only serves the in-memory fixture below.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import signal
import socket
import stat
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from urllib.parse import parse_qs, unquote, urlsplit

API = "/v1.47"


def fixture() -> dict:
    """Create a fresh mutable mock state with both safe and protected rows."""
    return {
        "containers": [
            {
                "Id": "container-running-001",
                "Names": ["/fixture-running"],
                "Image": "fixture/live:1",
                "ImageID": "sha256:fixture-running-image",
                "State": "running",
                "Status": "Up 3 minutes",
                "Labels": {"fixture": "protected"},
                "Ports": [],
                "Mounts": [
                    {
                        "Type": "volume",
                        "Name": "fixture-used-volume",
                        "Source": "/mock/fixture-used-volume",
                        "Destination": "/data",
                    }
                ],
                "SizeRw": 64 * 1024 * 1024,
            },
            {
                "Id": "container-stopped-001",
                "Names": ["/fixture-stopped"],
                "Image": "fixture/old:1",
                "ImageID": "sha256:fixture-stopped-image",
                "State": "exited",
                "Status": "Exited (0) 2 hours ago",
                "Labels": {"fixture": "removable"},
                "Ports": [],
                "Mounts": [],
                "SizeRw": 32 * 1024 * 1024,
            },
        ],
        "images": [
            {
                "Id": "sha256:fixture-running-image",
                "RepoTags": ["fixture/live:1"],
                "Size": 256 * 1024 * 1024,
                "SharedSize": 16 * 1024 * 1024,
                "Containers": 1,
            },
            {
                "Id": "sha256:fixture-stopped-image",
                "RepoTags": ["fixture/old:1"],
                "Size": 128 * 1024 * 1024,
                "SharedSize": 0,
                "Containers": 1,
            },
            {
                "Id": "sha256:fixture-dangling-unused",
                "RepoTags": ["<none>:<none>"],
                "Size": 96 * 1024 * 1024,
                "SharedSize": 16 * 1024 * 1024,
                "Containers": 0,
            },
        ],
        "volumes": [
            {
                "Name": "fixture-used-volume",
                "Driver": "local",
                "Mountpoint": "/mock/fixture-used-volume",
                "UsageData": {"Size": 512 * 1024 * 1024, "RefCount": 1},
            },
            {
                "Name": "fixture-unused-volume",
                "Driver": "local",
                "Mountpoint": "/mock/fixture-unused-volume",
                "UsageData": {"Size": 128 * 1024 * 1024, "RefCount": 0},
            },
        ],
        "build_cache": [
            {"ID": "cache-fixture-inuse", "Size": 512 * 1024 * 1024, "InUse": True, "Shared": False},
            {"ID": "cache-fixture-shared", "Size": 256 * 1024 * 1024, "InUse": False, "Shared": True},
            {"ID": "cache-fixture-unused", "Size": 192 * 1024 * 1024, "InUse": False, "Shared": False},
        ],
    }


class MockEngine(ThreadingMixIn, HTTPServer):
    address_family = socket.AF_UNIX
    allow_reuse_address = False
    daemon_threads = True

    def __init__(self, socket_path: Path, log_path: Path | None):
        self.state = fixture()
        self.state_lock = threading.RLock()
        self.log_path = log_path
        self.log_lock = threading.Lock()
        super().__init__(str(socket_path), Handler)

    def audit(self, method: str, path: str, result: str) -> None:
        if self.log_path is None:
            return
        record = {"method": method, "path": path, "result": result}
        with self.log_lock:
            self.log_path.parent.mkdir(parents=True, exist_ok=True)
            with self.log_path.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(record, ensure_ascii=False) + "\n")


class Handler(BaseHTTPRequestHandler):
    server: MockEngine
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *_args: object) -> None:
        # BaseHTTPRequestHandler logs can contain caller-controlled paths.
        return

    def _reply(self, status: int, value: object = None) -> None:
        body = b"" if value is None else json.dumps(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        if body:
            self.send_header("Content-Type", "application/json")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _path(self) -> tuple[str, dict[str, list[str]]]:
        parsed = urlsplit(self.path)
        path = parsed.path
        if path.startswith(API):
            path = path[len(API) :] or "/"
        return path, parse_qs(parsed.query, keep_blank_values=True)

    def _df(self) -> dict:
        state = self.server.state
        containers = [
            {
                "Id": item["Id"],
                "Names": item["Names"],
                "Image": item["Image"],
                "ImageID": item["ImageID"],
                "State": item["State"],
                "Status": item["Status"],
                "SizeRw": item["SizeRw"],
                "Mounts": item["Mounts"],
            }
            for item in state["containers"]
        ]
        return {
            "LayersSize": (
                sum(image["Size"] - image["SharedSize"] for image in state["images"])
                + max((image["SharedSize"] for image in state["images"]), default=0)
            ),
            "Images": [
                {
                    "Id": image["Id"],
                    "RepoTags": image["RepoTags"],
                    "Size": image["Size"],
                    "SharedSize": image["SharedSize"],
                    "Containers": image["Containers"],
                }
                for image in state["images"]
            ],
            "Containers": containers,
            "Volumes": [
                {"Name": volume["Name"], "UsageData": volume["UsageData"]}
                for volume in state["volumes"]
            ],
            "BuildCache": list(state["build_cache"]),
        }

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        path, _query = self._path()
        with self.server.state_lock:
            if path == "/_ping":
                self._reply(200, None)
            elif path == "/info":
                self._reply(200, {"ServerVersion": "mock-27.5.1"})
            elif path == "/containers/json":
                self._reply(200, self.server.state["containers"])
            elif path == "/images/json":
                self._reply(200, self.server.state["images"])
            elif path == "/volumes":
                self._reply(200, {"Volumes": self.server.state["volumes"]})
            elif path == "/system/df":
                self._reply(200, self._df())
            elif re.fullmatch(r"/containers/[^/]+/stats", path):
                self._reply(
                    200,
                    {
                        "cpu_stats": {"cpu_usage": {"total_usage": 10}, "system_cpu_usage": 100, "online_cpus": 2},
                        "precpu_stats": {"cpu_usage": {"total_usage": 5}, "system_cpu_usage": 50},
                        "memory_stats": {"usage": 256 * 1024 * 1024, "limit": 2 * 1024**3, "stats": {"inactive_file": 32 * 1024**2}},
                    },
                )
            else:
                self._reply(404, {"message": "mock endpoint not found"})

    def do_DELETE(self) -> None:  # noqa: N802 - stdlib handler API
        path, query = self._path()
        result = "rejected"
        with self.server.state_lock:
            container_match = re.fullmatch(r"/containers/([^/]+)", path)
            image_match = re.fullmatch(r"/images/([^/]+)", path)
            volume_match = re.fullmatch(r"/volumes/(.+)", path)
            if container_match:
                ident = unquote(container_match.group(1))
                valid_flags = query.get("force") == ["false"] and query.get("v") == ["false"]
                item = next((c for c in self.server.state["containers"] if c["Id"] == ident), None)
                if valid_flags and item and item["State"] != "running":
                    self.server.state["containers"].remove(item)
                    for image in self.server.state["images"]:
                        if image["Id"] == item["ImageID"]:
                            image["Containers"] = max(0, image["Containers"] - 1)
                    result = "deleted fixture container"
                    self._reply(204)
                else:
                    self._reply(409, {"message": "unsafe or unknown fixture container"})
            elif image_match:
                ident = unquote(image_match.group(1))
                item = next((i for i in self.server.state["images"] if i["Id"] == ident), None)
                safe_flags = query.get("force") == ["false"] and query.get("noprune") == ["true"]
                if safe_flags and item and item["Containers"] == 0:
                    self.server.state["images"].remove(item)
                    result = "deleted fixture image"
                    self._reply(200, [{"Untagged": ident}])
                else:
                    self._reply(409, {"message": "image is referenced or not a fixture image"})
            elif volume_match:
                name = unquote(volume_match.group(1))
                item = next((v for v in self.server.state["volumes"] if v["Name"] == name), None)
                if item and item["UsageData"]["RefCount"] == 0:
                    self.server.state["volumes"].remove(item)
                    result = "deleted fixture volume"
                    self._reply(204)
                else:
                    self._reply(409, {"message": "volume is referenced or not a fixture volume"})
            else:
                self._reply(404, {"message": "mock endpoint not found"})
        self.server.audit("DELETE", self.path, result)

    def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
        path, query = self._path()
        result = "rejected"
        with self.server.state_lock:
            if path == "/build/prune":
                raw_filters = query.get("filters", [""])
                try:
                    filters = json.loads(raw_filters[0]) if len(raw_filters) == 1 else None
                except json.JSONDecodeError:
                    filters = None
                ids = filters.get("id") if isinstance(filters, dict) else None
                selected = ids[0] if isinstance(ids, list) and len(ids) == 1 else ""
                # Require a literal, anchored exact ID so an unfiltered or broad
                # builder prune can never change even the mock fixture.
                match = re.fullmatch(r"\^([A-Za-z0-9_.:-]+)\$", selected)
                item = None
                if match:
                    candidate = match.group(1)
                    item = next((c for c in self.server.state["build_cache"] if c["ID"] == candidate), None)
                if item and not item["InUse"] and not item["Shared"]:
                    self.server.state["build_cache"].remove(item)
                    result = "pruned exact fixture cache"
                    self._reply(200, {"SpaceReclaimed": item["Size"], "CachesDeleted": [item["ID"]]})
                else:
                    self._reply(400, {"message": "build prune requires one anchored ID for an unused, unshared fixture cache"})
            else:
                self._reply(404, {"message": "mock endpoint not found"})
        if path == "/build/prune":
            self.server.audit("POST", self.path, result)


def worktree_root() -> Path:
    return Path(__file__).resolve().parents[5]


def validate_paths(socket_arg: str, log_arg: str | None) -> tuple[Path, Path | None]:
    root = worktree_root()
    work = (root / ".work").resolve()
    socket_path = Path(socket_arg).expanduser().resolve()
    if socket_path == Path("/run/user") or socket_path.is_relative_to(Path("/run/user")):
        raise ValueError("refusing to use a runtime Docker socket path")
    if socket_path == Path("/run") or socket_path.is_relative_to(Path("/run")):
        raise ValueError("refusing to use a system runtime socket path")
    if not socket_path.is_relative_to(work) or socket_path == work:
        raise ValueError(f"mock socket must be inside this worktree's .work directory: {work}")
    if not socket_path.parent.is_dir():
        raise ValueError("socket parent directory must already exist")
    if socket_path.exists() or socket_path.is_symlink():
        raise ValueError("refusing to replace an existing socket path")
    log_path = Path(log_arg).expanduser().resolve() if log_arg else None
    if log_path is not None and not log_path.is_relative_to(work):
        raise ValueError(f"mock mutation log must be inside this worktree's .work directory: {work}")
    return socket_path, log_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", required=True, help="new Unix socket path under .work")
    parser.add_argument("--log", help="optional JSONL mutation log under .work")
    args = parser.parse_args()
    try:
        socket_path, log_path = validate_paths(args.socket, args.log)
    except ValueError as error:
        parser.error(str(error))
    server = MockEngine(socket_path, log_path)
    bound = socket_path.stat()
    print(f"mock Docker Engine listening on {socket_path}", flush=True)

    def stop(_signum: int, _frame: object) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()
        try:
            current = socket_path.stat()
            if stat.S_ISSOCK(current.st_mode) and (current.st_dev, current.st_ino) == (bound.st_dev, bound.st_ino):
                socket_path.unlink()
        except FileNotFoundError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
