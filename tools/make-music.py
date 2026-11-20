#!/usr/bin/env python3
"""Render the ten Vectorfall tracks into art/music with NumPy and FFmpeg."""

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
import subprocess

import numpy as np


RATE = 22050
BARS = 40
TAU = 2 * np.pi
MINOR = (0, 2, 3, 5, 7, 8, 10)
DORIAN = (0, 2, 3, 5, 7, 9, 10)
MAJOR = (0, 2, 4, 5, 7, 9, 11)
MIXOLYDIAN = (0, 2, 4, 5, 7, 9, 10)


@dataclass(frozen=True)
class Song:
    file: str
    title: str
    bpm: int
    key: int
    mode: tuple
    chords: tuple
    hook: tuple
    groove: str


SONGS = [
    Song("first-light", "First Light", 96, 50, DORIAN, (0, 5, 3, 4), (0, 2, 4, 6, 5, 2, 3, 1), "float"),
    Song("saltwake", "Saltwake", 126, 45, MIXOLYDIAN, (0, 6, 3, 0), (4, 5, 7, 5, 2, 3, 0, 2), "motor"),
    Song("night-shift", "Night Shift", 117, 41, MINOR, (0, 1, 5, 4), (0, 0, 1, 4, 6, 4, 3, 1), "break"),
    Song("copper-ascent", "Copper Ascent", 110, 48, MAJOR, (0, 2, 5, 3), (2, 4, 5, 9, 8, 6, 4, 7), "motor"),
    Song("low-orbit", "Low Orbit", 85, 46, DORIAN, (0, 3, 6, 1), (4, 1, 0, 3, 7, 6, 4, 1), "float"),
    Song("wrong-side-of-the-rim", "Wrong Side of the Rim", 135, 42, MINOR, (0, 5, 3, 6), (0, 3, 4, 8, 7, 3, 6, 2), "break"),
    Song("coast-signal", "Coast Signal", 106, 47, MAJOR, (0, 4, 1, 3), (7, 4, 2, 5, 4, 3, 6, 2), "float"),
    Song("dead-frequency", "Dead Frequency", 120, 44, DORIAN, (0, 2, 3, 6), (1, 3, 0, 5, 4, 5, 2, 6), "break"),
    Song("horizon-run", "Horizon Run", 131, 43, MIXOLYDIAN, (0, 3, 2, 6), (0, 2, 7, 9, 5, 6, 3, 4), "motor"),
    Song("home-signal", "Home Signal", 92, 48, MAJOR, (0, 5, 3, 4), (7, 4, 5, 2, 1, 3, 2, 0), "float"),
]


def frequency(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


@lru_cache(maxsize=384)
def tone(voice, midi, samples):
    """Band-limited oscillator pairs with a little drift and a moving filter."""
    t = np.arange(samples, dtype=np.float32) / RATE
    hz = frequency(midi)
    phase = TAU * hz * t
    drift = 0.10 * np.sin(TAU * 3.1 * t) + 0.035 * np.sin(TAU * 0.43 * t)
    if voice == "bass":
        signal = .58 * np.sin(phase) + .24 * np.sin(phase * 2) + .18 * np.sin(phase * 3) * np.exp(-10 * t)
        attack, release = .009, .05
    elif voice == "pad":
        signal = (.5 * np.sin(phase + drift) + .5 * np.sin(phase * 1.004 - drift)
                  + .19 * np.sin(phase * 2.014) + .08 * np.sin(phase * 3 + drift))
        attack, release = .29, .42
    elif voice == "lead":
        signal = (.70 * np.sin(phase + drift) + .17 * np.sin(phase * 2 - drift)
                  + .16 * np.sin(phase * 3.009) * np.exp(-3.3 * t))
        attack, release = .048, .13
    else:
        signal = (np.sin(phase) + .28 * np.sin(phase * 2 + drift) + .15 * np.sin(phase * 4.01)) * np.exp(-5.5 * t)
        attack, release = .007, .07
    envelope = np.minimum(t / attack, 1) * np.minimum((samples - 1 - np.arange(samples)) / (RATE * release), 1)
    return (signal * envelope).astype(np.float32)


def percussion(seed):
    rng = np.random.default_rng(seed)
    t = np.arange(int(.38 * RATE), dtype=np.float32) / RATE
    white = rng.normal(0, .32, size=t.size)
    edge = white - np.roll(white, 1)
    kick_phase = TAU * (46 * t + 62 * (1 - np.exp(-23 * t)) / 23)
    kick = (.84 * np.sin(kick_phase) * np.exp(-17 * t) + edge * np.exp(-240 * t))
    snare = (.45 * np.sin(TAU * 166 * t) * np.exp(-40 * t) + .59 * edge * np.exp(-22 * t))
    hat = .62 * edge * np.exp(-66 * t)
    attack = np.minimum(t / .003, 1)
    return [kick * attack, snare * attack, hat * attack]


def render(song, seed):
    beat = 60 / song.bpm
    mix = np.zeros((round((BARS * 4 * beat + 1.4) * RATE), 2), dtype=np.float32)
    kick, snare, hat = percussion(seed)

    def lay(samples, start, gain, pan):
        frame = round(start * beat * RATE)
        samples = samples[:mix.shape[0] - frame]
        mix[frame:frame + samples.size, 0] += samples * (gain * (1 - pan) ** .5)
        mix[frame:frame + samples.size, 1] += samples * (gain * (1 + pan) ** .5)

    def note(voice, midi, start, length, gain, pan=0.0):
        lay(tone(voice, midi, round(length * beat * RATE)), start, gain, pan)

    def degree(step):
        octaves, key = divmod(step, 7)
        return song.key + song.mode[key] + 12 * octaves

    for bar in range(BARS):
        start = bar * 4
        section = bar // 4
        chord = song.chords[(bar if section not in (4, 5) else bar + 2) % 4]
        if bar == BARS - 1:
            chord = 0
        opening = section == 0
        bridge = section in (4, 5)
        closing = section == 9
        chorus = section in (2, 3, 7, 8)
        layers = (0, 2, 4, 6) if chorus or song.groove == "float" else (0, 2, 4)
        for k, interval in enumerate(layers):
            pitch = degree(chord + interval) + (0 if interval == 0 else 12)
            note("pad", pitch, start + k * .055, 4.5, .047 if chorus else .038, -.64 + k * .42)
        if opening or bar == BARS - 1:
            continue
        if song.groove == "motor":
            kicks = (0, 1.5, 2, 3.5) if chorus else (0, 2)
            bass_times = (0, .75, 1.5, 2, 2.75, 3.5)
        elif song.groove == "break":
            kicks = (0, .75, 2.5, 3.5) if bar % 2 else (0, 1.25, 2.75)
            bass_times = (0, 1.25, 2, 2.5, 3.5)
        else:
            kicks = (0, 2) if chorus else (0,)
            bass_times = (0, 2, 3.25)
        for k, offset in enumerate(bass_times):
            bass_note = degree(chord + (4 if k == len(bass_times) - 1 and bar % 2 else 0)) - 12
            note("bass", bass_note, start + offset, .44 if song.groove != "float" else .83, .14 if bridge else .19)
        if not bridge and not closing:
            for offset in kicks:
                lay(kick, start + offset, .17 if song.groove == "float" else .23, 0)
            for offset in (1, 3) if song.groove != "float" or chorus else (3,):
                lay(snare, start + offset, .15, .1)
            for k in range(8):
                if k % 2 or chorus:
                    lay(hat, start + k * .5 + (.035 if k % 2 else 0), .08 if k % 2 else .045, .3 if k % 2 else -.3)
        if chorus:
            for k in range(8):
                pitch = degree(song.hook[(k + bar * 2) % 8]) + 12
                note("pluck", pitch, start + k * .5, .48, .068, -.5 if k % 2 else .46)
        if (chorus and bar % 2 == 0) or bridge or (closing and bar % 2 == 1):
            hook_offset = 4 if bridge else 0
            for k, offset in enumerate((0, .85, 1.75, 2.7)):
                pitch = degree(song.hook[(k + hook_offset + (bar % 4) * 2) % 8]) + 12
                note("lead", pitch, start + offset, .72 if bridge else .64, .097, -.13)
    # A tape echo under the notes, a short output fade and soft limiting.
    delay = round(beat * .75 * RATE)
    mix[delay:, 0] += mix[:-delay, 1].copy() * .13
    mix[delay:, 1] += mix[:-delay, 0].copy() * .11
    fade = round(.78 * RATE)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    limited = np.tanh(mix * 1.8)
    limited *= .81 / max(float(np.max(np.abs(limited))), .01)
    return (limited * 32767).astype("<i2")


def main():
    folder = Path(__file__).resolve().parents[1] / "art" / "music"
    folder.mkdir(parents=True, exist_ok=True)
    for i, song in enumerate(SONGS):
        pcm = render(song, 740 + i)
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(RATE),
             "-ac", "2", "-i", "pipe:0", "-threads", "1", "-c:a", "libvorbis",
             "-q:a", "3", "-metadata", f"title={song.title}", str(folder / f"{song.file}.ogg")],
            input=pcm.tobytes(), check=True,
        )
        print(f"{song.title} {pcm.shape[0] / RATE:.1f} s", flush=True)
        tone.cache_clear()


if __name__ == "__main__":
    main()
