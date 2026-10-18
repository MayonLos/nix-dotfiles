import json
import os
import subprocess
import sys
import tempfile
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
        result = self._run("demo", "editor", "--", "file.java")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("blocked", result.stderr)
        self.assertFalse(self.capture.exists())


if __name__ == "__main__":
    unittest.main()
