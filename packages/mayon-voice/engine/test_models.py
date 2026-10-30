import hashlib
import io
import tarfile
import tempfile
import unittest
from pathlib import Path

from models import unpack_verified


def fixture_archive(path: Path) -> str:
    with tarfile.open(path, "w:bz2") as tar:
        root = tarfile.TarInfo("fixture/")
        root.type = tarfile.DIRTYPE
        root.mode = 0o755
        tar.addfile(root)
        for name, data in (("model.int8.onnx", b"tiny-model-fixture"), ("tokens.txt", b"token 0\n")):
            info = tarfile.TarInfo(f"fixture/{name}")
            info.size = len(data)
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(data))
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ModelFetcherTests(unittest.TestCase):
    def test_local_fixture_verifies_hash_extracts_and_sets_private_modes(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            archive = base / "fixture.tar.bz2"
            checksum = fixture_archive(archive)
            destination = base / "models" / "sensevoice"
            unpack_verified(archive, destination, checksum, "model.int8.onnx")
            self.assertEqual((destination / "model.int8.onnx").read_bytes(), b"tiny-model-fixture")
            self.assertEqual((destination / "tokens.txt").read_bytes(), b"token 0\n")
            self.assertEqual(destination.stat().st_mode & 0o777, 0o700)
            self.assertEqual((destination / "tokens.txt").stat().st_mode & 0o777, 0o600)

    def test_hash_mismatch_does_not_create_destination(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            archive = base / "fixture.tar.bz2"
            fixture_archive(archive)
            destination = base / "models" / "sensevoice"
            with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                unpack_verified(archive, destination, "0" * 64, "model.int8.onnx")
            self.assertFalse(destination.exists())

    def test_existing_destination_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            archive = base / "fixture.tar.bz2"
            checksum = fixture_archive(archive)
            destination = base / "models" / "sensevoice"
            destination.mkdir(parents=True)
            with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
                unpack_verified(archive, destination, checksum, "model.int8.onnx")


if __name__ == "__main__":
    unittest.main()
