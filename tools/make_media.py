"""Generate the TGA textures used by SmoothExperienceBar.

Usage: python make_media.py <output dir>
"""
import math
import os
import random
import struct
import sys


def write_tga(path, w, h, pixel):
    """pixel(x, y) -> (r, g, b, a) floats 0..1, y = 0 at the top."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    out = bytearray(header)
    for y in range(h - 1, -1, -1):  # bottom-left origin
        for x in range(w):
            r, g, b, a = (max(0, min(255, int(c * 255 + 0.5))) for c in pixel(x, y))
            out += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(out)


class TileNoise:
    """Value noise that tiles over a px x py lattice."""

    def __init__(self, px, py, seed):
        rnd = random.Random(seed)
        self.px, self.py = px, py
        self.lat = [[rnd.random() for _ in range(px)] for _ in range(py)]

    def __call__(self, x, y):
        x0, y0 = math.floor(x), math.floor(y)
        fx, fy = x - x0, y - y0
        sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        lat, px, py = self.lat, self.px, self.py
        a = lat[y0 % py][x0 % px]
        b = lat[y0 % py][(x0 + 1) % px]
        c = lat[(y0 + 1) % py][x0 % px]
        d = lat[(y0 + 1) % py][(x0 + 1) % px]
        top = a + (b - a) * sx
        bottom = c + (d - c) * sx
        return top + (bottom - top) * sy


def fbm(octaves, u, v):
    total, norm = 0.0, 0.0
    for noise, amp in octaves:
        total += noise(u * noise.px, v * noise.py) * amp
        norm += amp
    return total / norm


def make_swirl(path, w=256, h=64):
    """Thin, warped, tileable veins - the magic inside the liquid."""
    base = [(TileNoise(8 * 2**i, 2 * 2**i, 10 + i), 0.5**i) for i in range(4)]
    warp_x = [(TileNoise(4 * 2**i, 1 * 2**i, 30 + i), 0.5**i) for i in range(3)]
    warp_y = [(TileNoise(4 * 2**i, 1 * 2**i, 50 + i), 0.5**i) for i in range(3)]

    values = []
    for y in range(h):
        row = []
        for x in range(w):
            u, v = x / w, y / h
            wu = u + (fbm(warp_x, u, v) - 0.5) * 0.35
            wv = v + (fbm(warp_y, u, v) - 0.5) * 0.9
            n = fbm(base, wu % 1.0, wv % 1.0)
            ridge = 1 - abs(2 * n - 1)
            row.append(ridge ** 5)
        values.append(row)
    peak = max(max(r) for r in values) or 1
    write_tga(path, w, h, lambda x, y: (1, 1, 1, values[y][x] / peak))


def radial(size, fn):
    c = (size - 1) / 2

    def pixel(x, y):
        dx, dy = (x - c) / c, (y - c) / c
        return fn(dx, dy, math.hypot(dx, dy))

    return pixel


def make_bubble(path, size=32):
    def fn(dx, dy, d):
        ring = math.exp(-((d - 0.82) / 0.11) ** 2)
        body = 0.12 if d < 0.82 else 0.0
        hl = 0.9 * math.exp(-((math.hypot(dx + 0.32, dy + 0.32)) / 0.18) ** 2)
        a = min(1.0, ring * 0.85 + body + hl)
        if d > 1:
            a = 0.0
        return 1, 1, 1, a

    write_tga(path, size, size, radial(size, fn))


def make_mote(path, size=32):
    def fn(dx, dy, d):
        core = math.exp(-(d / 0.18) ** 2)
        halo = 0.35 * math.exp(-(d / 0.55) ** 2)
        star = 0.55 * (math.exp(-(dx / 0.05) ** 2) * math.exp(-(dy / 0.75) ** 2)
                       + math.exp(-(dy / 0.05) ** 2) * math.exp(-(dx / 0.75) ** 2))
        a = min(1.0, core + halo + star)
        if d > 1:
            a *= max(0.0, 1 - (d - 1) * 4)
        return 1, 1, 1, a

    write_tga(path, size, size, radial(size, fn))


def make_glow(path, size=64):
    def fn(dx, dy, d):
        return 1, 1, 1, max(0.0, math.exp(-(d / 0.45) ** 2) - 0.02)

    write_tga(path, size, size, radial(size, fn))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    make_swirl(os.path.join(out, "Swirl.tga"))
    make_bubble(os.path.join(out, "Bubble.tga"))
    make_mote(os.path.join(out, "Mote.tga"))
    make_glow(os.path.join(out, "Glow.tga"))
    print("wrote", sorted(os.listdir(out)))


if __name__ == "__main__":
    main()
