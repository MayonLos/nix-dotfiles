#!/usr/bin/env python3
"""Read shared wallpaper collections; only the Xorg runtime record is ours."""
import argparse
import os
from pathlib import Path
import random
import select
import socket
import subprocess
import tempfile


def images(root):
    found, directories = set(), set()
    for directory, children, files in os.walk(root, followlinks=True):
        canonical = Path(directory).resolve()
        if canonical in directories:
            children[:] = []
            continue
        directories.add(canonical)
        for name in files:
            path = Path(directory, name)
            if path.suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp'} and '\n' not in str(path):
                found.add(str(path.resolve()))
    return sorted(found)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['daemon', 'next'])
    parser.add_argument('--root', required=True)
    parser.add_argument('--fallback', required=True)
    parser.add_argument('--default', required=True)
    args = parser.parse_args()
    runtime = Path(os.environ['XDG_RUNTIME_DIR']) / 'nix-dotfiles-xorg'
    runtime.mkdir(mode=0o700, exist_ok=True)
    endpoint = runtime / 'wallpaper.sock'
    if args.action == 'next':
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as client:
            client.connect(str(endpoint))
            client.send(b'next')
        return
    # systemd owns this one process. No manager calls or other-session signals.
    endpoint.unlink(missing_ok=True)
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as server:
        server.bind(str(endpoint))
        os.chmod(endpoint, 0o600)
        current = args.default
        try:
            while True:
                subprocess.run(['feh', '--no-fehbg', '--bg-fill', current], check=True, timeout=15)
                fd, temporary = tempfile.mkstemp(prefix='.wallpaper-', dir=runtime)
                with os.fdopen(fd, 'w') as record:
                    record.write(current + '\n')
                os.replace(temporary, runtime / 'wallpaper')
                if select.select([server], [], [], 86400)[0]:
                    if server.recv(32) != b'next':
                        continue
                candidates = images(args.root) or images(args.fallback)
                candidates = [p for p in candidates if p != current] or [args.default]
                current = random.choice(candidates)
        finally:
            endpoint.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
