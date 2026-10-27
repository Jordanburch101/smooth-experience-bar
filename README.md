# Smooth Experience Bar

Lightweight World of Warcraft experience bar (TBC Anniversary, Interface 20506). Layout and colours follow the
Luxthos Experience Bar WeakAura; the fill is an animated liquid that reacts to XP gains, quest turn-ins and
level-ups.

## Layout

- `SmoothExperienceBar/` - the addon (junctioned into `_anniversary_\Interface\AddOns`)
  - `SmoothExperienceBar.lua` - data, events, text, fill animation, slash commands
  - `Liquid.lua` - liquid front simulation, swirl, bubbles and motes
  - `Media/` - generated textures
- `tools/make_media.py` - regenerates `Media/*.tga`
- `tools/harness/` - WoW API mock for running the addon outside the game

## In game

```
/seb unlock | lock | reset
/seb session
/seb test [xp] | level | multi | quest | turnin | rested | off
```

## Tools

```
python -m venv tools/venv
tools/venv/Scripts/python -m pip install lupa numpy pillow

python tools/make_media.py SmoothExperienceBar/Media
tools/venv/Scripts/python tools/harness/run.py SmoothExperienceBar preview      # preview.gif + sheet.png
tools/venv/Scripts/python tools/harness/slash_test.py SmoothExperienceBar
```
