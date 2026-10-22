import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


RUNNER = Path(__file__).with_name("runner.py")


class ProjectWorkbenchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.project = self.root / "项目 with spaces $'quoted'"
        self.project.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.capture = self.root / "capture.json"
        self.tmux_config = self.root / "tmuxp.json"
        self.tmux_config.write_text("{}", encoding="utf-8")
        self.registry = self.root / "projects.json"
        self.registry.write_text(
            json.dumps(
                {"demo": {"directory": str(self.project), "label": "A $project 'name'"}},
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        self._spy("kitty")
        self._spy("workspace-editor")
        self._spy("workspace-files")
        self._spy("tmuxp")
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin}:{self.env['PATH']}"
        self.env["CAPTURE"] = str(self.capture)

    def tearDown(self):
        self.temp.cleanup()

    def _spy(self, name, body=None):
        path = self.bin / name
        path.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "with open(os.environ['CAPTURE'], 'w') as out:\n"
            " json.dump({'cwd': os.getcwd(), 'argv': sys.argv[1:]}, out)\n"
            if body is None
            else body.replace("#!/usr/bin/env python3", f"#!{sys.executable}"),
            encoding="utf-8",
        )
        path.chmod(0o755)

    def _run(self, *args):
        return subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--projects-json",
                str(self.registry),
                "--kitty",
                str(self.bin / "kitty"),
                "--tmuxp",
                str(self.bin / "tmuxp"),
                *args,
            ],
            env=self.env,
            text=True,
            capture_output=True,
        )

    def test_missing_directory_fails_without_fallback(self):
        self.registry.write_text(
            json.dumps({"gone": {"directory": str(self.root / "missing"), "label": "Gone"}}),
            encoding="utf-8",
        )
        result = self._run("gone")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not exist", result.stderr)
        self.assertFalse(self.capture.exists())
        self.assertFalse((self.root / "missing").exists())

    def test_terminal_starts_kitty_in_requested_directory(self):
        result = self._run("demo")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(self.capture.read_text())
        self.assertEqual(data["cwd"], str(self.project))
        self.assertEqual(data["argv"], ["--directory", str(self.project)])

    def test_editor_preserves_argv_and_rejects_shell_metacharacters_as_data(self):
        args = ["editor", "--", "有 空格.java", "$(touch injected)", "'quote'", ""]
        result = self._run("demo", *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(self.capture.read_text())
        self.assertEqual(
            data["argv"], ["--directory", str(self.project), str(self.bin / "workspace-editor"), *args[2:]]
        )
        self.assertFalse((self.project / "injected").exists())

    def test_files_receives_project_and_exact_arguments(self):
        args = ["files", "--", "带空格", "$HOME", "'quoted'", ""]
        result = self._run("demo", *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(self.capture.read_text())
        self.assertEqual(data["cwd"], str(self.project))
        self.assertEqual(data["argv"], [str(self.project), *args[2:]])

    def test_envrc_without_direnv_fails_closed(self):
        (self.project / ".envrc").write_text("# test marker only\n", encoding="utf-8")
        (self.bin / "direnv").unlink(missing_ok=True)
        env = self.env.copy()
        env["PATH"] = f"{self.bin}:/usr/bin:/bin"
        result = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--projects-json",
                str(self.registry),
                "--kitty",
                str(self.bin / "kitty"),
                "--tmuxp",
                str(self.bin / "tmuxp"),
                "demo",
                "editor",
            ],
            env=env,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is unavailable", result.stderr)
        self.assertFalse(self.capture.exists())

    def test_terminal_rejects_command_arguments(self):
        result = self._run("demo", "terminal", "--", "do-not-run")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not accept command arguments", result.stderr)
        self.assertFalse(self.capture.exists())

    def test_untrusted_direnv_rejection_does_not_fallback(self):
        (self.project / ".envrc").write_text("# test marker only\n", encoding="utf-8")
        self._spy(
            "direnv",
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "if len(sys.argv) < 4 or sys.argv[1] != 'exec': raise SystemExit(90)\n"
            "print('direnv: error .envrc is blocked; run direnv allow to approve its content', file=sys.stderr)\n"
            "raise SystemExit(1)\n",
        )
        self._enable_workspace()
        result = self._run("demo", "workspace")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("blocked", result.stderr)
        self.assertFalse(self.capture.exists())

    def _enable_workspace(self):
        self.registry.write_text(
            json.dumps(
                {
                    "demo": {
                        "directory": str(self.project),
                        "label": "A $project 'name'",
                        "workspace": True,
                        "tmuxp_config": str(self.tmux_config),
                    }
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )

    def test_workspace_starts_tmuxp_with_the_fixed_config_in_project_directory(self):
        self._enable_workspace()
        result = self._run("demo", "workspace")
        self.assertEqual(result.returncode, 0, result.stderr)
        kitty = json.loads(self.capture.read_text())
        self.assertEqual(kitty["cwd"], str(self.project))
        self.assertEqual(
            kitty["argv"],
            ["--directory", str(self.project), str(self.bin / "tmuxp"), "load", "-y", str(self.tmux_config)],
        )

    def test_workspace_is_opt_in(self):
        result = self._run("demo", "workspace")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no workspace enabled", result.stderr)


@unittest.skipUnless(os.environ.get("WORKSPACE_TMUX_INTEGRATION") == "1", "requires tmux/tmuxp")
class TmuxpIntegrationTests(unittest.TestCase):
    def test_workspace_config_creates_and_reuses_one_fixed_session(self):
        tmux = os.environ["WORKSPACE_TMUX"]
        tmuxp = os.environ["WORKSPACE_TMUXP"]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            project = root / "project"
            project.mkdir()
            home = root / "home"
            xdg = root / "xdg"
            socket_dir = root / "sockets"
            bin_dir = root / "bin"
            for directory in (home, xdg, socket_dir, bin_dir):
                directory.mkdir()

            marker = root / "editor-invocations.jsonl"
            editor = bin_dir / "workspace-editor"
            editor.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys, time\n"
                "with open(os.environ['WORKSPACE_EDITOR_MARKER'], 'a') as marker:\n"
                " marker.write(json.dumps({'cwd': os.getcwd(), 'argv': sys.argv[1:]}) + '\\n')\n"
                "time.sleep(120)\n",
                encoding="utf-8",
            )
            editor.chmod(0o755)

            config = root / "workspace.json"
            session = f"workspace-check-{os.getpid()}"
            config.write_text(
                json.dumps(
                    {
                        "session_name": session,
                        "start_directory": str(project),
                        "windows": [
                            {
                                "window_name": "workspace",
                                "layout": "tiled",
                                "panes": [
                                    {"shell_command": "workspace-editor ."},
                                    {},
                                    {},
                                ],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            socket = socket_dir / "test.sock"
            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(xdg / "config"),
                    "XDG_DATA_HOME": str(xdg / "data"),
                    "XDG_CACHE_HOME": str(xdg / "cache"),
                    "XDG_STATE_HOME": str(xdg / "state"),
                    "TMUX_TMPDIR": str(socket_dir),
                    "WORKSPACE_EDITOR_MARKER": str(marker),
                    "PATH": os.pathsep.join(
                        [str(bin_dir), str(Path(tmux).parent), str(Path(tmuxp).parent), env.get("PATH", "")]
                    ),
                }
            )
            env.pop("TMUX", None)

            def tmux_command(*args):
                return subprocess.run(
                    [tmux, "-S", str(socket), "-f", "/dev/null", *args],
                    env=env,
                    text=True,
                    capture_output=True,
                    check=True,
                    timeout=10,
                )

            def load_workspace():
                return subprocess.run(
                    [tmuxp, "load", "-S", str(socket), "-f", "/dev/null", "-y", "-d", str(config)],
                    cwd=project,
                    env=env,
                    text=True,
                    capture_output=True,
                    check=True,
                    timeout=20,
                )

            try:
                load_workspace()
                panes = tmux_command(
                    "list-panes", "-t", f"={session}", "-F", "#{pane_index}|#{pane_current_path}"
                ).stdout.splitlines()
                self.assertEqual(len(panes), 3)
                self.assertTrue(all(line.endswith(f"|{project}") for line in panes), panes)
                # Detached tmux creation may return before the pane has
                # scheduled the editor process on a busy build machine.
                deadline = time.monotonic() + 5
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.05)
                invocations = [json.loads(line) for line in marker.read_text(encoding="utf-8").splitlines()]
                self.assertEqual(invocations, [{"cwd": str(project), "argv": ["."]}])

                load_workspace()
                windows = tmux_command("list-windows", "-t", f"={session}", "-F", "#{window_name}").stdout
                panes_after_reuse = tmux_command(
                    "list-panes", "-t", f"={session}", "-F", "#{pane_index}|#{pane_current_path}"
                ).stdout.splitlines()
                self.assertEqual(windows.splitlines(), ["workspace"])
                self.assertEqual(len(panes_after_reuse), 3)
                self.assertTrue(all(line.endswith(f"|{project}") for line in panes_after_reuse))
                self.assertEqual(marker.read_text(encoding="utf-8").count("\n"), 1)
            finally:
                subprocess.run(
                    [tmux, "-S", str(socket), "-f", "/dev/null", "kill-server"],
                    env=env,
                    text=True,
                    capture_output=True,
                    check=False,
                    timeout=10,
                )


if __name__ == "__main__":
    unittest.main()
