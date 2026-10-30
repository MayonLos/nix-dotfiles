#!/usr/bin/env python3
"""End-to-end CLI safety tests using only the in-memory Unix-socket mock Engine.

Usage: python -B packages/mayon-tui/crates/docker/tests/cli_mock.py /path/to/dockertui-mayon
No Docker executable or user Docker socket is read or invoked.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time
import tempfile
import threading
from urllib.parse import parse_qs, unquote, urlsplit

sys.dont_write_bytecode = True

MOCK_PATH = Path(__file__).with_name("mock_engine.py")
MOCK_SPEC = importlib.util.spec_from_file_location("dockertui_mock_engine", MOCK_PATH)
if MOCK_SPEC is None or MOCK_SPEC.loader is None:
    raise RuntimeError(f"cannot load mock Engine from {MOCK_PATH}")
mock_engine = importlib.util.module_from_spec(MOCK_SPEC)
MOCK_SPEC.loader.exec_module(mock_engine)


class Checks:
    def __init__(self) -> None:
        self.count = 0

    def that(self, condition: bool, message: str) -> None:
        self.count += 1
        if not condition:
            raise AssertionError(message)


def parse_mutations(log_path: Path) -> list[dict[str, str]]:
    if not log_path.exists():
        return []
    return [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines() if line]


def reset_fixture(server: mock_engine.MockEngine, log_path: Path) -> None:
    with server.state_lock:
        server.state = mock_engine.fixture()
    log_path.write_text("", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="built dockertui-mayon executable")
    args = parser.parse_args()
    binary = args.binary.expanduser().resolve(strict=True)
    if not binary.is_file():
        parser.error("binary must be a file")

    work = mock_engine.worktree_root() / ".work"
    if not work.is_dir():
        parser.error(f".work directory must exist: {work}")

    checks = Checks()
    labels: list[str] = []
    with tempfile.TemporaryDirectory(prefix="docker-cli-mock-", dir=work) as scratch:
        temp = Path(scratch).resolve()
        socket_path = temp / "engine.sock"
        log_path = temp / "mutations.jsonl"
        private_home = temp / "home"
        private_home.mkdir()
        server = mock_engine.MockEngine(socket_path, log_path)
        server_thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
        server_thread.start()
        try:
            checks.that(socket_path.is_relative_to(work.resolve()), "mock socket must stay under .work")
            endpoint = f"unix://{socket_path}"
            # Explicit host and an intentionally small environment prevent inheriting
            # DOCKER_HOST, credentials, tokens, or any desktop/session variables.
            env = {
                "PATH": os.defpath,
                "HOME": str(private_home),
                "XDG_RUNTIME_DIR": str(temp),
                "LANG": "C.UTF-8",
                "LC_ALL": "C.UTF-8",
            }

            def run(*arguments: str, input_text: str = ""):
                return subprocess.run(
                    [str(binary), "--host", endpoint, *arguments],
                    input=input_text,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                    timeout=20,
                    check=False,
                )

            def no_mutations(label: str) -> None:
                checks.that(not parse_mutations(log_path), f"{label}: no mutation request expected")

            # Read-only df must not mutate state, even though the daemon reports
            # removable fixture rows.
            reset_fixture(server, log_path)
            result = run("df")
            checks.that(result.returncode == 0, f"df failed: {result.stderr}")
            checks.that("镜像" in result.stdout and "构建缓存" in result.stdout, "df must report categories")
            no_mutations("df")
            labels.append("df is read-only")

            # No --yes is a preview only; --yes still requires the DELETE phrase.
            reset_fixture(server, log_path)
            result = run("clean", "--image", "sha256:fixture-dangling-unused")
            checks.that(result.returncode == 0, f"image preview failed: {result.stderr}")
            checks.that("准确删除清单" in result.stdout and "fixture-dangling-unused" in result.stdout, "preview must show exact ID")
            checks.that("仅预览；未执行" in result.stdout, "clean without --yes must remain a preview")
            no_mutations("preview")
            result = run("clean", "--yes", "--image", "sha256:fixture-dangling-unused", input_text="cancel\n")
            checks.that(result.returncode == 0 and "已取消" in result.stdout, "wrong second-confirmation text must cancel")
            no_mutations("cancelled image cleanup")
            labels.append("preview and --yes cancellation do not mutate")

            # The CLI rejects a running container and images/volumes referenced by
            # the fixture before any deletion request is issued.
            reset_fixture(server, log_path)
            for kind, ident in [
                ("--container", "container-running-001"),
                ("--image", "sha256:fixture-running-image"),
                ("--image", "sha256:fixture-stopped-image"),
                ("--volume", "fixture-used-volume"),
            ]:
                result = run("clean", kind, ident, "--yes", input_text="DELETE\n")
                checks.that(result.returncode != 0, f"unsafe selection should be rejected: {kind} {ident}")
                checks.that("不可清理" in result.stderr, f"unsafe selection should explain rejection: {kind} {ident}")
                no_mutations(f"rejected {kind} {ident}")
            labels.append("running and referenced resources are rejected")

            # Safe image deletion uses both non-forcing flags and names exactly one ID.
            reset_fixture(server, log_path)
            image_id = "sha256:fixture-dangling-unused"
            result = run("clean", "--image", image_id, "--yes", input_text="DELETE\n")
            checks.that(result.returncode == 0, f"image deletion failed: {result.stderr}")
            image_mutations = parse_mutations(log_path)
            checks.that(len(image_mutations) == 1, "image cleanup must issue exactly one mutation")
            image_path = urlsplit(image_mutations[0]["path"])
            image_query = parse_qs(image_path.query)
            checks.that(image_mutations[0]["method"] == "DELETE", "image cleanup must use DELETE")
            checks.that(unquote(image_path.path).endswith(image_id), "image cleanup must target selected ID only")
            checks.that(image_query == {"force": ["false"], "noprune": ["true"]}, "image DELETE must be force=false&noprune=true")
            checks.that(all(item["Id"] != image_id for item in server.state["images"]), "selected image should be removed")
            checks.that(any(item["Id"] == "sha256:fixture-running-image" for item in server.state["images"]), "other images must remain")
            labels.append("image cleanup is exact and non-pruning")

            # Cache prune must use a single anchored ID filter, and report the
            # Engine's reclaimed byte count.
            reset_fixture(server, log_path)
            cache_id = "cache-fixture-unused"
            result = run("clean", "--cache", cache_id, "--yes", input_text="DELETE\n")
            checks.that(result.returncode == 0, f"cache cleanup failed: {result.stderr}")
            cache_mutations = parse_mutations(log_path)
            checks.that(len(cache_mutations) == 1 and cache_mutations[0]["method"] == "POST", "cache cleanup must issue one POST")
            cache_url = urlsplit(cache_mutations[0]["path"])
            cache_query = parse_qs(cache_url.query)
            filters = json.loads(cache_query["filters"][0])
            checks.that(filters.get("id") == [f"^{cache_id}$"], "cache filter must anchor one exact ID")
            checks.that(filters.get("inuse") == ["false"] and filters.get("shared") == ["false"], "cache prune must exclude in-use/shared rows")
            checks.that(all(item["ID"] != cache_id for item in server.state["build_cache"]), "selected cache should be removed")
            checks.that("实际释放（daemon 占用前后差值）：192.0 MiB" in result.stdout, "actual cache space delta must be reported")
            labels.append("cache cleanup uses exact filter and reports reclaimed space")

            # A volume needs the generic DELETE plus its own exact name phrase.
            volume_id = "fixture-unused-volume"
            reset_fixture(server, log_path)
            result = run("clean", "--yes", "--volume", volume_id, input_text="DELETE\nDELETE wrong-name\n")
            checks.that(result.returncode == 0 and "已取消" in result.stdout, "wrong volume phrase must cancel")
            no_mutations("wrong volume phrase")
            checks.that(any(v["Name"] == volume_id for v in server.state["volumes"]), "cancelled volume remains")

            reset_fixture(server, log_path)
            result = run("clean", "--yes", "--volume", volume_id, input_text=f"DELETE\nDELETE {volume_id}\n")
            checks.that(result.returncode == 0, f"confirmed volume cleanup failed: {result.stderr}")
            volume_mutations = parse_mutations(log_path)
            checks.that(len(volume_mutations) == 1, "volume cleanup must issue exactly one mutation")
            volume_path = urlsplit(volume_mutations[0]["path"])
            checks.that(volume_mutations[0]["method"] == "DELETE" and unquote(volume_path.path).endswith(volume_id), "volume DELETE must target the exact confirmed name")
            checks.that(all(v["Name"] != volume_id for v in server.state["volumes"]), "confirmed unused volume should be removed")
            checks.that(any(v["Name"] == "fixture-used-volume" for v in server.state["volumes"]), "used volume must remain")
            labels.append("volume requires the exact separate name phrase")

            # A stopped container deletion must be non-forcing and leave every
            # fixture volume intact.
            reset_fixture(server, log_path)
            container_id = "container-stopped-001"
            result = run("clean", "--yes", "--container", container_id, input_text="DELETE\n")
            checks.that(result.returncode == 0, f"stopped-container cleanup failed: {result.stderr}")
            container_mutations = parse_mutations(log_path)
            checks.that(len(container_mutations) == 1, "container cleanup must issue exactly one mutation")
            container_path = urlsplit(container_mutations[0]["path"])
            container_query = parse_qs(container_path.query)
            checks.that(container_mutations[0]["method"] == "DELETE" and unquote(container_path.path).endswith(container_id), "container DELETE must target the selected stopped ID")
            checks.that(container_query == {"force": ["false"], "v": ["false"]}, "container DELETE must preserve volumes and avoid force")
            checks.that(len(server.state["volumes"]) == 2, "container cleanup must leave volumes intact")
            labels.append("stopped container cleanup preserves volumes")

            # Change the target after the exact preview has been displayed but
            # before confirming. Execution must take a fresh df snapshot, skip it,
            # report the full ID, and issue no mutation.
            reset_fixture(server, log_path)
            container_id = "container-stopped-001"
            process = subprocess.Popen(
                [str(binary), "--host", endpoint, "clean", "--yes", "--container", container_id],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                bufsize=0,
            )
            stdout_seen = bytearray()
            confirmation_seen = False
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + 10
            try:
                while time.monotonic() < deadline:
                    events = selector.select(timeout=max(0, deadline - time.monotonic()))
                    if not events:
                        break
                    chunk = os.read(process.stdout.fileno(), 4096)
                    if not chunk:
                        break
                    stdout_seen.extend(chunk)
                    if "二次确认".encode() in stdout_seen:
                        confirmation_seen = True
                        break
                checks.that(confirmation_seen, "CLI must reach the second-confirmation prompt before the state change")
                if confirmation_seen:
                    with server.state_lock:
                        changed = next(c for c in server.state["containers"] if c["Id"] == container_id)
                        changed["State"] = "running"
                    process.stdin.write(b"DELETE\n")
                    process.stdin.flush()
                else:
                    process.terminate()
                tail, stderr = process.communicate(timeout=15)
                output = (stdout_seen + tail).decode("utf-8", errors="replace")
                error_output = stderr.decode("utf-8", errors="replace")
                checks.that(process.returncode != 0, "changed running container must be reported as a failed cleanup")
                checks.that(container_id in output, "failure report must include the full container ID")
                checks.that("失败" in output and ("状态改变" in output or "运行中" in output), "failure report must explain the changed state")
                no_mutations("container state changed after preview")
                checks.that(len(server.state["volumes"]) == 2, "skipped container must leave volumes intact")
                labels.append("fresh state check skips a container that starts after preview")
            finally:
                selector.close()
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.communicate(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.communicate(timeout=5)

            for label in labels:
                print(f"PASS {label}")
            print(f"{checks.count} CLI/mock assertions passed")
        finally:
            server.shutdown()
            server.server_close()
            server_thread.join(timeout=3)
            if server_thread.is_alive():
                raise RuntimeError("mock Engine server thread did not stop")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
