#!/usr/bin/env python3
"""Isolated runtime checks for the optional Hyprland session wrapper."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


class HyprlandSessionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if len(sys.argv) != 3:
            raise RuntimeError("usage: test_hyprland_session.py BASH WRAPPER_SOURCE")
        cls.bash = sys.argv[1]
        source = Path(sys.argv[2]).read_text()
        if "@SYSTEMCTL@" not in source:
            raise RuntimeError("session wrapper source has no @SYSTEMCTL@ placeholder")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hyprland-session-test-")
        self.root = Path(self.temp.name)
        self.active_dir = self.root / "active"
        self.active_dir.mkdir()
        self.systemctl_log = self.root / "systemctl.log"
        self.launch_log = self.root / "launcher.log"

        self.fake_systemctl = self.root / "systemctl"
        self.fake_systemctl.write_text(
            "\n".join(
                [
                    f"#!{self.bash}",
                    'if [[ $2 == is-active ]]; then',
                    '  [[ -e "$FAKE_ACTIVE_DIR/$4" ]] && exit 0',
                    "  exit 3",
                    "fi",
                    'printf \'%s\\n\' "$*" >> "$FAKE_SYSTEMCTL_LOG"',
                    "exit 0",
                    "",
                ]
            )
        )
        self.fake_systemctl.chmod(0o755)

        self.wrapper = self.root / "hyprland-session"
        source = Path(sys.argv[2]).read_text()
        self.wrapper.write_text(source.replace("@SYSTEMCTL@", str(self.fake_systemctl)))
        self.wrapper.chmod(0o755)

        self.env = os.environ.copy()
        self.env.update(
            {
                "FAKE_ACTIVE_DIR": str(self.active_dir),
                "FAKE_SYSTEMCTL_LOG": str(self.systemctl_log),
                "LAUNCH_LOG": str(self.launch_log),
            }
        )

    def tearDown(self):
        self.temp.cleanup()

    def launcher(self, body):
        path = self.root / "launcher"
        path.write_text(f"#!{self.bash}\n{body}\n")
        path.chmod(0o755)
        return path

    def run_wrapper(self, launcher, *args, **kwargs):
        return subprocess.run(
            [self.bash, str(self.wrapper), str(launcher), *map(str, args)],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=5,
            **kwargs,
        )

    def test_refuses_each_active_session_target(self):
        for target in (
            "mango-session.target",
            "hyprland-session.target",
            "graphical-session.target",
        ):
            with self.subTest(target=target):
                self.launch_log.unlink(missing_ok=True)
                self.systemctl_log.unlink(missing_ok=True)
                (self.active_dir / target).touch()
                result = self.run_wrapper(
                    self.launcher('printf called > "$LAUNCH_LOG"; exit 0')
                )
                self.assertEqual(result.returncode, 1)
                self.assertIn("another graphical session is already active", result.stderr)
                self.assertFalse(self.launch_log.exists())
                self.assertFalse(self.systemctl_log.exists())
                (self.active_dir / target).unlink()

    def test_preserves_nonzero_exit_and_stops_session_targets(self):
        result = self.run_wrapper(
            self.launcher('printf "%s\\n" "$@" > "$LAUNCH_LOG"; exit 37'),
            "argument-one",
            "argument-two",
        )
        self.assertEqual(result.returncode, 37)
        self.assertEqual(self.launch_log.read_text().splitlines(), ["argument-one", "argument-two"])
        self.assertIn(
            "--user stop hyprland-session.target graphical-session.target",
            self.systemctl_log.read_text(),
        )
        self.assertIn(
            "--user unset-environment HYPRLAND_INSTANCE_SIGNATURE",
            self.systemctl_log.read_text(),
        )

    def test_forwards_term_and_int_waits_and_cleans_up(self):
        for received, requested in ((signal.SIGTERM, "TERM"), (signal.SIGINT, "INT")):
            with self.subTest(signal=requested):
                child_log = self.root / f"child-{requested}.log"
                launcher = self.root / f"launcher-{requested}.py"
                launcher.write_text(
                    f"#!{sys.executable}\n"
                    "import signal, sys, time\n"
                    "log = sys.argv[1]\n"
                    f"wanted = signal.SIG{requested}\n"
                    "def handle(signum, frame):\n"
                    "    with open(log, 'a') as output: output.write('received\\n')\n"
                    "    time.sleep(0.2)\n"
                    "    with open(log, 'a') as output: output.write('finished\\n')\n"
                    "    raise SystemExit(19)\n"
                    "signal.signal(wanted, handle)\n"
                    "open(log, 'w').write('ready\\n')\n"
                    "while True: time.sleep(0.05)\n"
                )
                launcher.chmod(0o755)
                process = subprocess.Popen(
                    [self.bash, str(self.wrapper), str(launcher), str(child_log)],
                    env=self.env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if child_log.exists() and child_log.read_text().startswith("ready\n"):
                        break
                    if process.poll() is not None:
                        self.fail(f"wrapper exited before launcher was ready ({process.returncode})")
                    time.sleep(0.01)
                else:
                    process.kill()
                    self.fail("launcher did not become ready")

                process.send_signal(received)
                _, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 19, stderr)
                self.assertEqual(
                    child_log.read_text().splitlines(), ["ready", "received", "finished"]
                )
                self.assertIn(
                    "--user stop hyprland-session.target graphical-session.target",
                    self.systemctl_log.read_text(),
                )
                self.assertIn(
                    "--user unset-environment HYPRLAND_INSTANCE_SIGNATURE",
                    self.systemctl_log.read_text(),
                )
                self.systemctl_log.unlink(missing_ok=True)

    def test_mango_started_before_exit_keeps_graphical_targets(self):
        launcher = self.launcher(
            'touch "$FAKE_ACTIVE_DIR/mango-session.target"; exit 41'
        )
        result = self.run_wrapper(launcher)
        self.assertEqual(result.returncode, 41)
        self.assertTrue((self.active_dir / "mango-session.target").exists())
        self.assertFalse(self.systemctl_log.exists())


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
