"""Render listing screenshots (CurseForge gallery) of the bar over an in-game backdrop.

Usage: python gallery.py <addon dir> <out dir> <backdrop image>
Writes hero.png, turn-in.png, level-up.png, themes.png, effects.png (1600x900), hero.gif, and
default-bar.gif over default-bar-backdrop.png from the backdrop's folder.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render import Session, font  # noqa: E402

ADDON, OUT, BACKDROP = sys.argv[1], sys.argv[2], sys.argv[3]
W, H = 1600, 900
GOLD = (255, 209, 0)
# The bar's own side texts get in the way when several bars are stacked.
NO_SIDE_TEXT = {"showLevelTime": False, "showSessionTime": False, "showXPHour": False, "showQuestRested": False}

# A believable session instead of the few seconds the scenario really lasts: 2h 13m at this level,
# 1h 30m into the session at about 100K XP/hour.
SEED_BEFORE = "__played.level = 7980; __played.total = 1234567"
SEED_AFTER = "SmoothExperienceBarCharDB.startTime = time() - 5400; SmoothExperienceBarCharDB.gainedXP = 146000"

_source = Image.open(BACKDROP).convert("RGB")

# Use Default Experience Bar, over an in-game screenshot of Forever's action bars: where the game's
# experience bar is in it (screen px), the UI scale it was taken at, and the game's segment lines
# over the bar (start + step * i), with a clean one to copy to each, as the game draws them over the
# liquid and under the text.
DEFAULT_BAR_BACKDROP = os.path.join(os.path.dirname(os.path.abspath(BACKDROP)), "default-bar-backdrop.png")
DEFAULT_BAR = {"left": 186, "top": 49, "width": 1420, "height": 13, "ui_scale": 1.15,
               "line_start": 183.6, "line_step": 71.47, "lines": 19, "line_sample": 469}
# A stand-in for the game's experience bar, as in the tests, for the default bar to find.
FAKE_XP_BAR = """
    MainMenuExpBar = nil
    StatusTrackingBarManager = CreateFrame('Frame', nil, UIParent)
    local container = CreateFrame('Frame', nil, StatusTrackingBarManager)
    StatusTrackingBarManager.barContainers = { container }
    local xp = CreateFrame('Frame', nil, container)
    xp.StatusBar = CreateFrame('Frame', nil, xp)
    xp.StatusBar:SetSize(%r, %r)
    xp.ExhaustionTick = CreateFrame('Frame', nil, xp)
    container.bars = { [4] = xp }
"""


def session(settings=None):
    return Session(ADDON, settings, before_login=SEED_BEFORE, after_login=SEED_AFTER)


def backdrop(w, h, brightness=0.85, blur=1.5):
    """The backdrop scaled to cover w x h, softened a little so the bar stands out."""
    scale = max(w / _source.width, h / _source.height)
    im = _source.resize((int(_source.width * scale + 0.5), int(_source.height * scale + 0.5)), Image.LANCZOS)
    left, top = (im.width - w) // 2, (im.height - h) // 2
    im = im.crop((left, top, left + w, top + h)).filter(ImageFilter.GaussianBlur(blur))
    return ImageEnhance.Brightness(im).enhance(brightness)


def label(img, text, x, y, size=26, anchor="ls"):
    draw = ImageDraw.Draw(img)
    f = font(size)
    draw.text((x + 2, y + 2), text, font=f, fill=(0, 0, 0), anchor=anchor, stroke_width=2, stroke_fill=(0, 0, 0))
    draw.text((x, y), text, font=f, fill=GOLD, anchor=anchor, stroke_width=1, stroke_fill=(0, 0, 0))


def snapshot(t, settings=None, k=2.0, ox=200, oy=400, bg=None):
    s = session(settings)
    s.run_until(t)
    return s.render(bg or backdrop(W, H), ox, oy, k)


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path, optimize=True)
    print("wrote", path, img.size)


def default_bar_gif(name, start=0.8, end=9.6, fps=20):
    """The liquid inside the game's experience bar, playing kills, a turn-in and a level-up."""
    b = DEFAULT_BAR
    shot = Image.open(DEFAULT_BAR_BACKDROP).convert("RGB")
    line = np.asarray(shot)[b["top"]:b["top"] + b["height"], b["line_sample"]].copy()
    lines = [round(b["line_start"] + b["line_step"] * i) for i in range(1, b["lines"] + 1)]
    # The screenshot's own bar emptied, so the rounded ends show dark.
    base = shot.copy()
    ImageDraw.Draw(base).rectangle([b["left"], b["top"], b["left"] + b["width"] - 1, b["top"] + b["height"] - 1],
                                   fill=(10, 8, 7))
    k = b["ui_scale"]
    s = Session(ADDON, {"showBar": False, "skinDefaultBar": True},
                before_login=SEED_BEFORE + FAKE_XP_BAR % (b["width"] / k, b["height"] / k),
                after_login=SEED_AFTER, frame="SmoothExperienceBarDefaultFrame")

    def segment_lines(img):
        px = np.asarray(img).copy()
        for x in lines:
            px[b["top"]:b["top"] + b["height"], x] = line
        return Image.fromarray(px)

    frames = []
    s.run_until(start)
    while s.t < end:
        s.run_until(s.t + 1 / fps)
        frames.append(s.render(base, b["left"], b["top"], k, under_text=segment_lines))
    # One palette for every frame and no dithering: the art stays still, so only the bar changes
    # between frames and the file stays small.
    sample = Image.new("RGB", (base.width, base.height * 6))
    for i, f in enumerate(np.linspace(0, len(frames) - 1, 6).astype(int)):
        sample.paste(frames[f], (0, i * base.height))
    palette = sample.quantize(colors=255, method=Image.MEDIANCUT)
    frames = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    path = os.path.join(OUT, name)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0, optimize=True)
    print("wrote", path, f"{len(frames)} frames, {os.path.getsize(path) // 1024} KB")


def main():
    os.makedirs(OUT, exist_ok=True)

    default_bar_gif("default-bar.gif")

    # One bar, mid quest turn-in: motes streaming and the liquid surging.
    save(snapshot(4.2), "hero.png")

    # The turn-in as three steps.
    img = backdrop(W, H)
    steps = [(3.9, "Completed quest XP waits in orange"), (4.3, "Turn it in and the liquid takes it"),
             (5.5, "All of it banked")]
    for i, (t, text) in enumerate(steps):
        oy = 170 + i * 270
        s = session()
        s.run_until(t)
        img = s.render(img, 200, oy, 2.0)
        label(img, text, 200, oy - 62)
    save(img, "turn-in.png")

    save(snapshot(8.55), "level-up.png")

    # Colour and smart themes in a grid.
    themes = [("luxthos", "Luxthos"), ("class", "Class Color"), ("faction", "Faction"), ("quality", "Item Quality"),
              ("prismatic", "Prismatic"), ("arcane", "Arcane"), ("fel", "Fel"), ("holy", "Holy"),
              ("blood", "Blood"), ("tidal", "Tidal"), ("zangarmarsh", "Zangarmarsh"), ("netherstorm", "Netherstorm"),
              ("hellfire", "Hellfire"), ("nagrand", "Nagrand")]
    img = backdrop(W, H, brightness=0.7)
    for i, (key, name) in enumerate(themes):
        col, row = i % 2, i // 2
        ox, oy = 95 + col * 760, 105 + row * 112
        s = session(dict(NO_SIDE_TEXT, theme=key))
        s.run_until(2.6)
        img = s.render(img, ox, oy, 1.1)
        label(img, name, ox, oy - 12, size=22)
    save(img, "themes.png")

    # Effect themes, each caught as its particles fly.
    effects = [("fire", "Fire"), ("frost", "Frost"), ("honey", "Honey"), ("lava", "Lava"),
               ("cosmic", "Cosmic"), ("nature", "Nature"), ("void", "Void")]
    img = backdrop(W, H, brightness=0.7)
    for i, (key, name) in enumerate(effects):
        ox, oy = 320, 92 + i * 118
        s = session(dict(NO_SIDE_TEXT, theme=key))
        s.run_until(4.3)
        img = s.render(img, ox, oy, 1.6)
        label(img, name, ox, oy - 14, size=24)
    save(img, "effects.png")

    # Animated: kills, the turn-in and the level-up.
    gw, gh, k = 1000, 260, 1.4
    bg = backdrop(gw, gh)
    s = session()
    s.run_until(0.8)
    frames = []
    while s.t < 9.6:
        s.run_until(s.t + 1 / 25)
        frames.append(s.render(bg, (gw - 600 * k) / 2, 105, k).quantize(colors=255, method=Image.MEDIANCUT))
    path = os.path.join(OUT, "hero.gif")
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=40, loop=0, optimize=True)
    print("wrote", path, f"{len(frames)} frames, {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main()
