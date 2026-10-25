#!/usr/bin/env python3
"""Apply preferred modes on physical output changes; sleep on RandR events."""
import argparse
import ctypes as C
import re
import subprocess


def topology(text):
    return [(m[1], m[2] == 'connected') for line in text.splitlines()
            if (m := re.match(r'^([^\s]+) (connected|disconnected)\b', line))]


def layout_command(outputs):
    # Internal display first, then deterministic connector order. Do not use
    # Wayland connector names, hard-coded EDIDs, or persist over user profiles.
    connected = sorted((name for name, online in outputs if online),
                       key=lambda name: (not name.startswith(('eDP', 'LVDS')), name))
    if not connected:
        return []
    command = ['xrandr']
    for name, online in outputs:
        if not online:
            command += ['--output', name, '--off']
    previous = None
    for name in connected:
        command += ['--output', name, '--auto']
        command += ['--right-of', previous] if previous else ['--primary', '--pos', '0x0']
        previous = name
    return command


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--x11', required=True)
    parser.add_argument('--randr', required=True)
    args = parser.parse_args()
    x = C.CDLL(args.x11)
    rr = C.CDLL(args.randr)
    x.XOpenDisplay.argtypes = [C.c_char_p]
    x.XOpenDisplay.restype = C.c_void_p
    x.XDefaultRootWindow.argtypes = [C.c_void_p]
    x.XDefaultRootWindow.restype = C.c_ulong
    x.XNextEvent.argtypes = [C.c_void_p, C.c_void_p]
    x.XCloseDisplay.argtypes = [C.c_void_p]
    rr.XRRSelectInput.argtypes = [C.c_void_p, C.c_ulong, C.c_int]
    display = x.XOpenDisplay(None)
    if not display:
        raise SystemExit('Xorg output watcher: no X11 display')
    try:
        rr.XRRSelectInput(display, x.XDefaultRootWindow(display), 1 | 2 | 4)
        previous = None
        while True:
            result = subprocess.run(['xrandr', '--query'], capture_output=True, text=True, timeout=5, check=True)
            outputs = topology(result.stdout)
            signature = tuple(outputs)
            if signature != previous:
                previous = signature
                command = layout_command(outputs)
                if command:
                    # Failures are visible in the journal; another physical
                    # topology change retries. Never loop on our mode events.
                    subprocess.run(command, timeout=10, check=False)
            event = C.create_string_buffer(192)  # XEvent: 24 native longs
            x.XNextEvent(display, event)
    finally:
        x.XCloseDisplay(display)


if __name__ == '__main__':
    main()
