import array
import json
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock
import wave
from pathlib import Path

from worker import VoiceError, Worker, read_wav, vad_trim


class AmplitudeVad:
    def is_speech(self, frame, rate):
        samples = array.array("h")
        samples.frombytes(frame)
        return max((abs(value) for value in samples), default=0) > 1000


class WorkerTests(unittest.TestCase):
    def test_webrtc_vad_trims_edges_and_preserves_speech(self):
        samples = array.array("h", [0] * (20 * 480) + [12000] * (4 * 480) + [0] * (20 * 480))
        speech, ratio = vad_trim(samples, vad=AmplitudeVad())
        self.assertEqual(len(speech), 18 * 480)
        self.assertAlmostEqual(ratio, 4 / 44)

    def test_read_wav_enforces_expected_recorder_format(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "tone.wav"
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(16000)
                wav.writeframes(array.array("h", [0, 1, -1] * 100).tobytes())
            data, rate = read_wav(str(path))
            self.assertEqual(rate, 16000)
            self.assertEqual(len(data), 300)

    def test_silence_is_empty_success_without_loading_model(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "silence.wav"
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(16000)
                wav.writeframes(array.array("h", [0] * 16000).tobytes())
            worker = Worker()
            worker.configure({"engine": "sensevoice", "model_dir": "/does/not/exist"})
            with mock.patch.dict(sys.modules, {"webrtcvad": types.SimpleNamespace(Vad=lambda _: AmplitudeVad())}):
                response = worker.recognize({"wav": str(path)})
            self.assertEqual(response["text"], "")
            self.assertIsNone(response["error"])
            self.assertIn("warnings", response)

    def test_whisper_cpu_forces_cpu_and_cuda_requires_backend_confirmation(self):
        worker = Worker()
        worker.configure({"engine": "whisper-cli", "model": "/models/model.bin", "whisper_binary": "whisper-cli"})
        completed = types.SimpleNamespace(returncode=0, stdout="文本", stderr="")
        with mock.patch("worker.subprocess.run", return_value=completed) as run:
            self.assertEqual(worker._whisper("audio.wav", []), "文本")
            self.assertIn("-ng", run.call_args.args[0])

        worker.configure({"engine": "whisper-cli", "model": "/models/model.bin", "provider": "cuda"})
        with mock.patch("worker.subprocess.run", return_value=completed) as run:
            with self.assertRaisesRegex(VoiceError, "did not confirm active CUDA"):
                worker._whisper("audio.wav", [])
            self.assertNotIn("-ng", run.call_args.args[0])
            self.assertNotIn("--no-prints", run.call_args.args[0])

        completed.stderr = "whisper_backend_init_gpu: using CUDA0 backend"
        with mock.patch("worker.subprocess.run", return_value=completed):
            self.assertEqual(worker._whisper("audio.wav", []), "文本")

    def test_jsonl_worker_returns_error_field_without_model_download(self):
        script = Path(__file__).with_name("worker.py")
        process = subprocess.run(
            [sys.executable, str(script)],
            input='{"config":{"engine":"sensevoice","model_dir":"/nonexistent"}}\n'
                  '{"wav":"/nonexistent.wav"}\n',
            text=True,
            capture_output=True,
            check=True,
            env={"PATH": "/usr/bin:/bin"},
        )
        rows = [json.loads(line) for line in process.stdout.splitlines()]
        self.assertTrue(rows[0]["configured"])
        self.assertIn("error", rows[1])
        self.assertFalse(rows[1]["text"])


if __name__ == "__main__":
    unittest.main()
