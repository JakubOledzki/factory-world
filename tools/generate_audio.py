#!/usr/bin/env python3
"""Synthesizes the game's sounds and music into client/audio/ as Ogg Vorbis.

Run: python3 tools/generate_audio.py [name ...]   (needs numpy and ffmpeg)

Nothing is recorded or downloaded: every sound is built here from sine waves, noise and plucked
strings (Karplus-Strong), so the files can be made again and changed like the rest of the art.
Effects are short and soft; the music is three calm loops in the spirit of a quiet workshop.
The same seed gives the same files.
"""
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parent.parent / "client" / "audio"
RATE = 32000
rng = np.random.default_rng(7)


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * RATE)) / RATE


def env(n: int, attack: float, decay: float) -> np.ndarray:
    """A sharp rise and an exponential fall, `decay` seconds to fade to about 1/20."""
    t = np.arange(n) / RATE
    rise = np.clip(t / max(attack, 1e-4), 0, 1)
    return rise * np.exp(-3.0 * np.maximum(t - attack, 0) / max(decay, 1e-4))


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    return x - lowpass(x, cutoff)


def noise(n: int) -> np.ndarray:
    return rng.uniform(-1, 1, n)


def tone(freq, seconds, kind="sine", phase=0.0):
    t = t_axis(seconds)
    f = np.full_like(t, freq) if np.isscalar(freq) else freq
    ph = 2 * np.pi * np.cumsum(f) / RATE + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "square":
        return np.sign(np.sin(ph)) * 0.6
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    raise ValueError(kind)


def pluck(freq: float, seconds: float, brightness: float = 0.5) -> np.ndarray:
    """Karplus-Strong string: a burst of noise in a delay line that loses its highs."""
    n = int(seconds * RATE)
    period = max(2, int(RATE / freq))
    buf = lowpass(noise(period), 2000 + 6000 * brightness)
    out = np.empty(n)
    decay = 0.996
    for i in range(n):
        v = buf[i % period]
        out[i] = v
        buf[i % period] = decay * 0.5 * (v + buf[(i + 1) % period])
    return out * env(n, 0.002, seconds)


def mix(length: float, *parts):
    out = np.zeros(int(length * RATE))
    for start, sound, gain in parts:
        i = int(start * RATE)
        end = min(len(out), i + len(sound))
        out[i:end] += sound[: end - i] * gain
    return out


def norm(x: np.ndarray, peak: float = 0.8) -> np.ndarray:
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * peak


def fade(x: np.ndarray, seconds: float = 0.01) -> np.ndarray:
    n = min(len(x) // 2, int(seconds * RATE))
    if n > 0:
        x = x.copy()
        x[:n] *= np.linspace(0, 1, n)
        x[-n:] *= np.linspace(1, 0, n)
    return x


def note(name: str) -> float:
    """'A4' → 440 Hz."""
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


# --- Effects -------------------------------------------------------------------------------

def sfx_click():
    n = int(0.05 * RATE)
    s = tone(1800, 0.05, "sine") * env(n, 0.001, 0.02) + highpass(noise(n), 3000) * env(n, 0.0005, 0.008) * 0.4
    return norm(s, 0.5)


def sfx_open():
    t = t_axis(0.16)
    s = tone(np.linspace(500, 900, len(t)), 0.16, "tri") * env(len(t), 0.005, 0.1)
    return norm(s, 0.45)


def sfx_close():
    t = t_axis(0.14)
    s = tone(np.linspace(800, 450, len(t)), 0.14, "tri") * env(len(t), 0.005, 0.09)
    return norm(s, 0.4)


def sfx_place():
    n = int(0.3 * RATE)
    thud = tone(np.linspace(140, 60, n), 0.3, "sine") * env(n, 0.002, 0.15)
    knock = lowpass(noise(n), 900) * env(n, 0.001, 0.05)
    return norm(thud + knock * 0.8, 0.8)


def sfx_pickup():
    n = int(0.18 * RATE)
    s = tone(np.geomspace(400, 1200, n), 0.18, "sine") * env(n, 0.003, 0.1)
    return norm(s, 0.55)


def sfx_chop():
    n = int(0.35 * RATE)
    hit = lowpass(noise(n), 1500) * env(n, 0.001, 0.07)
    body = tone(np.linspace(220, 150, n), 0.35, "tri") * env(n, 0.002, 0.18)
    return norm(hit * 1.2 + body * 0.7, 0.85)


def sfx_mine():
    n = int(0.45 * RATE)
    ring = sum(tone(f, 0.45, "sine") * a for f, a in [(1420, 1.0), (2310, 0.6), (3570, 0.35)]) * env(n, 0.001, 0.25)
    crack = highpass(noise(n), 1500) * env(n, 0.0005, 0.04)
    return norm(ring * 0.6 + crack, 0.8)


def sfx_harvest():
    n = int(0.4 * RATE)
    rustle = highpass(lowpass(noise(n), 5000), 1200) * env(n, 0.03, 0.25)
    return norm(rustle, 0.55)


def sfx_coin():
    a = tone(note("B5"), 0.09, "square") * env(int(0.09 * RATE), 0.001, 0.08)
    b = tone(note("E6"), 0.35, "square") * env(int(0.35 * RATE), 0.001, 0.3)
    return norm(lowpass(mix(0.45, (0, a, 0.8), (0.08, b, 0.8)), 6000), 0.45)


def sfx_craft():
    hits = []
    for i, f in enumerate([820, 900]):
        n = int(0.22 * RATE)
        hits.append((i * 0.13, (tone(f, 0.22, "sine") + tone(f * 2.76, 0.22, "sine") * 0.4) * env(n, 0.001, 0.12), 0.7))
    return norm(mix(0.4, *hits), 0.6)


def sfx_error():
    n = int(0.28 * RATE)
    s = (tone(160, 0.28, "square") + tone(166, 0.28, "square")) * env(n, 0.005, 0.2)
    return norm(lowpass(s, 1400), 0.45)


def sfx_notify():
    a = tone(note("A5"), 0.5, "sine") * env(int(0.5 * RATE), 0.002, 0.4)
    b = tone(note("E6"), 0.5, "sine") * env(int(0.5 * RATE), 0.002, 0.4)
    return norm(mix(0.65, (0, a, 0.6), (0.11, b, 0.5)), 0.45)


def sfx_levelup():
    notes = ["C5", "E5", "G5", "C6"]
    parts = []
    for i, name in enumerate(notes):
        length = 0.6 if i == len(notes) - 1 else 0.2
        n = int(length * RATE)
        s = (tone(note(name), length, "square") * 0.5 + tone(note(name) * 2, length, "sine") * 0.3) * env(n, 0.003, length)
        parts.append((i * 0.11, lowpass(s, 5000), 0.7))
    return norm(mix(1.1, *parts), 0.6)


def sfx_research():
    parts = []
    for i, name in enumerate(["G5", "B5", "D6", "G6", "B6"]):
        parts.append((i * 0.07, pluck(note(name), 0.9, 0.8), 0.6))
    return norm(mix(1.3, *parts), 0.55)


def sfx_achievement():
    parts = []
    for i, name in enumerate(["E6", "G#6", "B6", "E7"]):
        n = int(0.5 * RATE)
        parts.append((i * 0.06, tone(note(name), 0.5, "sine") * env(n, 0.002, 0.45), 0.5))
    parts.append((0.3, sfx_levelup()[: int(0.6 * RATE)], 0.4))
    return norm(mix(1.2, *parts), 0.6)


def sfx_train():
    n = int(1.1 * RATE)
    whistle = (tone(note("A5"), 1.1, "sine") + tone(note("C#6"), 1.1, "sine") * 0.8 + tone(note("E6"), 1.1, "sine") * 0.6)
    breath = lowpass(noise(n), 3000) * 0.15
    shape = np.minimum(1, t_axis(1.1) / 0.08) * np.minimum(1, (1.1 - t_axis(1.1)) / 0.3)
    return norm((whistle + breath) * shape, 0.5)


def sfx_drop():
    """A seasonal treat or an album find: a bright little sparkle."""
    parts = []
    for i, name in enumerate(["C7", "G6", "E7"]):
        n = int(0.3 * RATE)
        parts.append((i * 0.05, tone(note(name), 0.3, "sine") * env(n, 0.001, 0.25), 0.5))
    return norm(mix(0.5, *parts), 0.45)


def sfx_shutter():
    n = int(0.2 * RATE)
    a = highpass(noise(n), 2500) * env(n, 0.0005, 0.03)
    b = np.roll(a, int(0.07 * RATE)) * 0.7
    return norm(a + b, 0.6)


def loop_machines():
    """A quiet hum and clatter of working machines, two seconds that repeat seamlessly."""
    seconds = 4.0
    n = int(seconds * RATE)
    hum = tone(55, seconds, "saw") * 0.15 + tone(110, seconds, "sine") * 0.25
    hum = lowpass(hum, 300)
    clatter = np.zeros(n)
    for i in range(16):
        start = int(i * n / 16)
        k = int(0.06 * RATE)
        click = lowpass(noise(k), 2500) * env(k, 0.001, 0.03) * (0.6 if i % 4 == 0 else 0.3)
        clatter[start:start + k] += click[: n - start]
    return norm(hum + clatter * 0.5, 0.5)


# --- Music ---------------------------------------------------------------------------------

def pad(freqs, seconds):
    n = int(seconds * RATE)
    s = np.zeros(n)
    for f in freqs:
        for detune in (-0.12, 0.0, 0.11):
            s += tone(f * 2 ** (detune / 12), seconds, "saw", phase=rng.uniform(0, 6.28))
    s = lowpass(s / (len(freqs) * 3), 900)
    shape = np.minimum(1, t_axis(seconds) / 0.6) * np.minimum(1, (seconds - t_axis(seconds)) / 0.8)
    return s * shape


def song(chords, bpm, bars_per_chord, arp_pattern, melody_seed, seconds_hint):
    beat = 60 / bpm
    bar = 4 * beat
    total_bars = len(chords) * bars_per_chord
    length = total_bars * bar
    out = np.zeros(int(length * RATE) + RATE)
    melody_rng = np.random.default_rng(melody_seed)
    for ci, chord in enumerate(chords):
        start = ci * bars_per_chord * bar
        freqs = [note(n) for n in chord]
        p = pad([f / 2 for f in freqs], bars_per_chord * bar + 0.5)
        i = int(start * RATE)
        out[i:i + len(p)] += p * 0.35
        # Bass on the root, every half bar.
        for b in range(bars_per_chord * 2):
            t = start + b * bar / 2
            bass = pluck(freqs[0] / 4, bar / 2 + 0.2, 0.2)
            j = int(t * RATE)
            out[j:j + len(bass)] += bass[: len(out) - j] * 0.5
        # Arpeggio in eighths.
        for b in range(bars_per_chord * 8):
            step = arp_pattern[b % len(arp_pattern)]
            if step is None:
                continue
            f = freqs[step % len(freqs)] * (2 if step >= len(freqs) else 1)
            t = start + b * beat / 2
            s = pluck(f, 0.8, 0.55)
            j = int(t * RATE)
            out[j:j + len(s)] += s[: len(out) - j] * 0.22
        # A sparse melody on the chord's notes, an octave up.
        for b in range(bars_per_chord * 4):
            if melody_rng.random() < 0.45:
                f = freqs[melody_rng.integers(len(freqs))] * 2
                t = start + b * beat
                n = int(1.2 * RATE)
                s = (tone(f, 1.2, "tri") * 0.6 + tone(f * 2, 1.2, "sine") * 0.15) * env(n, 0.01, 0.9)
                j = int(t * RATE)
                out[j:j + len(s)] += s[: len(out) - j] * 0.12
    # The tail wraps to the start, so the loop has no seam.
    loop_n = int(length * RATE)
    tail = out[loop_n:]
    out = out[:loop_n]
    out[: len(tail)] += tail
    return norm(out, 0.6)


def music_garage():
    return song([["A3", "C4", "E4"], ["F3", "A3", "C4"], ["C3", "E3", "G3"], ["G3", "B3", "D4"]] * 4,
                bpm=84, bars_per_chord=2, arp_pattern=[0, 1, 2, 3, 2, 1, 0, None], melody_seed=1, seconds_hint=90)


def music_plot():
    return song([["D3", "F#3", "A3"], ["B2", "D3", "F#3"], ["G2", "B2", "D3"], ["A2", "C#3", "E3"]] * 4,
                bpm=96, bars_per_chord=2, arp_pattern=[0, 2, 1, 3, 0, 2, 1, 3], melody_seed=2, seconds_hint=100)


def music_world():
    return song([["E3", "G3", "B3"], ["C3", "E3", "G3"], ["D3", "F#3", "A3"], ["B2", "D3", "F#3"]] * 3,
                bpm=72, bars_per_chord=2, arp_pattern=[0, None, 1, None, 2, None, 3, None], melody_seed=3, seconds_hint=80)


SOUNDS = {
    "click": sfx_click, "open": sfx_open, "close": sfx_close, "place": sfx_place, "pickup": sfx_pickup,
    "chop": sfx_chop, "mine": sfx_mine, "harvest": sfx_harvest, "coin": sfx_coin, "craft": sfx_craft,
    "error": sfx_error, "notify": sfx_notify, "levelup": sfx_levelup, "research": sfx_research,
    "achievement": sfx_achievement, "train": sfx_train, "drop": sfx_drop, "shutter": sfx_shutter,
    "loop_machines": loop_machines,
    "music_garage": music_garage, "music_plot": music_plot, "music_world": music_world,
}


def write(name: str, samples: np.ndarray) -> None:
    looped = name.startswith(("music_", "loop_"))
    if not looped:
        samples = fade(samples, 0.004)
    pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "s.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        quality = "2" if looped else "4"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", quality,
                        str(OUT / f"{name}.ogg")], check=True)
    print(f"{name}.ogg  {len(samples) / RATE:.1f} s")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    names = sys.argv[1:] or list(SOUNDS)
    for name in names:
        write(name, SOUNDS[name]())


if __name__ == "__main__":
    main()
