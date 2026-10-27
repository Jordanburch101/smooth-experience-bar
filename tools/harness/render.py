"""Run SmoothExperienceBar against the WoW mock and draw it the way the game would.

Used by run.py (quick previews) and gallery.py (listing screenshots). Draws textures with their
blend modes, gradients, texture coordinates and rotation, and text in the game font with outline and
shadow, onto any background.
"""
import os
import re

import numpy as np
try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # some builds of lupa ship without LuaJIT
    from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4}
FPS = 60

# The game font isn't shipped with the repo; DialogueUI carries a copy. Falls back to Arial.
FONT_CANDIDATES = [
    os.environ.get("SEB_FONT", ""),
    r"C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\DialogueUI\Fonts\frizqt__.ttf",
    r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\DialogueUI\Fonts\frizqt__.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
]
FONT_PATH = next(p for p in FONT_CANDIDATES if p and os.path.exists(p))
_fonts = {}


def font(size):
    size = max(6, int(round(size)))
    if size not in _fonts:
        _fonts[size] = ImageFont.truetype(FONT_PATH, size)
    return _fonts[size]


# The scenario the previews play: login, a few kills, a quest turn-in, then a level-up.
P = "__player"
SCENARIO = [
    (0.0, "__quests = {{id = 1, xp = 15000, complete = true}}; __fire('QUEST_LOG_UPDATE')"),
    (1.0, f"{P}.xp = {P}.xp + 900; {P}.rested = {P}.rested - 900; __fire('PLAYER_XP_UPDATE', 'player')"),
    (1.5, f"{P}.xp = {P}.xp + 900; __fire('PLAYER_XP_UPDATE', 'player')"),
    (2.0, f"{P}.xp = {P}.xp + 900; __fire('PLAYER_XP_UPDATE', 'player')"),
    (2.4, f"{P}.xp = {P}.xp + 900; __fire('PLAYER_XP_UPDATE', 'player')"),
    # XP lands first, then the turn-in event, then the quest log catches up.
    (4.0, f"{P}.xp = {P}.xp + 15000; __fire('PLAYER_XP_UPDATE', 'player'); __fire('QUEST_TURNED_IN', 1, 15000, 0)"),
    (4.05, "__quests = {}; __fire('QUEST_LOG_UPDATE')"),
    (7.5, f"{P}.level = 58; {P}.xp = 40000; {P}.max = 330000; __fire('PLAYER_XP_UPDATE', 'player'); __fire('PLAYER_LEVEL_UP', 58)"),
]


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if v in ("true", "false"):
        return v
    try:
        float(v)
        return v
    except ValueError:
        return repr(v)


class Session:
    """One addon instance in the mock, logged in and ready to play the scenario."""

    def __init__(self, addon_dir, settings=None, scenario=SCENARIO, before_login="", after_login=""):
        """before_login / after_login: Lua run around PLAYER_ENTERING_WORLD, e.g. to seed session stats."""
        self.addon_dir = addon_dir
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
        self.G = self.lua.globals()
        # Item access: inside a class, attribute names starting with __ get mangled.
        self.G["__loadAddon"](addon_dir.replace("\\", "/"), "SmoothExperienceBar")
        self._step = self.G["__step"]
        apply = "".join(f"__settings[{k!r}]:SetValue({lua_value(v)}); " for k, v in (settings or {}).items())
        self.lua.execute("__fire('ADDON_LOADED', 'SmoothExperienceBar'); " + apply + before_login
                         + "; __fire('PLAYER_ENTERING_WORLD', true, false); " + after_login)
        self.pending = sorted(scenario, key=lambda e: e[0])
        self.t = 0.0
        self._media = {}
        self._visible = self.lua.eval("""function()
            local out = {}
            for _, r in ipairs(__regions) do
                if r.parent == SmoothExperienceBarFrame and r.shown and r.alpha > 0.001 then out[#out + 1] = r end
            end
            return out
        end""")

    @property
    def bar_size(self):
        bar = self.G.SmoothExperienceBarFrame
        return bar.w, bar.h

    def run_until(self, t):
        while self.t < t - 1e-9:
            while self.pending and self.pending[0][0] <= self.t:
                self.lua.execute(self.pending.pop(0)[1])
            self._step(1 / FPS)
            self.t += 1 / FPS

    # ------------------------------------------------------------------ drawing

    def media(self, path):
        name = path.split("\\")[-1]
        if name not in self._media:
            im = Image.open(os.path.join(self.addon_dir, "Media", name + ".tga")).convert("RGBA")
            self._media[name] = np.asarray(im).astype(np.float32) / 255
        return self._media[name]

    def regions(self):
        v = self._visible()
        regions = [v[i + 1] for i in range(len(v))]
        regions.sort(key=lambda r: (LAYERS.get(r.layer, 2), r.sub, r.order))
        return regions

    def _sample(self, img, r, pw, ph):
        th, tw = img.shape[:2]
        left, right, top, bottom = (r.tc[i] for i in range(1, 5))
        u = (left + (right - left) * (np.arange(pw) + 0.5) / pw) * tw - 0.5
        v = (top + (bottom - top) * (np.arange(ph) + 0.5) / ph) * th - 0.5
        x0, y0 = np.floor(u).astype(int), np.floor(v).astype(int)
        fx, fy = (u - x0)[None, :, None], (v - y0)[:, None, None]
        if r.wrap == "REPEAT":
            xa, xb, ya, yb = x0 % tw, (x0 + 1) % tw, y0 % th, (y0 + 1) % th
        else:
            xa, xb = np.clip(x0, 0, tw - 1), np.clip(x0 + 1, 0, tw - 1)
            ya, yb = np.clip(y0, 0, th - 1), np.clip(y0 + 1, 0, th - 1)
        top_row = img[ya][:, xa] * (1 - fx) + img[ya][:, xb] * fx
        bottom_row = img[yb][:, xa] * (1 - fx) + img[yb][:, xb] * fx
        return top_row * (1 - fy) + bottom_row * fy

    def _draw_texture(self, canvas, r, ox, oy, k):
        left, top, w, h = r.Rect(r)
        if w <= 0 or h <= 0:
            return
        x0, y0 = int(round(ox + left * k)), int(round(oy + top * k))
        x1, y1 = int(round(ox + (left + w) * k)), int(round(oy + (top + h) * k))
        pw, ph = x1 - x0, y1 - y0
        if pw <= 0 or ph <= 0:
            return
        if r.file == "SOLID":
            src = np.ones((ph, pw, 4), np.float32) * np.array([r.color[i] for i in range(1, 5)], np.float32)
        else:
            src = self._sample(self.media(r.file), r, pw, ph)
        if r.rotation and abs(r.rotation) > 0.01:
            im = Image.fromarray((np.clip(src, 0, 1) * 255).astype(np.uint8), "RGBA")
            im = im.rotate(np.degrees(r.rotation), resample=Image.BICUBIC)
            src = np.asarray(im).astype(np.float32) / 255
        if r.grad:
            c1 = np.array([r.grad[1][i] for i in range(1, 5)], np.float32)
            c2 = np.array([r.grad[2][i] for i in range(1, 5)], np.float32)
            src = src * (c1 + (c2 - c1) * ((np.arange(pw) + 0.5) / pw)[None, :, None])
        else:
            src = src * np.array([r.vc[i] for i in range(1, 5)], np.float32)
        alpha = src[..., 3:4] * r.alpha
        cx0, cy0 = max(0, x0), max(0, y0)
        cx1, cy1 = min(canvas.shape[1], x1), min(canvas.shape[0], y1)
        if cx0 >= cx1 or cy0 >= cy1:
            return
        s = src[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0, :3]
        a = alpha[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
        d = canvas[cy0:cy1, cx0:cx1]
        if r.blend == "ADD":
            d += s * a
        else:
            d[:] = d * (1 - a) + s * a

    def _draw_text(self, draw, r, ox, oy, k):
        text = r.text or ""
        if not text:
            return
        segments, color = [], (255, 255, 255)
        for part in re.split(r"(\|c[0-9a-fA-F]{8}|\|r)", text):
            if part.startswith("|c"):
                color = tuple(int(part[i:i + 2], 16) for i in (4, 6, 8))
            elif part == "|r":
                color = (255, 255, 255)
            elif part:
                segments.append((part, color))
        f = font(r.fontSize * k)
        # Real text width, so right-aligned and centred text sits where the game puts it.
        point, a = next(iter((p, r.points[p]) for p in r.points))
        bw, bh = self.bar_size
        ax = 0 if "LEFT" in a.relPoint else (bw if "RIGHT" in a.relPoint else bw / 2)
        ay = 0 if "TOP" in a.relPoint else (bh if "BOTTOM" in a.relPoint else bh / 2)
        x, y = ox + (ax + a.x) * k, oy + (ay - a.y) * k
        total = sum(f.getlength(s) for s, _ in segments)
        if "RIGHT" in point:
            x -= total
        elif "LEFT" not in point:
            x -= total / 2
        valign = "a" if "TOP" in point else ("d" if "BOTTOM" in point else "m")
        stroke = max(1, int(round(k * 0.8)))
        for s, c in segments:
            draw.text((x + k, y + k), s, font=f, fill=(0, 0, 0, 200), anchor="l" + valign,
                      stroke_width=stroke, stroke_fill=(0, 0, 0, 200))
            draw.text((x, y), s, font=f, fill=c + (255,), anchor="l" + valign,
                      stroke_width=stroke, stroke_fill=(0, 0, 0, 255))
            x += f.getlength(s)

    def render(self, background, ox, oy, k, ss=2):
        """Draw the bar onto a copy of background (PIL RGB) with its top-left at (ox, oy), k px per unit."""
        big = background.convert("RGB").resize((background.width * ss, background.height * ss), Image.BICUBIC)
        canvas = np.asarray(big).astype(np.float32) / 255
        texts = []
        for r in self.regions():
            if r.kind == "Texture":
                self._draw_texture(canvas, r, ox * ss, oy * ss, k * ss)
            elif r.kind == "FontString" and r.text:
                texts.append(r)
        img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8))
        img = img.resize(background.size, Image.LANCZOS).convert("RGBA")
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        for r in texts:
            self._draw_text(draw, r, ox, oy, k)
        return Image.alpha_composite(img, layer).convert("RGB")
