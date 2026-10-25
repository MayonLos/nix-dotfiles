from __future__ import annotations

import importlib.util
import base64
import hashlib
import io
import tempfile
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


status = load("xorg_status", ROOT / "resources/status.py")
copyq = load("rofi_copyq", ROOT / "resources/rofi-copyq.py")


class StatusTests(unittest.TestCase):
    def test_clock_is_separate_utf8_friendly_root_property_value(self):
        value = status.clock_label(status.dt.datetime(2026, 10, 25, 9, 5))
        self.assertEqual(value, "10月25日 周日 09:05")

    def test_status_contains_metrics_but_no_machine_or_network_identity(self):
        value = status.render_status(
            cpu=5,
            memory=3.8,
            online=True,
            volume=65,
            muted=False,
            battery=[(100, "Full", True)],
            ime_active=True,
        )
        for expected in ("5%", "3.8G", "65%", "100%", "养护", "中", "󰂚"):
            self.assertIn(expected, value)
        for forbidden in ("wlan", "SSID", "192.168.", "hostname", "@"):
            self.assertNotIn(forbidden, value)

    def test_status_property_is_utf8_string_and_never_shell_interpolated(self):
        calls = []

        def runner(argv, **kwargs):
            calls.append((argv, kwargs))
            return status.subprocess.CompletedProcess(argv, 0, "", "")

        sampler = status.Sampler(runner=runner)
        sampler.collect = lambda: ("colored status", "10月25日 周日 09:05")
        sampler.publish()
        commands = [argv for argv, _ in calls]
        self.assertIn(["xsetroot", "-name", "colored status"], commands)
        self.assertIn(
            ["xprop", "-root", "-f", "_MAYON_DWM_CLOCK", "8u", "-set", "_MAYON_DWM_CLOCK", "10月25日 周日 09:05"],
            commands,
        )
        self.assertTrue(all(isinstance(argv, list) for argv in commands))

    def test_proc_parsers_use_deltas_and_available_memory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stat = root / "stat"
            mem = root / "meminfo"
            stat.write_text("cpu 100 0 50 800 50 0 0 0\n", encoding="ascii")
            first = status.read_cpu(str(stat))
            stat.write_text("cpu 120 0 60 900 60 0 0 0\n", encoding="ascii")
            percent, current = status.cpu_percent(first, status.read_cpu(str(stat)))
            self.assertEqual(percent, 21)
            self.assertEqual(current, (1140, 960))
            mem.write_text("MemTotal: 8388608 kB\nMemAvailable: 4194304 kB\n", encoding="ascii")
            self.assertEqual(status.memory_gib(str(mem)), 4.0)


class CopyQSafetyTests(unittest.TestCase):
    def test_malformed_rofi_info_never_calls_copyq(self):
        with (
            patch.object(copyq, "item_snapshot", return_value=None) as snapshot,
            patch.object(copyq, "call") as call,
        ):
            for token in ("rm -rf /", "9999999999:" + "a" * 64, "4:" + "0" * 64):
                self.assertEqual(copyq.select_token(token), 2)
            snapshot.assert_called_once_with(4)
            call.assert_not_called()

    def test_snapshot_parser_decodes_full_serialized_item_and_mime_data(self):
        packed = b"serialized image item with PNG payload"
        text = b"optional label"
        output = b"7\t" + base64.b64encode(packed) + b"\t" + base64.b64encode(text) + b"\t" + base64.b64encode(b"image/png") + b"\n"
        with patch.object(copyq, "call", return_value=copyq.subprocess.CompletedProcess([], 0, output, b"")) as call:
            self.assertEqual(copyq.item_snapshot(7), (packed, text, "image/png"))
            self.assertEqual(call.call_args.args[0][:3], ["eval", "--", copyq.SNAPSHOT_SCRIPT])
            self.assertIn("pack(item)", copyq.SNAPSHOT_SCRIPT)

    def test_listing_distinguishes_image_items_and_hashes_all_serialized_mimes(self):
        packed = b"full serialized image/png bytes and metadata"
        output = io.StringIO()
        with (
            patch.object(copyq, "call", return_value=copyq.subprocess.CompletedProcess([], 0, b"1\n", b"")) as call,
            patch.object(copyq, "item_snapshot", return_value=(packed, b"", "image/png")) as snapshot,
            redirect_stdout(output),
        ):
            self.assertEqual(copyq.emit_history(), 0)
        row = output.getvalue()
        self.assertTrue(row.startswith("🖼 image/png\0info\x1f0:"), repr(row))
        self.assertIn(hashlib.sha256(packed).hexdigest(), row)
        snapshot.assert_called_once_with(0)
        call.assert_called_once_with(["size"])

    def test_changed_serialized_item_is_rejected_before_atomic_eval(self):
        shown = b"item serialization shown to rofi"
        current = b"same index but changed image data"
        token = f"2:{hashlib.sha256(shown).hexdigest()}"
        with (
            patch.object(copyq, "item_snapshot", return_value=(current, b"", "image/png")),
            patch.object(copyq, "call") as call,
        ):
            self.assertEqual(copyq.select_token(token), 2)
            call.assert_not_called()

    def test_selection_passes_snapshot_to_static_atomic_verify_then_select(self):
        packed = b"serialized image item"
        token = f"2:{hashlib.sha256(packed).hexdigest()}"
        success = copyq.subprocess.CompletedProcess([], 0, b"selected\n", b"")
        with (
            patch.object(copyq, "item_snapshot", return_value=(packed, b"", "image/png")),
            patch.object(copyq, "call", return_value=success) as call,
        ):
            self.assertEqual(copyq.select_token(token), 0)
        args = call.call_args.args[0]
        kwargs = call.call_args.kwargs
        self.assertEqual(args, ["eval", "--", copyq.SELECT_SCRIPT, "2", "-"])
        self.assertEqual(kwargs["input_data"], base64.b64encode(packed))
        self.assertIn("toBase64(pack(getItem(row))) !== expected", copyq.SELECT_SCRIPT)
        self.assertIn("select(row)", copyq.SELECT_SCRIPT)

    def test_rofi_preview_sanitizes_text_and_identifies_binary_types(self):
        self.assertEqual(copyq.preview(b"line\n\x1b[31msecret\x1b[0m"), "line[31msecret[0m")
        self.assertEqual(copyq.preview(b"", "image/jpeg"), "🖼 image/jpeg")
        self.assertEqual(copyq.preview(b"label", "image/png"), "🖼 image/png · label")
        self.assertEqual(len(copyq.preview(b"x" * 300)), 121)


if __name__ == "__main__":
    unittest.main()
