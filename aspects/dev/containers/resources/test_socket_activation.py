#!/usr/bin/env python3
"""Exercise systemd-socket-proxyd with an isolated Unix-socket backend."""

from __future__ import annotations

import concurrent.futures
import os
import pathlib
import socket
import subprocess
import tempfile
import threading
import time


def serve_backend(path: pathlib.Path, stop: threading.Event) -> None:
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(path))
    listener.listen(32)
    listener.settimeout(0.1)
    try:
        while not stop.is_set():
            try:
                connection, _ = listener.accept()
            except TimeoutError:
                continue
            threading.Thread(target=serve_client, args=(connection,), daemon=True).start()
    finally:
        listener.close()


def serve_client(connection: socket.socket) -> None:
    with connection:
        payload = connection.recv(256)
        connection.sendall(payload.upper())


def request(path: pathlib.Path, payload: bytes) -> bytes:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(5)
        client.connect(str(path))
        client.sendall(payload)
        return client.recv(256)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="docker-proxy-check-") as tmp:
        root = pathlib.Path(tmp)
        frontend = root / "docker.sock"
        backend = root / "docker-private.sock"
        stop = threading.Event()
        backend_thread = threading.Thread(target=serve_backend, args=(backend, stop), daemon=True)
        backend_thread.start()
        deadline = time.monotonic() + 5
        while not backend.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert backend.exists(), "test backend failed to bind"

        launcher = subprocess.Popen(
            [
                os.environ["SYSTEMD_SOCKET_ACTIVATE"],
                "--listen=" + str(frontend),
                os.environ["SYSTEMD_SOCKET_PROXYD"],
                str(backend),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            deadline = time.monotonic() + 5
            while not frontend.exists() and time.monotonic() < deadline:
                if launcher.poll() is not None:
                    raise AssertionError(f"socket activation exited: {launcher.stderr.read()}")
                time.sleep(0.01)
            assert frontend.exists(), "socket activation failed to bind"

            payloads = [f"request-{index}".encode() for index in range(16)]
            with concurrent.futures.ThreadPoolExecutor(max_workers=len(payloads)) as pool:
                responses = list(pool.map(lambda payload: request(frontend, payload), payloads))
            assert responses == [payload.upper() for payload in payloads], responses
        finally:
            launcher.terminate()
            try:
                launcher.wait(timeout=3)
            except subprocess.TimeoutExpired:
                launcher.kill()
                launcher.wait()
            stop.set()
            backend_thread.join(timeout=1)


if __name__ == "__main__":
    main()
