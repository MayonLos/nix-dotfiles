#!/usr/bin/env python3
"""Minimal greetd IPC stub for the isolated gtkgreet runtime check.

gtkgreet 0.8 talks to ``GREETD_SOCK`` using a 4-byte little-endian length header
followed by one JSON object (not newline-delimited JSON). The runtime check never
authenticates: the stub only has to keep the socket valid so the greeter renders
its login card without a real greetd/PAM.

This is an independent, standard-library-only implementation of the protocol;
the repository's ``.work/preview/greeter`` harness uses an equivalent stub.
"""

from __future__ import annotations

import json
import os
import signal
import socket
import struct
import sys


def log(message: str) -> None:
    path = os.environ.get("STUB_LOG")
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(message + "\n")
    except OSError:
        pass


def send_message(connection: socket.socket, payload: dict) -> None:
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    connection.sendall(struct.pack("<I", len(body)) + body)


def read_message(connection: socket.socket):
    header = b""
    while len(header) < 4:
        chunk = connection.recv(4 - len(header))
        if not chunk:
            return None
        header += chunk
    (length,) = struct.unpack("<I", header)
    body = b""
    while len(body) < length:
        chunk = connection.recv(length - len(body))
        if not chunk:
            return None
        body += chunk
    return json.loads(body.decode("utf-8"))


def handle(connection: socket.socket) -> None:
    request = read_message(connection)
    if request is None:
        return
    log("request " + json.dumps(request, ensure_ascii=False, sort_keys=True))
    kind = request.get("type")
    if kind == "create_session":
        send_message(
            connection,
            {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password:"},
        )
    elif kind == "post_auth_message_response":
        send_message(
            connection,
            {
                "type": "error",
                "error_type": "auth_error",
                "description": "runtime-e2e stub: authentication disabled",
            },
        )
    elif kind in ("start_session", "cancel_session"):
        send_message(connection, {"type": "success"})
    else:
        send_message(
            connection,
            {
                "type": "error",
                "error_type": "error",
                "description": f"runtime-e2e stub: unsupported request {kind!r}",
            },
        )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: greetd_stub.py SOCKET", file=sys.stderr)
        return 2
    path = sys.argv[1]
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(16)
    log(f"listening on {path}")
    stop = False

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    server.settimeout(0.5)
    while not stop:
        try:
            connection, _ = server.accept()
        except socket.timeout:
            continue
        try:
            with connection:
                handle(connection)
        except (OSError, ValueError) as error:
            log(f"connection error: {error!r}")
    server.close()
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    log("stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
