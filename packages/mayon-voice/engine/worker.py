#!/usr/bin/env python3
"""JSON-lines offline ASR worker for mayon-voice.

Protocol: first request is {"config": {"engine": ..., "model_dir": ...}};
subsequent requests are {"wav": "/path/to/mono-16k-pcm16.wav",
"hotwords": ["..." ]}. One JSON response is written for every request.
No model is downloaded by this process.
"""

from __future__ import annotations

import array
import argparse
import json
import os
import resource
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path
from typing import Any


class VoiceError(Exception):
    pass


def read_wav(path: str) -> tuple[array.array, int]:
    try:
        with wave.open(path, "rb") as wav:
            channels, width, rate, frames = (
                wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes()
            )
            if channels != 1 or width != 2:
                raise VoiceError("expected mono, 16-bit PCM WAV")
            if rate != 16000:
                raise VoiceError("expected 16000 Hz WAV; resampling is the recorder's responsibility")
            samples = array.array("h")
            samples.frombytes(wav.readframes(frames))
            if sys.byteorder != "little":
                samples.byteswap()
            if not samples:
                raise VoiceError("WAV contains no samples")
            return samples, rate
    except (wave.Error, OSError) as exc:
        raise VoiceError(f"cannot read WAV: {exc}") from exc


def vad_trim(samples: array.array, rate: int = 16000, vad=None) -> tuple[array.array, float]:
    """Use WebRTC VAD and preserve short inter-word pauses while trimming silence."""
    if rate not in (8000, 16000, 32000, 48000):
        raise VoiceError("WebRTC VAD supports 8, 16, 32, or 48 kHz audio")
    if vad is None:
        try:
            import webrtcvad
        except ImportError as exc:
            raise VoiceError("webrtcvad is required for VAD; no energy-only fallback is enabled") from exc
        vad = webrtcvad.Vad(2)
    frame = int(rate * 0.03)
    marked: list[bool] = []
    for start in range(0, len(samples), frame):
        part = samples[start : start + frame]
        if len(part) != frame:
            break
        marked.append(bool(vad.is_speech(part.tobytes(), rate)))
    active = [i for i, is_voice in enumerate(marked) if is_voice]
    if not active:
        return array.array("h"), 0.0
    max_gap_frames = 10  # 300ms; shorter gaps remain untouched inside a segment.
    padding_frames = 7   # 210ms around each segment to avoid clipped consonants.
    segments: list[tuple[int, int]] = []
    begin = previous = active[0]
    for index in active[1:]:
        if index - previous - 1 > max_gap_frames:
            segments.append((max(0, begin - padding_frames), min(len(marked), previous + padding_frames + 1)))
            begin = index
        previous = index
    segments.append((max(0, begin - padding_frames), min(len(marked), previous + padding_frames + 1)))
    result = array.array("h")
    inter_segment_pause = array.array("h", [0] * int(rate * 0.12))
    for index, (start_frame, end_frame) in enumerate(segments):
        if index:
            result.extend(inter_segment_pause)
        result.extend(samples[start_frame * frame : min(len(samples), end_frame * frame)])
    return result, len(active) / max(1, len(marked))


class Worker:
    def __init__(self) -> None:
        self.config: dict[str, Any] = {}
        self.recognizer = None

    def configure(self, config: dict[str, Any]) -> None:
        engine = config.get("engine", "sensevoice")
        if engine not in ("sensevoice", "paraformer", "whisper-cli"):
            raise VoiceError("engine must be sensevoice, paraformer, or whisper-cli")
        if engine == "whisper-cli" and not config.get("whisper_binary"):
            config["whisper_binary"] = "whisper-cli"
        self.config = dict(config)
        self.recognizer = None

    def _model(self):
        if self.recognizer is not None:
            return self.recognizer
        engine = self.config.get("engine", "sensevoice")
        model_dir = Path(self.config.get("model_dir", "" )).expanduser()
        if not model_dir.is_dir():
            raise VoiceError(f"model directory is missing: {model_dir}; run `mayon-voice models fetch` first")
        tokens = Path(self.config.get("tokens", str(model_dir / "tokens.txt"))).expanduser()
        model = Path(self.config.get("model", str(model_dir / "model.int8.onnx"))).expanduser()
        if not tokens.is_file() or not model.is_file():
            raise VoiceError(f"model files are missing under {model_dir}; run `mayon-voice models fetch` first")
        try:
            import sherpa_onnx
        except ImportError as exc:
            raise VoiceError("sherpa_onnx Python bindings are unavailable") from exc
        threads = int(self.config.get("num_threads", max(1, min(4, os.cpu_count() or 1))))
        provider = self.config.get("provider", "cpu")
        if provider != "cpu":
            raise VoiceError("this sherpa-onnx package is CPU-only; CUDA provider is disabled")
        if engine == "sensevoice":
            # The factory API for SenseVoice has no hotword parameters.
            self.recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
                model=str(model), language=self.config.get("language", "auto"),
                use_itn=bool(self.config.get("use_itn", True)),
                tokens=str(tokens), num_threads=threads, provider=provider,
            )
        else:
            self.recognizer = sherpa_onnx.OfflineRecognizer.from_paraformer(
                paraformer=str(model), tokens=str(tokens), num_threads=threads,
                provider=provider,
            )
        return self.recognizer

    def recognize(self, request: dict[str, Any]) -> dict[str, Any]:
        wav_path = request.get("wav")
        if not isinstance(wav_path, str):
            raise VoiceError("request requires a WAV path string")
        start = time.perf_counter()
        before = resource.getrusage(resource.RUSAGE_SELF)
        before_children = resource.getrusage(resource.RUSAGE_CHILDREN)
        before_children = resource.getrusage(resource.RUSAGE_CHILDREN)
        samples, rate = read_wav(wav_path)
        speech, ratio = vad_trim(samples, rate)
        if not speech:
            return {
                "text": "", "error": None, "engine": self.config.get("engine", "sensevoice"),
                "elapsed_ms": round((time.perf_counter() - start) * 1000, 2),
                "cpu_ms": 0.0, "rss_peak_kb": int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss),
                "speech_ratio": 0.0, "warnings": ["未检测到语音，跳过模型推理。"],
            }
        engine = self.config.get("engine", "sensevoice")
        requested_hotwords = [str(word).strip() for word in request.get("hotwords", []) if str(word).strip()]
        has_hotwords = bool(requested_hotwords or self.config.get("hotwords"))
        if requested_hotwords and engine in ("sensevoice", "paraformer"):
            # These offline factories use greedy decoding; sherpa only wires
            # hotwords for compatible modified-beam-search/transducer configs.
            requested_hotwords = []
        if engine == "whisper-cli":
            runtime_root = os.environ.get("XDG_RUNTIME_DIR")
            scratch_root = Path(runtime_root) / "mayon-voice" if runtime_root else None
            if scratch_root is not None:
                scratch_root.mkdir(mode=0o700, exist_ok=True)
            with tempfile.TemporaryDirectory(prefix="whisper-", dir=scratch_root) as folder:
                trimmed = Path(folder) / "speech.wav"
                with wave.open(str(trimmed), "wb") as wav:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)
                    wav.setframerate(rate)
                    output = array.array("h", speech)
                    if sys.byteorder != "little":
                        output.byteswap()
                    wav.writeframes(output.tobytes())
                trimmed.chmod(0o600)
                text = self._whisper(str(trimmed), requested_hotwords or self.config.get("hotwords", []))
        else:
            recognizer = self._model()
            try:
                import numpy as np
            except ImportError as exc:
                raise VoiceError("numpy is required by sherpa-onnx") from exc
            stream = recognizer.create_stream()
            audio = np.asarray(speech, dtype=np.float32) / 32768.0
            stream.accept_waveform(rate, audio)
            recognizer.decode_stream(stream)
            result = stream.result
            text = result.text.strip() if hasattr(result, "text") else str(result).strip()
        after = resource.getrusage(resource.RUSAGE_SELF)
        after_children = resource.getrusage(resource.RUSAGE_CHILDREN)
        cpu_seconds = (
            after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime
            + after_children.ru_utime + after_children.ru_stime
            - before_children.ru_utime - before_children.ru_stime
        )
        return {
            "text": text,
            "error": None,
            "engine": engine,
            "elapsed_ms": round((time.perf_counter() - start) * 1000, 2),
            "cpu_ms": round(cpu_seconds * 1000, 2),
            "rss_peak_kb": int(max(after.ru_maxrss, after_children.ru_maxrss)),
            "speech_ratio": round(ratio, 4),
            "warnings": (["该引擎的 sherpa Python API 不支持热词；本次未应用。"]
                         if has_hotwords and engine in ("sensevoice", "paraformer") else []),
        }

    def _whisper(self, wav_path: str, hotwords: Any) -> str:
        binary = str(self.config.get("whisper_binary", "whisper-cli"))
        words = [str(word).strip() for word in hotwords if str(word).strip()]
        provider = str(self.config.get("provider", "cpu"))
        if provider not in ("cpu", "cuda"):
            raise VoiceError("whisper-cli provider must be cpu or cuda")
        model = self.config.get("model")
        if not model:
            raise VoiceError("whisper-cli config requires model to point at a ggml model file")
        language = str(self.config.get("language", "zh"))
        command = [binary]
        if provider == "cpu":
            command += ["-ng", "--no-prints"]
        command += ["-m", str(Path(model).expanduser()), "-f", wav_path, "-l", language, "-t", str(self.config.get("num_threads", 4)),
                    "-nt"]
        if words:
            command += ["--prompt", ", ".join(words)]
        proc = subprocess.run(
            command,
            text=True, capture_output=True, timeout=float(self.config.get("timeout_s", 60)), check=False,
        )
        if proc.returncode:
            raise VoiceError(f"whisper-cli exited {proc.returncode}: {proc.stderr[-500:]}")
        if provider == "cuda" and "whisper_backend_init_gpu: using CUDA" not in proc.stderr:
            raise VoiceError("whisper-cli did not confirm active CUDA backend; refusing silent CPU fallback")
        return proc.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", choices=("sensevoice", "paraformer", "whisper-cli"))
    parser.add_argument("--model-dir")
    parser.add_argument("--model")
    parser.add_argument("--tokens")
    parser.add_argument("--provider", default="cpu")
    parser.add_argument("--threads", type=int)
    parser.add_argument("--language")
    parser.add_argument("--whisper-binary")
    args = parser.parse_args()
    worker = Worker()
    if args.engine:
        worker.configure({
            key: value for key, value in {
                "engine": args.engine, "model_dir": args.model_dir,
                "model": args.model, "tokens": args.tokens,
                "provider": args.provider, "num_threads": args.threads,
                "language": args.language, "whisper_binary": args.whisper_binary,
            }.items() if value is not None
        })
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise VoiceError("each line must be a JSON object")
            if "config" in request:
                config = request["config"]
                if not isinstance(config, dict):
                    raise VoiceError("config must be a JSON object")
                worker.configure(config)
                response = {"text": "", "error": None, "configured": True,
                            "engine": worker.config.get("engine", "sensevoice")}
            else:
                response = worker.recognize(request)
        except Exception as exc:
            response = {"text": "", "error": str(exc)}
        sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
