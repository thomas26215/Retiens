"""Synthétise les effets sonores de Retiens (WAV mono 44,1 kHz).

Usage : python3 synth.py <dossier_sortie>
Tout est généré ici (aucun échantillon externe) : marimba, cloches,
pops, souffles, avec une petite réverbération pour l'espace.
"""
import math
import random
import struct
import sys
import wave
from pathlib import Path

SR = 44100
random.seed(7)


def buf(seconds):
    return [0.0] * int(SR * seconds)


def add(dst, src, at=0.0, gain=1.0):
    off = int(at * SR)
    need = off + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, v in enumerate(src):
        dst[off + i] += v * gain
    return dst


def partials(freq, dur, parts, attack=0.003):
    """Somme de partiels (ratio, amplitude, constante de décroissance s)."""
    n = int(dur * SR)
    out = [0.0] * n
    # Relâchement sur le dernier quart : pas de coupure nette (clic).
    release = max(int(0.03 * SR), n // 4)
    for ratio, amp, tau in parts:
        f = freq * ratio
        if f > SR / 2.2:
            continue
        w = 2 * math.pi * f / SR
        ph = random.random() * 0.2
        for i in range(n):
            t = i / SR
            env = math.exp(-t / tau)
            if t < attack:
                env *= t / attack
            if n - i < release:
                env *= 0.5 - 0.5 * math.cos(math.pi * (n - i) / release)
            out[i] += amp * env * math.sin(w * i + ph)
    return out


def marimba(freq, dur=0.6, amp=1.0):
    return [v * amp for v in partials(freq, dur, [
        (1.0, 1.0, 0.32), (3.93, 0.32, 0.07), (9.2, 0.07, 0.025), (2.0, 0.08, 0.15),
    ], attack=0.002)]


def bell(freq, dur=1.4, amp=1.0):
    return [v * amp for v in partials(freq, dur, [
        (1.0, 1.0, 0.75), (2.756, 0.42, 0.36), (5.404, 0.22, 0.2),
        (8.933, 0.09, 0.11), (0.5, 0.08, 0.5),
    ], attack=0.0015)]


def soft(freq, dur=0.35, amp=1.0, tau=0.14, attack=0.008):
    return [v * amp for v in partials(freq, dur, [
        (1.0, 1.0, tau), (2.0, 0.18, tau * 0.6), (3.0, 0.05, tau * 0.4),
    ], attack=attack)]


def glide(f0, f1, dur, amp=1.0, tau=None, attack=0.004, curve=1.0):
    n = int(dur * SR)
    out = [0.0] * n
    ph = 0.0
    release = max(int(0.02 * SR), n // 5)
    for i in range(n):
        x = i / n
        f = f0 + (f1 - f0) * (x ** curve)
        ph += 2 * math.pi * f / SR
        t = i / SR
        env = math.exp(-t / tau) if tau else math.sin(math.pi * x) ** 0.6
        if t < attack:
            env *= t / attack
        if tau and n - i < release:
            env *= 0.5 - 0.5 * math.cos(math.pi * (n - i) / release)
        out[i] = amp * env * (math.sin(ph) + 0.12 * math.sin(2 * ph))
    return out


def noise(dur, amp=1.0, cutoff0=2000.0, cutoff1=600.0, shape='swell'):
    """Souffle : bruit blanc passe-bas à fréquence de coupure mobile."""
    n = int(dur * SR)
    out = [0.0] * n
    y = 0.0
    for i in range(n):
        x = i / n
        fc = cutoff0 + (cutoff1 - cutoff0) * x
        a = 1 - math.exp(-2 * math.pi * fc / SR)
        y += a * (random.uniform(-1, 1) - y)
        if shape == 'swell':
            env = math.sin(math.pi * x) ** 1.5
        else:
            env = math.exp(-x * 6)
        out[i] = amp * env * y
    return out


def reverb(x, mix=0.22):
    """Petite salle : quelques échos amortis, filtrés passe-bas."""
    taps = [(0.029, 0.55), (0.041, 0.45), (0.053, 0.38), (0.071, 0.3),
            (0.097, 0.22), (0.131, 0.16), (0.173, 0.1), (0.229, 0.06)]
    tail = int(0.35 * SR)
    out = x + [0.0] * tail
    wet = [0.0] * len(out)
    for d, g in taps:
        off = int(d * SR)
        for i, v in enumerate(x):
            wet[i + off] += v * g
    y = 0.0
    for i in range(len(wet)):
        y += 0.35 * (wet[i] - y)
        out[i] += mix * y
    return out


def finish(x, peak=0.8, fade=0.02, rev=0.22):
    if rev:
        x = reverb(x, rev)
    # Coupe le silence final.
    end = len(x)
    while end > 0 and abs(x[end - 1]) < 1e-4:
        end -= 1
    x = x[:end + int(0.01 * SR)]
    m = max(abs(v) for v in x) or 1.0
    x = [v * peak / m for v in x]
    nf = int(fade * SR)
    for i in range(min(nf, len(x))):
        x[-1 - i] *= i / nf
    return x


def write(path, x):
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b''.join(
            struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in x))


def hz(name):
    notes = {'C': -9, 'C#': -8, 'D': -7, 'D#': -6, 'E': -5, 'F': -4, 'F#': -3,
             'G': -2, 'G#': -1, 'A': 0, 'A#': 1, 'B': 2}
    n, o = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((notes[n] + 12 * (o - 4)) / 12)


def build():
    s = {}

    # Toucher léger (boutons, choix).
    s['tap'] = finish(soft(1750, 0.06, tau=0.012, attack=0.001), peak=0.5, rev=0.08)

    # Carte glissée assez loin : petit « tic » boisé.
    s['swipe'] = finish(marimba(hz('A6'), 0.12), peak=0.55, rev=0.1)

    # Oublié : deux notes graves qui descendent, douces (pas punitif).
    x = buf(0.1)
    add(x, marimba(hz('E4'), 0.5))
    add(x, marimba(hz('C4'), 0.6), at=0.11)
    s['again'] = finish(x, peak=0.75)

    # Difficile : une note médium, neutre, avec un léger rebond.
    x = buf(0.1)
    add(x, marimba(hz('D5'), 0.5))
    add(x, marimba(hz('D5'), 0.4), at=0.09, gain=0.45)
    s['hard'] = finish(x, peak=0.6)

    # Bien : tierce majeure montante, marimba + cloche.
    x = buf(0.1)
    add(x, marimba(hz('E5'), 0.5))
    add(x, bell(hz('E5'), 0.8), gain=0.25)
    add(x, marimba(hz('G5'), 0.6), at=0.085)
    add(x, bell(hz('G5'), 1.0), at=0.085, gain=0.35)
    s['good'] = finish(x, peak=0.8)

    # Facile : arpège pétillant + scintillement aigu.
    x = buf(0.1)
    for i, n in enumerate(['C5', 'E5', 'G5', 'C6']):
        add(x, marimba(hz(n), 0.5), at=i * 0.055)
        add(x, bell(hz(n), 1.1), at=i * 0.055, gain=0.35)
    for i in range(6):
        add(x, bell(hz('C7') * random.choice([1, 1.25, 1.5, 2]), 0.5),
            at=0.2 + i * 0.045, gain=0.07)
    s['easy'] = finish(x, peak=0.82)

    # Journée terminée : fanfare (arpège, accord tenu, scintillements).
    x = buf(0.1)
    arp = ['C5', 'E5', 'G5', 'C6', 'E6']
    for i, n in enumerate(arp):
        add(x, marimba(hz(n), 0.6), at=i * 0.075)
        add(x, bell(hz(n), 1.2), at=i * 0.075, gain=0.3)
    t = len(arp) * 0.075 + 0.05
    for n in ['C4', 'C5', 'E5', 'G5', 'C6']:
        add(x, bell(hz(n), 2.0), at=t, gain=0.45)
    add(x, soft(hz('C4'), 1.6, tau=0.6, attack=0.05), at=t, gain=0.18)
    for i in range(14):
        f = hz('C7') * random.choice([1, 1.122, 1.26, 1.335, 1.498, 1.682, 2])
        add(x, bell(f, 0.6), at=t + 0.05 + i * 0.07 + random.uniform(0, 0.03),
            gain=0.06 * (1 - i / 16))
    add(x, noise(0.9, cutoff0=6000, cutoff1=2500), at=t, gain=0.05)
    s['complete'] = finish(x, peak=0.85, rev=0.3)

    # Souvenir qui devient solide : montée + deux cloches.
    x = buf(0.1)
    add(x, glide(500, 1500, 0.22, amp=0.35, curve=1.6))
    add(x, bell(hz('D6'), 1.0), at=0.18)
    add(x, bell(hz('A6'), 1.2), at=0.28)
    s['levelup'] = finish(x, peak=0.78)

    # Série prolongée : trois notes rapides + petit souffle.
    x = buf(0.1)
    add(x, noise(0.3, cutoff0=900, cutoff1=4000), gain=0.18)
    for i, n in enumerate(['G5', 'B5', 'D6']):
        add(x, marimba(hz(n), 0.4), at=0.05 + i * 0.045)
    add(x, bell(hz('G6'), 0.9), at=0.2, gain=0.4)
    s['streak'] = finish(x, peak=0.78)

    # Demain : deux « boop » doux qui descendent.
    x = buf(0.1)
    add(x, soft(hz('A4'), 0.3, tau=0.1))
    add(x, soft(hz('E4'), 0.35, tau=0.12), at=0.12)
    s['postpone'] = finish(x, peak=0.6)

    # Annuler : glissando descendant, comme un retour arrière.
    x = buf(0.05)
    add(x, soft(1600, 0.04, tau=0.01, attack=0.001), gain=0.4)
    add(x, glide(950, 380, 0.2, amp=0.6, curve=0.7), at=0.01)
    s['undo'] = finish(x, peak=0.6)

    # Ajout : « pop » de bulle.
    x = buf(0.05)
    add(x, glide(260, 820, 0.07, amp=1.0, tau=0.035, attack=0.001, curve=0.5))
    add(x, marimba(hz('C6'), 0.25), at=0.045, gain=0.25)
    s['add'] = finish(x, peak=0.7, rev=0.15)

    # Suppression : petit choc sourd.
    x = buf(0.05)
    add(x, glide(150, 55, 0.18, amp=1.0, tau=0.06, attack=0.002))
    add(x, noise(0.12, cutoff0=700, cutoff1=200, shape='decay'), gain=0.4)
    s['delete'] = finish(x, peak=0.65, rev=0.12)

    # Interrupteur / sélection.
    s['toggle'] = finish(marimba(hz('E6'), 0.12), peak=0.4, rev=0.08)

    return s


if __name__ == '__main__':
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, data in build().items():
        write(out / f'{name}.wav', data)
        print(f'{name}: {len(data) / SR:.2f} s')
