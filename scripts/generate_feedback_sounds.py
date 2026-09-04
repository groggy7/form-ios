#!/usr/bin/env python3
"""Generate the iOS feedback sounds that Android currently synthesizes at runtime."""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path


STEREO_SAMPLE_RATE = 48_000
ANDROID_UNDO_SAMPLE_RATE = 44_100
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "FormApp" / "Resources" / "Sounds"


def write_wav(name: str, samples: list[float], *, sample_rate: int, channels: int) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for sample in samples:
        normalized = max(-1.0, min(1.0, sample)) * 32_767
        # Kotlin's Float.toInt() truncates toward zero; match Android's undo PCM exactly.
        pcm = int(normalized) if channels == 1 else round(normalized)
        frames.extend(struct.pack("<h", pcm) * channels)

    with wave.open(str(OUTPUT_DIR / name), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(frames)


def write_stereo_wav(name: str, samples: list[float]) -> None:
    write_wav(name, samples, sample_rate=STEREO_SAMPLE_RATE, channels=2)


def write_android_undo_wav(name: str, samples: list[float]) -> None:
    write_wav(name, samples, sample_rate=ANDROID_UNDO_SAMPLE_RATE, channels=1)


def set_undo_samples() -> list[float]:
    duration = 0.18
    sample_count = int(ANDROID_UNDO_SAMPLE_RATE * duration)
    phase = 0.0
    samples: list[float] = []

    for index in range(sample_count):
        time = index / ANDROID_UNDO_SAMPLE_RATE
        frequency = 440.0 * math.pow(260.0 / 440.0, time / duration)
        phase += 2.0 * math.pi * frequency / ANDROID_UNDO_SAMPLE_RATE
        envelope = (1.0 - time / duration) * 0.25
        samples.append(math.sin(phase) * envelope)

    return samples


def workout_complete_samples() -> list[float]:
    duration = 1.2
    samples = [0.0] * int(STEREO_SAMPLE_RATE * duration)
    notes = (
        (523.25, 0.00, 0.20),
        (659.25, 0.10, 0.22),
        (783.99, 0.20, 0.25),
        (1046.50, 0.32, 0.85),
        (1318.51, 0.34, 0.75),
        (1567.98, 0.38, 0.70),
    )

    for frequency, start_seconds, note_duration in notes:
        start_index = int(start_seconds * STEREO_SAMPLE_RATE)
        note_length = min(int(note_duration * STEREO_SAMPLE_RATE), len(samples) - start_index)
        for offset in range(note_length):
            time = offset / STEREO_SAMPLE_RATE
            attack = min(1.0, time / 0.04)
            decay = math.exp(-time * 4.0)
            samples[start_index + offset] += (
                math.sin(2.0 * math.pi * frequency * time) * attack * decay * 0.28
            )

    return samples


if __name__ == "__main__":
    write_android_undo_wav("form_set_undo.wav", set_undo_samples())
    write_stereo_wav("form_workout_complete.wav", workout_complete_samples())
