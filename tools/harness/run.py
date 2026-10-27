"""Load SmoothExperienceBar against the WoW mock, play a scripted scenario and render it.

Usage: python run.py <addon dir> <out dir> [setting=value ...]
e.g.   python run.py SmoothExperienceBar preview theme=fel width=800 height=48
Writes preview.gif (30 fps) and sheet.png (stills at key moments).
"""
import math
import os
import sys

import numpy as np
try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # some builds of lupa ship without LuaJIT
    from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

ADDON, OUT = sys.argv[1], sys.argv[2]
SETTINGS = dict(arg.split("=", 1) for arg in sys.argv[3:])
HERE = os.path.dirname(os.path.abspath(__file__))
FPS, SS = 60, 2  # sim rate, supersampling
BAR_W, BAR_H = int(SETTINGS.get("width", 600)), int(SETTINGS.get("height", 30))


def lua_value(v):
    if v in ("true", "false"):
        return v
    try:
        float(v)
        return v
    except ValueError:
        return repr(v)


APPLY_SETTINGS = "".join(f"__settings[{k!r}]:SetValue({lua_value(v)}); " for k, v in SETTINGS.items())
MARGIN_X, MARGIN_Y = 20, int(40 * max(1, BAR_H / 30))
IMG_W, IMG_H = BAR_W + MARGIN_X * 2, BAR_H + MARGIN_Y * 2
LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4}
SCENE = np.array([0.13, 0.16, 0.24])

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
G = lua.globals()
ns = G.__loadAddon(ADDON.replace("\\", "/"), "SmoothExperienceBar")

_media = {}


def media(path):
    name = path.split("\\")[-1]
    if name not in _media:
        im = Image.open(os.path.join(ADDON, "Media", name + ".tga")).convert("RGBA")
        _media[name] = np.asarray(im).astype(np.float32) / 255
    return _media[name]


def lua_list(t, n):
    return [t[i + 1] for i in range(n)]


def draw_texture(canvas, r, ox, oy):
    left, top, w, h = r.Rect(r)
    if w <= 0 or h <= 0:
        return
    x0, y0 = int(round((ox + left) * SS)), int(round((oy + top) * SS))
    x1, y1 = int(round((ox + left + w) * SS)), int(round((oy + top + h) * SS))
    pw, ph = x1 - x0, y1 - y0
    if pw <= 0 or ph <= 0:
        return

    if r.file in ("SOLID",) or (r.file or "").endswith("WHITE8x8"):
        src = np.ones((ph, pw, 4), np.float32)
        if r.color:
            src[..., :4] *= np.array(lua_list(r.color, 4), np.float32)
    else:
        img = media(r.file)
        th, tw = img.shape[:2]
        l, rr, t, b = lua_list(r.tc, 4)
        u = l + (rr - l) * (np.arange(pw) + 0.5) / pw
        v = t + (b - t) * (np.arange(ph) + 0.5) / ph
        if r.wrap == "REPEAT":
            u, v = u % 1.0, v % 1.0
        ui = np.clip((u * tw).astype(int), 0, tw - 1)
        vi = np.clip((v * th).astype(int), 0, th - 1)
        src = img[vi][:, ui].copy()

    if r.grad:
        c1 = np.array(lua_list(r.grad[1], 4), np.float32)
        c2 = np.array(lua_list(r.grad[2], 4), np.float32)
        k = ((np.arange(pw) + 0.5) / pw)[None, :, None]
        src *= c1 + (c2 - c1) * k
    else:
        src *= np.array(lua_list(r.vc, 4), np.float32)
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


try:
    FONT = {s: ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", s) for s in range(8, 30)}
except OSError:
    FONT = None


def render():
    canvas = np.empty((IMG_H * SS, IMG_W * SS, 3), np.float32)
    canvas[:] = SCENE
    visible = lua.eval("""function()
        local out = {}
        for _, r in ipairs(__regions) do
            if r.parent == SmoothExperienceBarFrame and r.shown and r.alpha > 0.001 then out[#out + 1] = r end
        end
        return out
    end""")()
    regions = [visible[i + 1] for i in range(len(visible))]
    regions.sort(key=lambda r: (LAYERS.get(r.layer, 2), r.sub, r.order))
    texts = []
    for r in regions:
        if r.kind == "Texture":
            draw_texture(canvas, r, MARGIN_X, MARGIN_Y)
        elif r.kind == "FontString" and r.text:
            texts.append(r)
    img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8))
    img = img.resize((IMG_W, IMG_H), Image.LANCZOS)
    if FONT:
        draw = ImageDraw.Draw(img)
        for r in texts:
            left, top, w, h = r.Rect(r)
            plain = r.text
            import re
            plain = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", plain)
            draw.text((MARGIN_X + left, MARGIN_Y + top), plain, font=FONT.get(int(r.fontSize), FONT[14]),
                      fill=(255, 255, 255), stroke_width=1, stroke_fill=(0, 0, 0))
    return img


# Scenario: (time, label, lua code)
P = "__player"
SCENARIO = [
    (0.0, None, "__quests = {{id = 1, xp = 15000, complete = true}}; __fire('ADDON_LOADED', 'SmoothExperienceBar'); " + APPLY_SETTINGS + "__fire('PLAYER_ENTERING_WORLD', true, false); __fire('QUEST_LOG_UPDATE')"),
    (1.0, "kill", f"{P}.xp = {P}.xp + 900; {P}.rested = {P}.rested - 900; __fire('PLAYER_XP_UPDATE', 'player')"),
    (1.5, None, f"{P}.xp = {P}.xp + 900; __fire('PLAYER_XP_UPDATE', 'player')"),
    (2.0, None, f"{P}.xp = {P}.xp + 900; __fire('PLAYER_XP_UPDATE', 'player')"),
    (2.4, "kills", f"{P}.xp = {P}.xp + 900; __fire('PLAYER_XP_UPDATE', 'player')"),
    # XP lands first, then the turn-in event, then the quest log catches up.
    (4.0, "turn-in", f"{P}.xp = {P}.xp + 15000; __fire('PLAYER_XP_UPDATE', 'player'); __fire('QUEST_TURNED_IN', 1, 15000, 0)"),
    (4.05, None, "__quests = {}; __fire('QUEST_LOG_UPDATE')"),
    (7.5, "level-up", f"{P}.level = 58; {P}.xp = 40000; {P}.max = 330000; __fire('PLAYER_XP_UPDATE', 'player'); __fire('PLAYER_LEVEL_UP', 58)"),
]
END = 11.0
STILLS = [0.9, 1.15, 2.6, 4.12, 4.35, 4.7, 7.9, 8.3, 10.5]


def main():
    os.makedirs(OUT, exist_ok=True)
    frames, stills = [], []
    pending = sorted(SCENARIO, key=lambda e: e[0])
    still_t = list(STILLS)
    n = int(END * FPS)
    for i in range(n):
        t = i / FPS
        while pending and pending[0][0] <= t:
            _, label, code = pending.pop(0)
            lua.execute(code)
        G.__step(1 / FPS)
        if i % 2 == 0:
            frames.append(render())
        if still_t and t >= still_t[0]:
            stills.append((still_t.pop(0), render()))

    frames[0].save(os.path.join(OUT, "preview.gif"), save_all=True, append_images=frames[1:],
                   duration=int(1000 / 30), loop=0, optimize=False)
    sheet = Image.new("RGB", (IMG_W, IMG_H * len(stills)), (0, 0, 0))
    d = ImageDraw.Draw(sheet)
    for k, (t, im) in enumerate(stills):
        sheet.paste(im, (0, k * IMG_H))
        d.text((4, k * IMG_H + 2), f"t={t:.2f}s", fill=(255, 255, 0))
    sheet.save(os.path.join(OUT, "sheet.png"))
    print("frames", len(frames), "chat", [G.__chat[i + 1] for i in range(len(G.__chat))])


if __name__ == "__main__":
    main()
