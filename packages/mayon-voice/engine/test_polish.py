import tempfile
import unittest
from pathlib import Path

from polish import polish


class PolishTests(unittest.TestCase):
    def test_missing_key_file_falls_back_to_original(self):
        self.assertEqual(polish("原始文本", "/no/such/key"), "原始文本")

    def test_empty_key_file_falls_back_to_original(self):
        with tempfile.TemporaryDirectory() as folder:
            key = Path(folder) / "key"
            key.write_text("", encoding="utf-8")
            self.assertEqual(polish("保留", str(key)), "保留")


if __name__ == "__main__":
    unittest.main()
