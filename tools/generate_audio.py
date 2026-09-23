#!/usr/bin/env python3
"""Reproduce MIREWARD's original PCM sound assets using only Python's library."""

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import random
import struct
import wave
import zlib


RATE = 22050
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
TAU = 2 * math.pi


def silence(seconds):
    return [0.0] * round(seconds * RATE)


def tone(samples, start, duration, frequency, gain, end_frequency=None, decay=4):
    """Soft attack and decaying partial, optionally bending in frequency."""
    offset = round(start * RATE)
    count = round(duration * RATE)
    end_frequency = frequency if end_frequency is None else end_frequency
    for i in range(min(count, len(samples) - offset)):
        t = i / RATE
        u = i / count
        phase = TAU * (frequency * t + (end_frequency - frequency) * t * t / (2 * duration))
        envelope = min(1, t / 0.006) * (1 - u) * math.exp(-decay * u)
        samples[offset + i] += gain * envelope * math.sin(phase)


def noise(samples, rng, start, duration, gain, smoothing=0.2):
    offset = round(start * RATE)
    count = round(duration * RATE)
    filtered = 0.0
    for i in range(min(count, len(samples) - offset)):
        filtered += smoothing * (rng.uniform(-1, 1) - filtered)
        u = i / count
        envelope = min(1, i / (RATE * 0.008)) * (1 - u) ** 2
        samples[offset + i] += gain * envelope * filtered


def bell(samples, start, frequency, gain=0.2, duration=1.5):
    for ratio, strength in [(1, 1), (2.01, 0.28), (2.76, 0.12), (4.07, 0.035)]:
        tone(samples, start, duration, frequency * ratio, gain * strength, decay=3.8)


def cue(name):
    rng = random.Random(zlib.crc32(name.encode()))
    durations = {"death": 0.8, "door": 0.65, "bandage": 0.8,
                 "bell_low": 1.4, "bell_chime": 1.6, "bell_solved": 2.5,
                 "quest_complete": 2.1, "distant_bell": 3.2}
    samples = silence(durations.get(name, 0.4))
    if name.startswith("footstep_"):
        frequency, smoothing = {"dirt": (88, 0.35), "stone": (170, 0.7), "wood": (120, 0.22)}[name[9:]]
        noise(samples, rng, 0, 0.2, 0.28, smoothing)
        tone(samples, 0, 0.16, frequency, 0.17, decay=6)
    elif name == "swing":
        noise(samples, rng, 0, 0.32, 0.4, 0.12)
    elif name in ("metal_impact", "shield_block", "parry", "guard_break"):
        frequency = {"metal_impact": 360, "shield_block": 180, "parry": 620, "guard_break": 95}[name]
        noise(samples, rng, 0, 0.12, 0.24, 0.5)
        bell(samples, 0.008, frequency, 0.24, 0.38)
        if name == "guard_break":
            tone(samples, 0.05, 0.3, 190, 0.16, end_frequency=65)
    elif name in ("hurt", "death"):
        tone(samples, 0, len(samples) / RATE, 145, 0.22, end_frequency=55, decay=2)
        noise(samples, rng, 0, 0.28, 0.18, 0.08)
    elif name in ("pickup", "ui_accept", "ui_back"):
        frequency = {"pickup": 390, "ui_accept": 330, "ui_back": 250}[name]
        tone(samples, 0, 0.16, frequency, 0.16, decay=5)
        tone(samples, 0.055, 0.2, frequency * (1.25 if name != "ui_back" else 0.8), 0.1)
    elif name in ("chest", "door"):
        noise(samples, rng, 0, 0.28, 0.26, 0.14)
        tone(samples, 0, 0.2, 94, 0.2)
        tone(samples, 0.09, 0.25, 220, 0.07, end_frequency=145)
    elif name == "bandage":
        for start in (0, 0.2, 0.43):
            noise(samples, rng, start, 0.28, 0.25, 0.22)
    elif name in ("bell_low", "bell_chime", "distant_bell"):
        bell(samples, 0, {"bell_low": 140, "bell_chime": 330, "distant_bell": 165}[name],
             0.22, len(samples) / RATE)
    elif name in ("bell_solved", "quest_complete"):
        for i, frequency in enumerate((220, 275, 330)):
            bell(samples, i * 0.25, frequency, 0.15, 1.7)
    else:
        raise ValueError(name)
    return samples


def ambience(zone):
    rng = random.Random(zlib.crc32(zone.encode()))
    samples = silence(12)
    low = 0.0
    for i in range(len(samples)):
        low += 0.035 * (rng.uniform(-1, 1) - low)
        samples[i] = low * (0.2 + 0.05 * math.sin(TAU * i / len(samples)))
    if zone == "village":
        for start in (1.1, 2.9, 4.7, 8.2, 10):
            bell(samples, start, 290, 0.055, 0.5)
            noise(samples, rng, start, 0.25, 0.07, 0.2)
        for start in (0.2, 3.6, 6.8, 9.5):
            noise(samples, rng, start, 2, 0.14, 0.12)
    elif zone == "monastery":
        for start in (1.4, 1.8, 6.1):
            tone(samples, start, 0.32, 430, 0.055, end_frequency=295, decay=1)
            noise(samples, rng, start, 0.28, 0.04, 0.5)
        bell(samples, 8.2, 165, 0.055, 3.1)
    elif zone in ("crypt", "undercroft"):
        for start in (0.8, 3.1, 5.9, 9.7):
            tone(samples, start, 0.35, 620 if zone == "crypt" else 780, 0.055, end_frequency=420)
            tone(samples, start + 0.15, 0.45, 310, 0.022)
    elif zone == "inn":
        for _ in range(28):
            noise(samples, rng, rng.uniform(0.2, 11.5), 0.08, 0.09, 0.65)
        tone(samples, 4.5, 0.8, 85, 0.035, end_frequency=65)
    elif zone != "forest":
        raise ValueError(zone)
    return samples


def music():
    samples = silence(24)
    for frequency, gain in ((55, 0.035), (110, 0.04), (165, 0.025)):
        for i in range(len(samples)):
            samples[i] += gain * math.sin(TAU * frequency * i / RATE) * (0.75 + 0.25 * math.sin(TAU * i / len(samples)))
    # Original sparse six-note phrase over a restrained low drone.
    for start, frequency in zip((1, 5, 9, 13, 17, 20), (220, 293.6648, 261.6256, 196, 246.9417, 220)):
        for harmonic, gain in ((1, 0.12), (2, 0.028), (3, 0.009)):
            tone(samples, start, 3.8, frequency * harmonic, gain, decay=2.5)
    return samples


def encode(samples, loop):
    # Fade loop seams and one-shot tails, leaving substantial mixing headroom.
    fade = min(round((0.08 if loop else 0.005) * RATE), len(samples) // 2)
    for i in range(fade):
        samples[i] *= i / fade
        samples[-1 - i] *= i / fade
    peak = max(abs(value) for value in samples)
    gain = min(1, 0.55 / max(peak, 0.000001))
    pcm = [round(value * gain * 32767) for value in samples]
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(struct.pack("<" + "h" * len(pcm), *pcm))
    return buffer.getvalue(), max(abs(value) for value in pcm) / 32768, math.sqrt(sum(value * value for value in pcm) / len(pcm)) / 32768


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Compare generated bytes without rewriting assets.")
    args = parser.parse_args()
    cues = ("footstep_dirt", "footstep_stone", "footstep_wood", "swing", "metal_impact",
            "shield_block", "parry", "guard_break", "hurt", "death", "pickup", "chest",
            "door", "ui_accept", "ui_back", "bandage", "bell_low", "bell_chime",
            "bell_solved", "quest_complete", "distant_bell")
    assets = [(name, cue(name), "UI" if name.startswith("ui_") else "Effects", False) for name in cues]
    assets += [("ambience_" + zone, ambience(zone), "Ambience", True)
               for zone in ("village", "forest", "monastery", "crypt", "undercroft", "inn")]
    assets.append(("music_valley", music(), "Music", True))
    manifest = {}
    for name, samples, bus, loop in assets:
        data, peak, rms = encode(samples, loop)
        path = OUTPUT / (name + ".wav")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit("Audio differs: " + str(path))
        else:
            OUTPUT.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        manifest[name] = {"path": "res://assets/audio/" + path.name, "bus": bus, "loop": loop,
                          "seconds": len(samples) / RATE, "sample_rate": RATE,
                          "peak": round(peak, 6), "rms": round(rms, 6), "sha256": hashlib.sha256(data).hexdigest()}
    text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    path = OUTPUT / "manifest.json"
    if args.check:
        if not path.exists() or path.read_text() != text:
            raise SystemExit("Audio manifest differs")
    else:
        path.write_text(text)
    print(f"{'Verified' if args.check else 'Generated'} {len(manifest)} original mono PCM assets at {RATE} Hz.")


if __name__ == "__main__":
    main()
