#!/usr/bin/env python3
"""Isolated lifecycle tests for the Xorg session supervisor."""

import json
import os
from pathlib import Path
import signal
import shutil
import sys
import subprocess
import tempfile
import time
import unittest


SOURCE = Path(__file__).parents[1] / "session"


class XorgSessionSupervisorTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.calls = self.root / "systemctl.log"
        self.dbus_calls = self.root / "dbus.log"
        self.active = self.root / "active-targets"
        self.dwm_started = self.root / "dwm-started"
        self.dwm_env = self.root / "dwm-env.json"
        self.dwm_pid = self.root / "dwm.pid"
        self.target_started = self.root / "target-started"
        self.xprop_ready = self.root / "xprop-ready"
        self.hm_vars = self.root / "hm-session-vars.sh"
        self.hm_vars.write_text(
            'if [ -n "${__HM_SESS_VARS_SOURCED-}" ]; then return; fi\n'
            'export __HM_SESS_VARS_SOURCED=1\n'
            'export HM_PUBLIC_TEST=value-from-hm\n'
            'export NIXOS_OZONE_WL=1\n'
            # Match HM's generated optional-path exports. A fresh login need
            # not define either variable; sourcing under nounset aborts it.
            'export QT_PLUGIN_PATH="/hm/qt/plugins${QT_PLUGIN_PATH:+:}$QT_PLUGIN_PATH"\n'
            'export XCURSOR_PATH="/hm/icons${XCURSOR_PATH:+:}$XCURSOR_PATH"\n'
        )
        self.manager_env = self.root / "manager-environment"
        self.manager_env.write_text(
            "MANGO_SOCKET=private-mango-value\n"
            "HYPRLAND_INSTANCE_SIGNATURE=private-hypr-value\n"
            "OTHER_SECRET=do-not-touch\n"
        )

        self.systemctl = self.write_executable(
            "systemctl",
            """#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_SYSTEMCTL_LOG"
	if [ "$1" = --user ] && [ "$2" = show-environment ]; then
	  cat "$TEST_MANAGER_ENV"
	  exit 0
	fi
	if [ "$1" = --user ] && [ "$2" = start ] && [ "$3" = xorg-session.target ]; then
	  test -f "$TEST_XPROP_READY" || exit 9
	  test "$TEST_TARGET_FAIL" != 1 || exit 10
	  touch "$TEST_TARGET_STARTED"
	  exit 0
	fi
if [ "$1" = --user ] && [ "$2" = is-active ]; then
  grep -Fxq "$4" "$TEST_ACTIVE_TARGETS"
  exit $?
fi
exit 0
""",
        )
        self.dbus = self.write_executable(
            "dbus-update-activation-environment",
            """#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_DBUS_LOG"
if [ "$1" = --systemd ] && [ "${TEST_DBUS_FAIL:-0}" = 1 ]; then exit 1; fi
exit 0
""",
        )
        self.dwm = self.write_executable(
            "dwm",
            f"""#!{sys.executable}
import json, os, signal, sys, time
from pathlib import Path
root = Path(os.environ['TEST_ROOT'])
def stop(signum, frame):
    (root / 'dwm-signal').write_text(str(signum))
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
(root / 'dwm-started').write_text('yes')
(root / 'dwm.pid').write_text(str(os.getpid()))
(root / 'dwm-env.json').write_text(json.dumps(dict(os.environ)))
try:
    os.fstat(9)
    (root / 'dwm-inherited-lock').write_text('bad')
except OSError:
    pass
if os.environ.get('TEST_DWM_WAIT') == '1':
    while True:
        time.sleep(0.05)
if os.environ.get('TEST_DWM_EXIT_IMMEDIATELY') == '1':
    sys.exit(int(os.environ.get('TEST_DWM_EXIT', '7')))
deadline = time.monotonic() + 3
while not (root / 'target-started').exists() and time.monotonic() < deadline:
    time.sleep(0.01)
sys.exit(int(os.environ.get('TEST_DWM_EXIT', '23')))
""",
        )
        self.xprop = self.write_executable(
            "xprop",
            """#!/bin/sh
if [ "$TEST_XPROP_MODE" != ready ]; then
  exit 1
fi
test -f "$TEST_ROOT/dwm-started" || exit 1
case "$*" in
  "-root -notype _NET_SUPPORTING_WM_CHECK")
    printf '_NET_SUPPORTING_WM_CHECK = 0x1234\\n'
    ;;
  "-id 0x1234 -notype _NET_WM_NAME")
    touch "$TEST_XPROP_READY"
    printf '_NET_WM_NAME = "dwm"\\n'
    ;;
esac
""",
        )

        replacements = {
            "@runtimeShell@": os.environ.get("XORG_TEST_SHELL", shutil.which("bash")),
            "@systemctl@": str(self.systemctl),
            "@dbusUpdateActivationEnvironment@": str(self.dbus),
            "@dwm@": str(self.dwm),
            "@xprop@": str(self.xprop),
            "@sleep@": shutil.which("sleep"),
            "@stat@": shutil.which("stat"),
            "@flock@": shutil.which("flock"),
            "@hmSessionVars@": str(self.hm_vars),
            "@defaultOzone@": "1",
            "@defaultXModifiers@": "'@im=fcitx'",
        }
        script = SOURCE.read_text()
        for old, new in replacements.items():
            script = script.replace(old, new)
        self.script = self.root / "xorg-session"
        self.script.write_text(script)
        self.script.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def write_executable(self, name, content):
        path = self.root / name
        path.write_text(content)
        path.chmod(0o755)
        return path

    def environment(self, **extra):
        # Do not copy the developer's credentials/activation environment into
        # the fake WM or a failing assertion. Only these test inputs are needed.
        env = {"PATH": os.environ["PATH"], "HOME": str(self.root), "LANG": "C.UTF-8"}
        env.update(
            {
                "TEST_ROOT": str(self.root),
                "TEST_SYSTEMCTL_LOG": str(self.calls),
                "TEST_DBUS_LOG": str(self.dbus_calls),
                "TEST_ACTIVE_TARGETS": str(self.active),
                "TEST_MANAGER_ENV": str(self.manager_env),
                "TEST_TARGET_STARTED": str(self.target_started),
                "TEST_XPROP_READY": str(self.xprop_ready),
                "TEST_XPROP_MODE": "ready",
                "TEST_TARGET_FAIL": "0",
                "DISPLAY": ":88",
                "XAUTHORITY": str(self.root / "Xauthority"),
                "XDG_SESSION_TYPE": "x11",
                "XDG_RUNTIME_DIR": str(self.runtime),
                "WAYLAND_DISPLAY": "wayland-9",
                "MANGO_SOCKET": "mango-test",
                "HYPRLAND_INSTANCE_SIGNATURE": "hypr-test",
                "NIXOS_OZONE_WL": "1",
                "TEST_SECRET_DO_NOT_IMPORT": "private-value",
            }
        )
        env.update(extra)
        return env

    def log(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_refuses_existing_graphical_session_without_starting_dwm(self):
        self.active.write_text("graphical-session.target\n")
        result = subprocess.run(
            [str(self.script)], env=self.environment(), text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("refusing to start", result.stderr)
        self.assertFalse(self.dwm_started.exists())
        self.assertFalse(any("import-environment" in call for call in self.log()))
        self.assertFalse(any("stop" in call for call in self.log()))

    def test_sets_x11_environment_and_cleans_activation_state(self):
        result = subprocess.run(
            [str(self.script)], env=self.environment(), text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 23, result.stderr)
        child_env = json.loads(self.dwm_env.read_text())
        expected = {
            "QT_QPA_PLATFORM": "xcb",
            "GDK_BACKEND": "x11",
            "GTK_IM_MODULE": "fcitx",
            "QT_IM_MODULE": "fcitx",
            "XMODIFIERS": "@im=fcitx",
            "XDG_CURRENT_DESKTOP": "dwm",
            "XDG_SESSION_TYPE": "x11",
            "XDG_SESSION_DESKTOP": "dwm",
            "DESKTOP_SESSION": "xorg-dwm",
            "MOZ_ENABLE_WAYLAND": "0",
            "ELECTRON_OZONE_PLATFORM_HINT": "x11",
            "HM_PUBLIC_TEST": "value-from-hm",
        }
        for name, value in expected.items():
            self.assertEqual(child_env.get(name), value)
        self.assertFalse((self.root / "dwm-inherited-lock").exists(), "dwm must not inherit supervisor lock FD9")
        self.assertEqual(child_env.get("NIXOS_OZONE_WL"), "")
        self.assertEqual(child_env.get("__HM_SESS_VARS_SOURCED"), "1")
        for name in ("WAYLAND_DISPLAY", "MANGO_SOCKET", "HYPRLAND_INSTANCE_SIGNATURE"):
            self.assertTrue(name not in child_env, f"{name} leaked into the fake WM")

        joined = "\n".join(self.log())
        self.assertIn("import-environment DISPLAY XAUTHORITY", joined)
        self.assertIn("unset-environment DISPLAY XAUTHORITY", joined)
        self.assertIn("QT_QPA_PLATFORM GDK_BACKEND GTK_IM_MODULE QT_IM_MODULE XMODIFIERS", joined)
        self.assertIn("unset-environment WAYLAND_DISPLAY MANGO_SOCKET HYPRLAND_INSTANCE_SIGNATURE", joined)
        self.assertIn("NIXOS_OZONE_WL", joined)
        self.assertNotIn("private-mango-value", joined)
        self.assertNotIn("private-hypr-value", joined)
        self.assertNotIn("OTHER_SECRET", joined)
        self.assertIn("stop xorg-session.target", joined)
        self.assertIn("start xorg-session.target", joined)
        self.assertTrue(self.target_started.exists())
        self.assertTrue(self.xprop_ready.exists())
        self.assertFalse((self.runtime / "nix-dotfiles-xorg" / "session.pid").exists())
        self.assertIn("stop graphical-session.target graphical-session-pre.target", joined)
        self.assertNotIn("--all", joined)
        dbus = self.dbus_calls.read_text()
        self.assertIn("QT_QPA_PLATFORM=xcb", dbus)
        self.assertIn("GTK_IM_MODULE=fcitx", dbus)
        self.assertIn("NIXOS_OZONE_WL=", dbus)
        self.assertIn("WAYLAND_DISPLAY=", dbus)
        self.assertNotIn("TEST_SECRET_DO_NOT_IMPORT", dbus)
        self.assertNotIn("private-value", dbus)
        cleanup_dbus = dbus.splitlines()[-1]
        self.assertNotIn("--systemd", cleanup_dbus)
        self.assertIn("QT_QPA_PLATFORM=", cleanup_dbus)
        self.assertIn("GDK_BACKEND=*", cleanup_dbus)
        self.assertIn("NIXOS_OZONE_WL=1", cleanup_dbus)
        self.assertIn("XMODIFIERS=@im=fcitx", cleanup_dbus)
        self.assertIn("set-environment NIXOS_OZONE_WL=1", joined)

    def test_dbus_import_failure_restores_static_defaults(self):
        result = subprocess.run(
            [str(self.script)], env=self.environment(TEST_DBUS_FAIL="1"),
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.dwm_started.exists())
        self.assertIn("set-environment NIXOS_OZONE_WL=1 XMODIFIERS=@im=fcitx", "\n".join(self.log()))
        cleanup = self.dbus_calls.read_text().splitlines()[-1]
        self.assertIn("GDK_BACKEND=*", cleanup)
        self.assertIn("XMODIFIERS=@im=fcitx", cleanup)

    def test_requires_x11_display(self):
        env = self.environment()
        env.pop("DISPLAY")
        result = subprocess.run(
            [str(self.script)], env=env, text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("DISPLAY is unset", result.stderr)
        self.assertFalse(self.dwm_started.exists())
        self.assertFalse(any("import-environment" in call for call in self.log()))

    def test_forwards_term_and_skips_global_cleanup_if_mango_takes_over(self):
        process = subprocess.Popen(
            [str(self.script)],
            env=self.environment(TEST_DWM_WAIT="1"),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 5
        while not self.dwm_pid.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(self.dwm_pid.exists(), "dwm child did not start")
        self.active.write_text("mango-session.target\n")
        process.send_signal(signal.SIGTERM)
        _, stderr = process.communicate(timeout=5)

        self.assertEqual(process.returncode, 143, stderr)
        self.assertEqual((self.root / "dwm-signal").read_text(), str(signal.SIGTERM))
        joined = "\n".join(self.log())
        self.assertIn("stop xorg-session.target", joined)
        self.assertNotIn("stop graphical-session.target graphical-session-pre.target", joined)
        self.assertFalse(any("unset-environment DISPLAY" in call for call in self.log()))

    def test_dwm_start_failure_never_starts_session_target(self):
        result = subprocess.run(
            [str(self.script)],
            env=self.environment(
                TEST_XPROP_MODE="none", TEST_DWM_EXIT_IMMEDIATELY="1", TEST_DWM_EXIT="7"
            ),
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertFalse(self.target_started.exists())
        self.assertFalse(any("start xorg-session.target" in call for call in self.log()))

    def test_target_start_failure_terminates_dwm_and_cleans_session(self):
        result = subprocess.run(
            [str(self.script)],
            env=self.environment(TEST_TARGET_FAIL="1", TEST_DWM_WAIT="1"),
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertFalse(self.target_started.exists())
        self.assertEqual((self.root / "dwm-signal").read_text(), str(signal.SIGTERM))
        self.assertFalse((self.runtime / "nix-dotfiles-xorg" / "session.pid").exists())

    def test_hm_source_failure_does_not_import_or_start_session(self):
        self.hm_vars.write_text('return 1\n')
        result = subprocess.run([str(self.script)], env=self.environment(), text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('could not load Home Manager', result.stderr)
        self.assertFalse(self.dwm_started.exists())
        self.assertFalse(any('import-environment' in call for call in self.log()))
        self.assertFalse((self.runtime / 'nix-dotfiles-xorg/session.pid').exists())

    def test_concurrent_supervisor_is_rejected_before_environment_import(self):
        self.hm_vars.write_text(self.hm_vars.read_text() + '\ntouch "$TEST_ROOT/hm-blocked"\nwhile [ ! -e "$TEST_ROOT/hm-release" ]; do sleep 0.02; done\n')
        process = subprocess.Popen([str(self.script)], env=self.environment(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not (self.root / "hm-blocked").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / "hm-blocked").exists(), "first supervisor did not reach HM loading")
            self.assertFalse((self.runtime / "nix-dotfiles-xorg/session.pid").exists())
            second = subprocess.run([str(self.script)], env=self.environment(), capture_output=True, text=True, timeout=5)
            self.assertEqual(second.returncode, 1, second.stderr)
            self.assertIsNone(process.poll(), "first supervisor was disturbed")
            self.assertFalse(any("import-environment" in call or "stop " in call for call in self.log()))
            (self.root / "hm-release").touch()
            _, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 23, stderr)
        finally:
            (self.root / "hm-release").touch()
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=5)

    def test_exit_command_refuses_reused_pid(self):
        pidfile = self.runtime / "nix-dotfiles-xorg" / "session.pid"
        pidfile.parent.mkdir(mode=0o700)
        pidfile.write_text(f"{os.getpid()} 0\n")
        result = subprocess.run(
            [str(self.script), "--exit"], env=self.environment(), text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("PID has been reused", result.stderr)

    def test_refusing_existing_supervisor_does_not_stop_its_targets(self):
        stat_fields = Path(f"/proc/{os.getpid()}/stat").read_text().split()
        pidfile = self.runtime / "nix-dotfiles-xorg" / "session.pid"
        pidfile.parent.mkdir(mode=0o700)
        pidfile.write_text(f"{os.getpid()} {stat_fields[21]}\n")
        result = subprocess.run(
            [str(self.script)], env=self.environment(), text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("already running", result.stderr)
        self.assertFalse(any("stop" in call for call in self.log()))
        self.assertFalse(any("import-environment" in call for call in self.log()))
        self.assertTrue(pidfile.exists())

    def test_exit_command_signals_only_recorded_session_pid(self):
        child = subprocess.Popen([shutil.which("sleep"), "30"])
        try:
            stat_fields = Path(f"/proc/{child.pid}/stat").read_text().split()
            starttime = stat_fields[21]
            pidfile = self.runtime / "nix-dotfiles-xorg" / "session.pid"
            pidfile.parent.mkdir(mode=0o700)
            pidfile.write_text(f"{child.pid} {starttime}\n")
            result = subprocess.run(
                [str(self.script), "--exit"], env=self.environment(), text=True, capture_output=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(child.wait(timeout=5), -signal.SIGTERM)
        finally:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
