#!/usr/bin/env python3
"""Procedural 20 s ambient score for the FRAME demo.

Pure stdlib (no numpy). Writes assets/director/score.wav (stereo, 16-bit, 32 kHz ~2.5 MB).
    python3 director/tools/gen_score.py [out.wav]

Cue sheet (matches director/director.gd timeline):
  0.0  low hit + shimmer under the title card, warm Dmaj9 pad, sea wash (coast)
  5.8  reverse swell into the cut ............ 7.0 soft sub impact
  7.0  intimate Gmaj7 pad, felt-piano notes, small room tone (macro)
  12.3 reverse swell into the cut ............ 13.5 sub impact
  13.5 organ pedal + choir-like pad, long reverb, stone room tone (cathedral)
  18.5 resolve under the end card, fade to silence by 19.9
"""
import math
import random
import struct
import sys
import wave

SR = 32000
DUR = 20.0
N = int(SR * DUR)
random.seed(1337)

L = [0.0] * N
R = [0.0] * N
SL = [0.0] * N  # reverb send
SR_ = [0.0] * N

TAB_N = 4096
MASK = TAB_N - 1


def make_table(harmonics):
    tab = [0.0] * TAB_N
    for n, a in harmonics:
        for i in range(TAB_N):
            tab[i] += a * math.sin(2 * math.pi * n * i / TAB_N)
    peak = max(abs(x) for x in tab)
    return [x / peak for x in tab]


SINE = make_table([(1, 1.0)])
WARM = make_table([(n, 1.0 / (n * n)) for n in range(1, 9)])
# "vowel"-ish: emphasise 2nd-5th harmonics like an 'ah' formant on a low voice
CHOIR = make_table([(1, 0.6), (2, 0.8), (3, 0.7), (4, 0.45), (5, 0.3), (6, 0.12), (7, 0.08), (9, 0.04)])
ORGAN = make_table([(1, 1.0), (2, 0.5), (3, 0.18), (4, 0.25), (6, 0.08), (8, 0.1)])


def smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def env_ar(t, t0, t1, att, rel):
    if t < t0 or t > t1:
        return 0.0
    a = smooth((t - t0) / att) if att > 0 else 1.0
    r = smooth((t1 - t) / rel) if rel > 0 else 1.0
    return a * r


def osc(table, freq, t0, t1, amp, att, rel, pan=0.0, send=0.3, detune_cents=0.0,
        vib_rate=0.0, vib_cents=0.0, trem=0.0, trem_rate=0.2, phase0=None, decay=0.0):
    """Wavetable oscillator with AR envelope, optional exponential decay, equal-power pan."""
    i0 = max(0, int(t0 * SR))
    i1 = min(N, int(t1 * SR))
    f = freq * 2 ** (detune_cents / 1200.0)
    phase = random.random() * TAB_N if phase0 is None else phase0
    gl = math.cos((pan + 1) * math.pi / 4) * amp
    gr = math.sin((pan + 1) * math.pi / 4) * amp
    inc0 = f * TAB_N / SR
    vr = 2 * math.pi * vib_rate / SR
    tr = 2 * math.pi * trem_rate / SR
    tph = random.random() * 6.28
    for i in range(i0, i1):
        t = i / SR
        e = env_ar(t, t0, t1, att, rel)
        if decay > 0:
            e *= math.exp(-(t - t0) / decay)
        if trem:
            e *= 1.0 - trem * (0.5 + 0.5 * math.sin(tph + tr * i))
        inc = inc0
        if vib_cents:
            inc *= 2 ** (vib_cents * math.sin(vr * i) / 1200.0)
        phase += inc
        v = table[int(phase) & MASK] * e
        L[i] += v * gl
        R[i] += v * gr
        SL[i] += v * gl * send
        SR_[i] += v * gr * send


def pad(table, notes, t0, t1, amp, att, rel, send, spread=0.6, voices=3, cents=7.0):
    n = len(notes)
    for k, fr in enumerate(notes):
        base_pan = (k / max(1, n - 1) * 2 - 1) * spread
        for v in range(voices):
            dc = (v - (voices - 1) / 2) * cents
            osc(table, fr, t0, t1, amp / voices, att, rel, pan=max(-1, min(1, base_pan + (v - 1) * 0.2)),
                send=send, detune_cents=dc + random.uniform(-1.5, 1.5),
                vib_rate=random.uniform(0.08, 0.2), vib_cents=3.0, trem=0.25,
                trem_rate=random.uniform(0.07, 0.18))


def noise_layer(t0, t1, amp_fn, cutoff_fn, send):
    """Stereo-decorrelated noise through a 2-pole lowpass with time-varying cutoff."""
    i0 = max(0, int(t0 * SR))
    i1 = min(N, int(t1 * SR))
    a0 = b0 = a1 = b1 = 0.0
    rnd = random.random
    for i in range(i0, i1):
        t = i / SR
        a = amp_fn(t)
        if a <= 0.0:
            continue
        g = 1.0 - math.exp(-2 * math.pi * cutoff_fn(t) / SR)
        a0 += g * (rnd() * 2 - 1 - a0)
        a1 += g * (a0 - a1)
        b0 += g * (rnd() * 2 - 1 - b0)
        b1 += g * (b0 - b1)
        yl = a1 * a * 2.0
        yr = b1 * a * 2.0
        L[i] += yl
        R[i] += yr
        SL[i] += yl * send
        SR_[i] += yr * send


def boom(t0, amp, f0=58.0, f1=34.0, dec=1.4, send=0.35):
    i0 = int(t0 * SR)
    i1 = min(N, int((t0 + dec * 4) * SR))
    ph = 0.0
    for i in range(i0, i1):
        t = (i - i0) / SR
        f = f1 + (f0 - f1) * math.exp(-t / 0.25)
        ph += 2 * math.pi * f / SR
        e = (1 - math.exp(-t / 0.012)) * math.exp(-t / dec)
        v = math.sin(ph) * e * amp
        L[i] += v
        R[i] += v
        SL[i] += v * send
        SR_[i] += v * send


def swell(t_hit, length, amp, send=0.5):
    """Reverse-cymbal style rising filtered noise ending at t_hit, short tail after."""
    def a(t):
        if t < t_hit:
            x = (t - (t_hit - length)) / length
            return amp * (max(0.0, x) ** 3)
        return amp * math.exp(-(t - t_hit) / 0.18)

    def fc(t):
        x = min(1.0, max(0.0, (t - (t_hit - length)) / length))
        return 500 + 7000 * x * x

    noise_layer(t_hit - length, t_hit + 1.0, a, fc, send)


def felt(freq, t0, amp, pan, send=0.55):
    # soft "felt piano": a few inharmonic-ish partials with fast attack and per-partial decay
    for mult, a, d in ((1.0, 1.0, 2.4), (2.002, 0.35, 1.2), (3.007, 0.12, 0.7), (4.02, 0.05, 0.4)):
        osc(SINE, freq * mult, t0, min(DUR, t0 + 6), amp * a, 0.012, 0.6, pan=pan, send=send, decay=d)


def shimmer(t0, t1, notes, amp, send=0.8):
    for k, fr in enumerate(notes):
        osc(SINE, fr, t0 + k * 0.09, t1, amp, 1.2, 2.0, pan=(-0.6 + 1.2 * k / max(1, len(notes) - 1)),
            send=send, vib_rate=4.5, vib_cents=4, trem=0.5, trem_rate=0.9 + k * 0.23)


# ---------------------------------------------------------------- notes
D1, A1 = 36.71, 55.0
D2, G2, A2 = 73.42, 98.0, 110.0
D3, E3, Fs3, G3, A3, B3 = 146.83, 164.81, 185.0, 196.0, 220.0, 246.94
D4, E4, Fs4, A4, B4 = 293.66, 329.63, 369.99, 440.0, 493.88
D5, Fs5, A5, E5 = 587.33, 739.99, 880.0, 659.26

print("coast...", file=sys.stderr)
# Title hit + shimmer
boom(0.45, 0.10, dec=1.8)
shimmer(0.5, 4.5, [A4, E5, Fs5], 0.018)
# Warm Dmaj9 pad
pad(WARM, [D2, A2, E3, Fs3, A3], 0.0, 7.6, 0.075, 2.8, 0.9, send=0.35)


# Sea wash: three slow breaker swells + constant distant surf bed
def sea_amp(t):
    bed = 0.035 * smooth(t / 1.5) * smooth((7.9 - t) / 0.9)
    w = 0.0
    for c in (1.6, 4.6, 7.4):
        x = (t - c) / 1.5
        w += math.exp(-x * x) * (0.9 if x < 0 else 1.0)
    return bed + 0.07 * w * smooth((7.9 - t) / 0.9) * smooth(t / 0.8)


def sea_fc(t):
    w = 0.0
    for c in (1.6, 4.6, 7.4):
        x = (t - c) / 1.2
        w += math.exp(-x * x)
    return 350 + 1700 * w


noise_layer(0.0, 7.9, sea_amp, sea_fc, send=0.25)
swell(7.0, 1.3, 0.08)
boom(7.0, 0.075, f0=52, f1=32, dec=1.2)

print("macro...", file=sys.stderr)
# Intimate Gmaj7 / Bm pad, higher and softer
pad(WARM, [G2, D3, Fs3, B3], 6.8, 14.0, 0.055, 1.4, 1.0, send=0.45, spread=0.5)
for t0, f, p in ((7.35, B4, -0.3), (8.6, Fs4, 0.25), (9.7, D5, -0.1), (10.9, A4, 0.35),
                 (11.75, Fs5, -0.25), (12.4, E5, 0.1)):
    felt(f, t0, 0.05, p)
# small-room tone
noise_layer(6.9, 14.0, lambda t: 0.012 * env_ar(t, 6.9, 14.0, 0.8, 0.8), lambda t: 260.0, send=0.1)
swell(13.5, 1.4, 0.085, send=0.6)
boom(13.5, 0.095, f0=50, f1=30, dec=1.9, send=0.5)

print("cathedral...", file=sys.stderr)
# Organ pedal
osc(ORGAN, D1, 13.4, 19.9, 0.07, 1.5, 1.6, send=0.6)
osc(ORGAN, A1, 13.6, 19.9, 0.035, 2.0, 1.6, send=0.6)
# Choir-like pad (slow attack, wide, heavy reverb)
pad(CHOIR, [D3, A3, D4, Fs4, A4], 13.4, 19.9, 0.06, 2.2, 1.4, send=0.95, spread=0.8, voices=3, cents=9)
# Resolution under end card: add E5/Fs5 shimmer
shimmer(17.6, 19.9, [D5, Fs5, A5], 0.012, send=1.0)
# stone room tone
noise_layer(13.4, 20.0, lambda t: 0.016 * env_ar(t, 13.4, 19.9, 1.0, 1.4), lambda t: 420.0, send=0.5)

print("reverb...", file=sys.stderr)


def freeverb(inp, combs, allps, fb, damp):
    out = [0.0] * N
    for clen in combs:
        buf = [0.0] * clen
        idx = 0
        store = 0.0
        for i in range(N):
            y = buf[idx]
            store = y * (1 - damp) + store * damp
            buf[idx] = inp[i] + store * fb
            idx += 1
            if idx == clen:
                idx = 0
            out[i] += y
    for alen in allps:
        buf = [0.0] * alen
        idx = 0
        for i in range(N):
            b = buf[idx]
            x = out[i]
            buf[idx] = x + b * 0.5
            out[i] = b - x
            idx += 1
            if idx == alen:
                idx = 0
    return out


sc = SR / 44100.0
combs = [int(c * sc) for c in (1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116)]
allps = [int(a * sc) for a in (556, 441, 341, 225)]
spread = int(23 * sc)
rl = freeverb(SL, combs, allps, 0.90, 0.35)
rr = freeverb(SR_, [c + spread for c in combs], [a + spread for a in allps], 0.90, 0.35)

print("mix...", file=sys.stderr)
wet = 0.045
outL = [L[i] + rl[i] * wet for i in range(N)]
outR = [R[i] + rr[i] * wet for i in range(N)]
# master fade in/out, DC-safe soft clip, normalise to -1 dBFS peak
for i in range(N):
    t = i / SR
    g = smooth(t / 0.25) * smooth((DUR - 0.05 - t) / 0.6)
    outL[i] *= g
    outR[i] *= g
peak = max(max(abs(x) for x in outL), max(abs(x) for x in outR))
norm = 0.89 / peak
frames = bytearray()
for i in range(N):
    a = math.tanh(outL[i] * norm * 1.1) / math.tanh(1.1)
    b = math.tanh(outR[i] * norm * 1.1) / math.tanh(1.1)
    frames += struct.pack("<hh", int(a * 32767), int(b * 32767))

out = sys.argv[1] if len(sys.argv) > 1 else "assets/director/score.wav"
with wave.open(out, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(bytes(frames))
print("wrote", out, len(frames), "bytes, peak", peak, file=sys.stderr)
