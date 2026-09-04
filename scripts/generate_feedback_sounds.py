#!/usr/bin/env python3
"""Generate the iOS feedback sounds that Android currently synthesizes at runtime."""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 48_000
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "FormApp" / "Resources" / "Sounds"


def write_stereo_wav(name: str, samples: list[float]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for sample in samples:
        pcm = round(max(-1.0, min(1.0, sample)) * 32_767)
        frames.extend(struct.pack("<hh", pcm, pcm))

    with wave.open(str(OUTPUT_DIR / name), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)


def set_undo_samples() -> list[float]:
    duration = 0.18
    sample_count = int(SAMPLE_RATE * duration)
    phase = 0.0
    samples: list[float] = []

    for index in range(sample_count):
        time = index / SAMPLE_RATE
        frequency = 440.0 * math.pow(260.0 / 440.0, time / duration)
        phase += 2.0 * math.pi * frequency / SAMPLE_RATE
        envelope = 1.0 - time / duration
        # Fundamental plus presence harmonic so tone carries cleanly on phone speakers
        tone = math.sin(phase) + 0.35 * math.sin(2.0 * phase)
        samples.append(tone * envelope * 0.55)

    return samples


def workout_complete_samples() -> list[float]:
    duration = 1.2
    samples = [0.0] * int(SAMPLE_RATE * duration)
    notes = (
        (523.25, 0.00, 0.20),
        (659.25, 0.10, 0.22),
        (783.99, 0.20, 0.25),
        (1046.50, 0.32, 0.85),
        (1318.51, 0.34, 0.75),
        (1567.98, 0.38, 0.70),
    )

    for frequency, start_seconds, note_duration in notes:
        start_index = int(start_seconds * SAMPLE_RATE)
        note_length = min(int(note_duration * SAMPLE_RATE), len(samples) - start_index)
        for offset in range(note_length):
            time = offset / SAMPLE_RATE
            attack = min(1.0, time / 0.04)
            decay = math.exp(-time * 4.0)
            samples[start_index + offset] += (
                math.sin(2.0 * math.pi * frequency * time) * attack * decay * 0.28
            )

    return samples


if __name__ == "__main__":
    write_stereo_wav("form_set_undo.wav", set_undo_samples())
    write_stereo_wav("form_workout_complete.wav", workout_complete_samples())
