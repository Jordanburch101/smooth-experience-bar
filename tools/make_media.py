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


def make_bubble(path, size=64):
    """Glassy bubble: soft rim lit from below right, faint body, a bright highlight and a small glint."""

    def fn(dx, dy, d):
        lit = 0.55 + 0.45 * max(0.0, (dx + dy) / 1.414)  # light passing through, toward the bottom right
        ring = math.exp(-((d - 0.8) / 0.14) ** 2) * lit
        body = 0.2 * min(1.0, max(0.0, (0.8 - d) / 0.15))
        hl = math.exp(-(math.hypot((dx + 0.3) / 1.3, dy + 0.34) / 0.24) ** 2)
        glint = 0.7 * math.exp(-(math.hypot(dx - 0.4, dy - 0.38) / 0.12) ** 2)
        a = min(1.0, ring * 0.9 + body + hl + glint)
        if d > 0.95:
            a *= max(0.0, 1 - (d - 0.95) / 0.05)
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


class TileWorley:
    """Cellular noise that tiles over cx x cy cells. Returns distances to the nearest two points."""

    def __init__(self, cx, cy, seed):
        rnd = random.Random(seed)
        self.cx, self.cy = cx, cy
        self.pts = [[(rnd.random(), rnd.random()) for _ in range(cx)] for _ in range(cy)]

    def __call__(self, u, v):
        x, y = u * self.cx, v * self.cy
        ix, iy = math.floor(x), math.floor(y)
        f1 = f2 = 9.0
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                gx, gy = ix + ox, iy + oy
                px, py = self.pts[gy % self.cy][gx % self.cx]
                d = math.hypot(gx + px - x, gy + py - y)
                if d < f1:
                    f1, f2 = d, f1
                elif d < f2:
                    f2 = d
        return f1, f2


def write_field(path, w, h, field, power=1.0):
    """field(u, v) -> value >= 0; normalised to its peak and written as white with alpha."""
    values = [[field(x / w, y / h) for x in range(w)] for y in range(h)]
    peak = max(max(r) for r in values) or 1
    write_tga(path, w, h, lambda x, y: (1, 1, 1, (values[y][x] / peak) ** power))


def make_heat(path, w=256, h=64):
    """Vertical flame tongues for fire."""
    base = [(TileNoise(16 * 2**i, 2 * 2**i, 70 + i), 0.5**i) for i in range(3)]
    warp = [(TileNoise(8, 2, 80), 1.0)]

    def field(u, v):
        wu = u + (fbm(warp, u, v) - 0.5) * 0.08
        n = fbm(base, wu % 1.0, v)
        return (1 - abs(2 * n - 1)) ** 4 * (0.35 + 0.65 * v)

    write_field(path, w, h, field)


def make_cracks(path, w=256, h=64):
    """Glowing cell edges, like cooling lava."""
    cells = TileWorley(16, 4, 90)
    warp = [(TileNoise(8, 2, 91), 1.0)]

    def field(u, v):
        f1, f2 = cells((u + (fbm(warp, u, v) - 0.5) * 0.02) % 1.0, v)
        e = f2 - f1
        return math.exp(-(e / 0.06) ** 2) + 0.35 * math.exp(-(e / 0.25) ** 2)

    write_field(path, w, h, field)


def make_caustics(path, w=256, h=64):
    """Soft rippling light, like sun through water."""
    cells = TileWorley(12, 3, 100)
    warp_x = [(TileNoise(8, 2, 101), 1.0), (TileNoise(16, 4, 102), 0.5)]
    warp_y = [(TileNoise(8, 2, 103), 1.0), (TileNoise(16, 4, 104), 0.5)]

    def field(u, v):
        wu = u + (fbm(warp_x, u, v) - 0.5) * 0.06
        wv = v + (fbm(warp_y, u, v) - 0.5) * 0.25
        f1, f2 = cells(wu % 1.0, wv % 1.0)
        return math.exp(-((f2 - f1) / 0.14) ** 2)

    write_field(path, w, h, field, 1.6)


def make_nebula(path, w=256, h=64):
    """Soft clouds."""
    base = [(TileNoise(8 * 2**i, 2 * 2**i, 110 + i), 0.55**i) for i in range(4)]
    warp_x = [(TileNoise(4, 1, 120), 1.0), (TileNoise(8, 2, 121), 0.5)]
    warp_y = [(TileNoise(4, 2, 122), 1.0), (TileNoise(8, 4, 123), 0.5)]

    def field(u, v):
        wu = u + (fbm(warp_x, u, v) - 0.5) * 0.25
        wv = v + (fbm(warp_y, u, v) - 0.5) * 0.8
        n = fbm(base, wu % 1.0, wv % 1.0)
        return max(0.0, n - 0.3)

    write_field(path, w, h, field, 1.2)


def make_tendrils(path, w=256, h=64):
    """Long thin streaks that writhe, for the void."""
    base = [(TileNoise(4 * 2**i, 4 * 2**i, 130 + i), 0.5**i) for i in range(3)]
    warp_x = [(TileNoise(4, 1, 140), 1.0)]
    warp_y = [(TileNoise(4, 2, 141), 1.0), (TileNoise(8, 4, 142), 0.5)]

    def field(u, v):
        wu = u + (fbm(warp_x, u, v) - 0.5) * 0.4
        wv = v + (fbm(warp_y, u, v) - 0.5) * 1.2
        n = fbm(base, wu % 1.0, wv % 1.0)
        return (1 - abs(2 * n - 1)) ** 8

    write_field(path, w, h, field)


def make_frost(path, w=256, h=64):
    """Crystalline lines at two scales."""
    big, small = TileWorley(16, 4, 150), TileWorley(32, 8, 151)

    def field(u, v):
        a1, a2 = big(u, v)
        b1, b2 = small(u, v)
        return math.exp(-((a2 - a1) / 0.06) ** 2) + 0.3 * math.exp(-((b2 - b1) / 0.1) ** 2)

    write_field(path, w, h, field)


EDGE_CORE = 0.7  # where the bright line sits across the edge texture; Liquid.lua matches it


def make_edge(path, w=32, h=48):
    """Soft bright line along the liquid front, one per slice.

    Across: a sharp core with a soft glow into the liquid and a quick fade out of it.
    Down: ramp, flat, ramp in thirds. Neighbouring slices overlap on the ramps, which sum to 1,
    so the line blends between slices instead of stepping.
    """

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        d = u - EDGE_CORE
        a = math.exp(-(abs(d) / 0.18) ** 4) + 0.3 * math.exp(-(d / 0.35) ** 2)
        if d > 0:
            a *= max(0.0, 1 - d / (1 - EDGE_CORE))
        k = min(1.0, v * 3, (1 - v) * 3)
        return 1, 1, 1, min(1.0, a) * math.sin(k * math.pi / 2) ** 2

    write_tga(path, w, h, pixel)


def make_foam(path, w=32, h=48):
    """Froth where the liquid meets quest or rested XP, one per slice.

    Across: bright at the contact line (left) fading into the segment, with specks of foam.
    Down: the same ramp, flat, ramp thirds as Edge.tga so slices blend.
    """
    rnd = random.Random(160)
    specks = [(rnd.random() ** 1.6 * 0.8, rnd.random(), 0.05 + rnd.random() * 0.07) for _ in range(28)]

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        a = math.exp(-u / 0.22) * 0.8
        for sx, sy, r in specks:
            d = math.hypot((u - sx) * w / h, v - sy)  # round specks in a non-square texture
            a += 0.7 * math.exp(-(d / r) ** 2) * (1 - sx)
        a *= max(0.0, 1 - u) ** 0.5
        k = min(1.0, v * 3, (1 - v) * 3)
        return 1, 1, 1, min(1.0, a) * math.sin(k * math.pi / 2) ** 2

    write_tga(path, w, h, pixel)


def make_core(path, w=256, h=64):
    """Light from inside the liquid: a soft band through the middle, brighter in patches.

    Tiles across; the bar maps it once from top to bottom.
    """
    patches = [(TileNoise(4 * 2**i, 1, 170 + i), 0.5**i) for i in range(3)]

    def pixel(x, y):
        u, v = x / w, (y + 0.5) / h
        band = math.exp(-((v - 0.5) / 0.26) ** 2)
        return 1, 1, 1, band * (0.45 + 0.55 * fbm(patches, u, 0.0))

    write_tga(path, w, h, pixel)


def make_bolt(path, w=256, rows=8, rh=32):
    """Lightning crawling through cloud, for inside the liquid: `rows` variants stacked, each running
    left to right, so each stroke of a flash can take a new shape.

    A jagged main arc from midpoint displacement whose brightness wanders along its length, as if parts
    of it were behind cloud, with branches that thin out to nothing at their tips. Thin core, faint halo;
    the bloom around it is drawn separately.
    """
    rnd = random.Random(180)

    def arc(x0, y0, x1, y1, amp, depth, lo, hi):
        pts = [(x0, y0), (x1, y1)]
        for _ in range(depth):
            out = [pts[0]]
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                my = (ay + by) / 2 + (rnd.random() - 0.5) * 2 * amp
                out += [((ax + bx) / 2, max(lo, min(hi, my))), (bx, by)]
            pts, amp = out, amp * 0.75
        return pts

    values = []
    for r in range(rows):
        top = r * rh
        lo, hi = top + 4, top + rh - 4
        mid = top + rh / 2
        main = arc(2, mid + rnd.uniform(-5, 5), w - 2, mid + rnd.uniform(-5, 5), rh * 0.3, 7, lo, hi)
        waves = [(rnd.uniform(1, 4), rnd.uniform(0, 6.28)) for _ in range(3)]

        def along(x):  # brightness along the arc: dips where it passes behind cloud
            s = sum(math.sin(x / w * f * 6.28 + p) for f, p in waves) / 3
            return 0.3 + 0.7 * (0.5 + 0.5 * s) ** 1.5

        segs = [(p, q, along((p[0] + q[0]) / 2)) for p, q in zip(main, main[1:])]

        def branch(sx, sy, k0, length, depth):
            ex = sx + rnd.choice((1, 1, -1)) * length
            ey = max(lo, min(hi, sy + rnd.choice((-1, 1)) * rnd.uniform(4, rh * 0.35)))
            pts = arc(sx, sy, ex, ey, rh * 0.15, 5, lo, hi)
            n = len(pts) - 1
            for j, (p, q) in enumerate(zip(pts, pts[1:])):
                segs.append((p, q, k0 * (1 - j / n) ** 1.3))  # thins out toward the tip
            if depth > 0:
                for _ in range(2):
                    j = rnd.randrange(n // 4, n * 3 // 4)
                    branch(*pts[j], k0 * 0.6 * (1 - j / n), length * 0.45, depth - 1)

        for _ in range(4):
            j = rnd.randrange(16, len(main) - 16)
            sx, sy = main[j]
            branch(sx, sy, 0.8 * along(sx), rnd.uniform(25, 60), 1)
        values.append(segs)

    def seg_dist(px, py, ax, ay, bx, by):
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy or 1)))
        return math.hypot(px - ax - vx * t, py - ay - vy * t)

    h = rows * rh
    field = [[0.0] * w for _ in range(h)]
    for r, segs in enumerate(values):
        for y in range(r * rh, (r + 1) * rh):
            for x in range(w):
                a = 0.0
                for (ax, ay), (bx, by), k in segs:
                    if abs(ay - y) > 8 and abs(by - y) > 8:
                        continue
                    d = seg_dist(x + 0.5, y + 0.5, ax, ay, bx, by)
                    a = max(a, k * (math.exp(-(d / 1.0) ** 2) + 0.2 * math.exp(-(d / 2.5) ** 2)))
                fade = min(1.0, x / 20, (w - 1 - x) / 20)  # arcs thin out at their ends
                field[y][x] = min(1.0, a) * fade
    write_tga(path, w, h, lambda x, y: (1, 1, 1, field[y][x]))


def make_shade(path, w=4, h=64):
    """Darkens the top and bottom of the bar like light falling off a glass cylinder.

    Drawn black over everything inside the bar; slightly heavier at the bottom.
    """

    def pixel(x, y):
        v = (y + 0.5) / h
        c = 2 * v - 1
        dark = (1 - math.sqrt(max(0.0, 1 - c * c))) ** 0.8
        return 1, 1, 1, 0.5 * dark * (1 + 0.3 * c)

    write_tga(path, w, h, pixel)


def make_glass_light(path, w=256, h=64):
    """Light on the glass tube, drawn additively over the bar and split at the liquid front so the part
    over the liquid can take its colour.

    A highlight near the top with a narrow core and a soft halo, broken into pieces of varying brightness
    the way a real reflection is; a faint one near the bottom; and bright outer rims, strongest on top.
    The tube's ends are GlassCap.tga.
    """
    rnd = random.Random(190)
    waves_top = [(rnd.uniform(1.5, 5), rnd.uniform(0, 6.28)) for _ in range(3)]
    waves_low = [(rnd.uniform(1, 3), rnd.uniform(0, 6.28)) for _ in range(2)]

    def pieces(u, waves, cut):  # 0 in the gaps, up to 1 in the brightest stretches
        n = 0.5 + 0.5 * sum(math.sin(u * f * 6.28 + p) for f, p in waves) / len(waves)
        return max(0.0, (n - cut) / (1 - cut)) ** 0.7

    def band(v, centre, width):
        return math.exp(-((v - centre) / width) ** 2)

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        top = pieces(u, waves_top, 0.3) * (0.6 * band(v, 0.2, 0.028) + 0.16 * band(v, 0.22, 0.09))
        low = pieces(u, waves_low, 0.4) * 0.14 * band(v, 0.84, 0.04)
        rim = 0.5 * band(v, 0.015, 0.022) + 0.25 * band(v, 0.985, 0.022)
        return 1, 1, 1, min(1.0, top + low + rim)

    write_tga(path, w, h, pixel)


def make_glass_dark(path, w=4, h=64):
    """Thin dark lines just inside the rims, where the glass is seen edge on: gives the tube thickness.

    Drawn black over the bar.
    """

    def pixel(x, y):
        v = (y + 0.5) / h
        return 1, 1, 1, 0.4 * math.exp(-((v - 0.055) / 0.022) ** 2) + 0.35 * math.exp(-((v - 0.945) / 0.022) ** 2)

    write_tga(path, w, h, pixel)


def make_glass_cap(path, w=32, h=64):
    """Light on the left end of the tube (mirrored for the right). Seen from the side a tube's end is
    straight, so this matches the top and bottom: a bright rim along the very end, strongest at the top.
    """

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        return 1, 1, 1, 0.45 * math.exp(-((u - 0.03) / 0.044) ** 2) * (1 - 0.45 * v)

    write_tga(path, w, h, pixel)


def make_glass_cap_dark(path, w=32, h=64):
    """Shadow on the left end of the tube (mirrored for the right): a thin dark line just inside the rim
    for the glass's thickness, like GlassDark.tga along the top and bottom, and a slight darkening toward
    the end. Drawn black.
    """

    def pixel(x, y):
        u = (x + 0.5) / w
        return 1, 1, 1, min(1.0, 0.4 * math.exp(-((u - 0.11) / 0.044) ** 2) + 0.15 * (1 - u) ** 3)

    write_tga(path, w, h, pixel)


def make_round_end(path, right=False, w=40, h=64):
    """Mask that rounds off one end of the bar for Rounded Liquid: a half circle as tall as the bar, then
    solid. The mask is 0.625 bar heights wide with the circle's centre half a bar height in, so its inner
    columns are fully solid and stretch along the rest of the bar (the mask uses CLAMP).
    """

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        if right:
            u = 1 - u
        dx = u * w / h - 0.5  # in bar heights from the circle's centre
        if dx >= 0:
            return 1, 1, 1, 1
        d = math.hypot(dx, v - 0.5)
        return 1, 1, 1, max(0.0, min(1.0, 0.5 + (0.5 - d) * h))

    write_tga(path, w, h, pixel)


def make_glass_cap_round(path, dark=False, w=32, h=64):
    """Glass on the left end of the tube when it is rounded off (mirrored for the right): the rim, or
    with dark the thin line just inside it, following the half circle of the RoundEnd mask.
    """

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        d = math.hypot(u * 0.5 - 0.5, v - 0.5)  # in bar heights; the texture is half a bar height wide
        if dark:
            return 1, 1, 1, 0.4 * math.exp(-((d - 0.435) / 0.022) ** 2)
        return 1, 1, 1, 0.5 * math.exp(-((d - 0.482) / 0.022) ** 2) * (1.1 - 0.6 * v)

    write_tga(path, w, h, pixel)


def make_wisp(path, size=48):
    """A soft, uneven puff of vapour, taller than wide, for wisps rising off the liquid."""
    lumps = [(TileNoise(4 * 2**i, 4 * 2**i, 200 + i), 0.5**i) for i in range(3)]

    def fn(dx, dy, d):
        e = math.hypot(dx * 1.3, dy * 0.9)
        body = max(0.0, 1 - e) ** 1.6
        return 1, 1, 1, body * (0.35 + 0.65 * fbm(lumps, (dx + 1) / 2, (dy + 1) / 2))

    write_tga(path, size, size, radial(size, fn))


def make_ember(path, size=32):
    """Teardrop flame: wide and bright at the bottom, thin at the top."""

    def fn(dx, dy, d):
        width = 0.12 + 0.22 * (dy + 1) / 2
        a = math.exp(-(dx / width) ** 2 - ((dy - 0.15) / 0.6) ** 2)
        a += 0.6 * math.exp(-(math.hypot(dx, dy - 0.35) / 0.18) ** 2)
        return 1, 1, 1, min(1.0, a)

    write_tga(path, size, size, radial(size, fn))


def make_snow(path, size=32):
    """Six-armed snowflake with side branches."""

    def seg_dist(px, py, ax, ay, bx, by):
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)))
        return math.hypot(px - ax - vx * t, py - ay - vy * t)

    segs = []
    for k in range(6):
        a = k * math.pi / 3
        ex, ey = math.cos(a) * 0.85, math.sin(a) * 0.85
        segs.append((0, 0, ex, ey))
        for side in (-1, 1):
            mx, my = math.cos(a) * 0.5, math.sin(a) * 0.5
            b = a + side * math.pi / 4
            segs.append((mx, my, mx + math.cos(b) * 0.25, my + math.sin(b) * 0.25))

    def fn(dx, dy, d):
        dist = min(seg_dist(dx, dy, *s) for s in segs)
        return 1, 1, 1, min(1.0, math.exp(-(dist / 0.06) ** 2) + 0.5 * math.exp(-(d / 0.15) ** 2))

    write_tga(path, size, size, radial(size, fn))


def make_leaf(path, size=32):
    """Pointed leaf on the diagonal with a faint centre vein."""

    def fn(dx, dy, d):
        c, s = math.cos(math.pi / 4), math.sin(math.pi / 4)
        u, v = (dx * c + dy * s) / 0.9, (-dx * s + dy * c) / 0.9
        if abs(u) >= 1:
            return 1, 1, 1, 0
        half = 0.38 * (1 - u * u) ** 0.8
        edge = half - abs(v)
        if edge <= 0:
            return 1, 1, 1, 0
        a = min(1.0, edge / 0.06)
        vein = 1 - 0.45 * math.exp(-(v / 0.03) ** 2)
        return 1, 1, 1, a * vein

    write_tga(path, size, size, radial(size, fn))


def make_star(path, size=32):
    """Sharp four-point star with shorter diagonals."""

    def fn(dx, dy, d):
        core = math.exp(-(d / 0.1) ** 2)
        main = math.exp(-abs(dx) / 0.025) * math.exp(-abs(dy) / 0.45) + math.exp(-abs(dy) / 0.025) * math.exp(-abs(dx) / 0.45)
        rx, ry = (dx + dy) * 0.7071, (dx - dy) * 0.7071
        diag = 0.5 * (math.exp(-abs(rx) / 0.02) * math.exp(-abs(ry) / 0.2) + math.exp(-abs(ry) / 0.02) * math.exp(-abs(rx) / 0.2))
        return 1, 1, 1, min(1.0, core + main + diag)

    write_tga(path, size, size, radial(size, fn))


def make_crystal(path, size=32):
    """Elongated ice shard with bright edges and a centre facet."""

    def fn(dx, dy, d):
        k = abs(dx) / 0.42 + abs(dy) / 0.95
        if k >= 1:
            return 1, 1, 1, 0
        edge = math.exp(-((1 - k) / 0.12) ** 2)
        facet = 0.5 * math.exp(-(dx / 0.04) ** 2)
        coverage = min(1.0, (1 - k) / 0.08)  # soft outline instead of a hard cut
        return 1, 1, 1, min(1.0, 0.35 + edge * 0.65 + facet) * coverage

    write_tga(path, size, size, radial(size, fn))


def make_icon(path):
    """Addon list icon, from branding/ (needs Pillow; skipped without it).

    An addon TGA rather than the game's INV_Scroll_10, because Forever does not load game files by path.
    """
    try:
        from PIL import Image
    except ImportError:
        print("Pillow not installed, Icon.tga not regenerated")
        return
    # The game's original with its border, which suits the in-game addon list.
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "branding", "icon-original-64.png")
    im = Image.open(src).convert("RGBA").resize((64, 64))
    px = im.load()
    write_tga(path, 64, 64, lambda x, y: tuple(c / 255 for c in px[x, y]))


def make_grip(path, size=16):
    """Resize grip: three diagonal ridges in the bottom-right corner."""

    def pixel(x, y):
        s = (x + y) - (size - 1)  # 0 on the anti-diagonal, growing toward the corner
        if s < 0:
            return 1, 1, 1, 0
        a = max(0.0, 1 - abs((s % 4) - 1) / 1.2) if s < 12 else 0.0
        return 1, 1, 1, a

    write_tga(path, size, size, pixel)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    make_swirl(os.path.join(out, "Swirl.tga"))
    make_heat(os.path.join(out, "Heat.tga"))
    make_cracks(os.path.join(out, "Cracks.tga"))
    make_caustics(os.path.join(out, "Caustics.tga"))
    make_nebula(os.path.join(out, "Nebula.tga"))
    make_tendrils(os.path.join(out, "Tendrils.tga"))
    make_frost(os.path.join(out, "Frost.tga"))
    make_bubble(os.path.join(out, "Bubble.tga"))
    make_mote(os.path.join(out, "Mote.tga"))
    make_glow(os.path.join(out, "Glow.tga"))
    make_edge(os.path.join(out, "Edge.tga"))
    make_foam(os.path.join(out, "Foam.tga"))
    make_core(os.path.join(out, "Core.tga"))
    make_bolt(os.path.join(out, "Bolt.tga"))
    make_wisp(os.path.join(out, "Wisp.tga"))
    make_shade(os.path.join(out, "Shade.tga"))
    make_glass_light(os.path.join(out, "GlassLight.tga"))
    make_glass_dark(os.path.join(out, "GlassDark.tga"))
    make_glass_cap(os.path.join(out, "GlassCap.tga"))
    make_glass_cap_dark(os.path.join(out, "GlassCapDark.tga"))
    make_glass_cap_round(os.path.join(out, "GlassCapRound.tga"))
    make_glass_cap_round(os.path.join(out, "GlassCapRoundDark.tga"), dark=True)
    make_round_end(os.path.join(out, "RoundEndL.tga"))
    make_round_end(os.path.join(out, "RoundEndR.tga"), right=True)
    make_ember(os.path.join(out, "Ember.tga"))
    make_snow(os.path.join(out, "Snow.tga"))
    make_leaf(os.path.join(out, "Leaf.tga"))
    make_star(os.path.join(out, "Star.tga"))
    make_crystal(os.path.join(out, "Crystal.tga"))
    make_grip(os.path.join(out, "Grip.tga"))
    make_icon(os.path.join(out, "Icon.tga"))
    print("wrote", sorted(os.listdir(out)))


if __name__ == "__main__":
    main()
