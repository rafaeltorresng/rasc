#!/usr/bin/env python3
"""Produce synthetic 16k/mono PCM fixtures. Uses only bundled TTS voices and generated noise."""
import array
import json
import math
import random
import subprocess as sp
import sys
import tempfile
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
RATE = 16000
VOICES = {"en-US": "Samantha", "pt-BR": "Luciana"}

def synthesize(part, locale, temp):
    if isinstance(part, dict):
        locale, part = part["locale"], part["text"]
    aiff = temp / "utterance.aiff"
    sp.run(["say", "-v", VOICES[locale], "-r", "173", "-o", aiff, part], check=True)
    raw = sp.check_output(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", aiff,
                           "-ar", str(RATE), "-ac", "1", "-f", "s16le", "-"])
    samples = array.array("h", raw)
    audible = [i for i, value in enumerate(samples) if abs(value) > 85]
    if not audible:
        raise ValueError(f"Voice produced no speech: {locale}")
    # Standard fixtures add common guard samples outside this content range.
    return samples[audible[0]:audible[-1] + 1]

def add_noise(samples, decibels, has_speech):
    rng = random.Random(4567)
    low = 0.0
    noise = []
    for _ in samples:
        white = rng.gauss(0, 1)
        low = 0.96 * low + 0.04 * white
        noise.append(0.30 * white + 2.0 * low)
    rms = math.sqrt(sum(x*x for x in noise) / len(noise))
    target = (math.sqrt(sum(x*x for x in samples) / len(samples)) if has_speech else 32767)
    scale = target * 10**(decibels/20) / rms
    return array.array("h", (min(32767, max(-32768, int(value + perturbation * scale)))
                             for value, perturbation in zip(samples, noise)))

def build(output):
    output.mkdir(parents=True, exist_ok=True)
    rows = json.loads((HERE / "corpus.json").read_text())
    sources = {}
    with tempfile.TemporaryDirectory() as name:
        for fixture in rows:
            if "copy" in fixture:
                source, reference, critical = sources[fixture["copy"]]
                content = array.array("h", source)
            else:
                reference = fixture.get("text", "")
                critical = fixture.get("critical", [])
                if "silence" in fixture:
                    content = array.array("h", [0]) * round(fixture["silence"] * RATE)
                    if fixture.get("click"):
                        content[400:416] = array.array("h", [8000, -6200, 4000, -2500] * 4)
                else:
                    content = array.array("h")
                    segments = fixture.get("segments", [reference])
                    reference = " ".join(s["text"] if isinstance(s, dict) else s for s in segments)
                    for number, segment in enumerate(segments):
                        if number:
                            content.extend([0] * round(fixture["pause_ms"] * RATE / 1000))
                        content.extend(synthesize(segment, fixture["locale"], Path(name)))
            sources[fixture["id"]] = (content, reference, critical)
            if reference and not fixture.get("tight"):
                content = array.array("h", [0]) * 2400 + content + array.array("h", [0]) * 3200
            if "noise_db" in fixture:
                content = add_noise(content, fixture["noise_db"], bool(reference))
            filename = output / (fixture["id"] + ".wav")
            with wave.open(str(filename), "wb") as audio:
                audio.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
                audio.writeframes(content.tobytes())
            fixture.update(reference=reference, critical=critical, seconds=round(len(content)/RATE, 4))
    (output / "manifest.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")

if __name__ == "__main__":
    build(Path(sys.argv[1]))
