# Smooth Experience Bar

Lightweight World of Warcraft experience bar (TBC Anniversary, Interface 20506). Layout follows the
Luxthos Experience Bar WeakAura; the fill is an animated liquid that reacts to XP gains, quest turn-ins and
level-ups.

## Layout

- `SmoothExperienceBar/` - the addon (junctioned into `_anniversary_\Interface\AddOns`)
  - `Themes.lua` - theme registry and the default theme
  - `Liquid.lua` - liquid front simulation, swirl, bubbles and motes
  - `SmoothExperienceBar.lua` - data, events, text, fill animation, slash commands
  - `Options.lua` - settings page (Options > AddOns > Smooth Experience Bar)
  - `Media/` - generated textures
- `tools/make_media.py` - regenerates `Media/*.tga`
- `tools/harness/` - WoW API mock for running the addon outside the game

## In game

`/seb` opens the settings page. Other commands:

```
/seb unlock | lock | reset
/seb session
/seb test [xp] | level | multi | quest | turnin | rested | off
```

## Themes

25 themes ship in `Themes.lua`:

- Default: Luxthos
- Smart: Class Color, Faction, Item Quality (changes colour as the bar fills), Prismatic (cycles hue)
- Colour: Arcane, Fel, Holy, Blood, Ember, Tidal, Plague, Midnight, Sunset
- Outland zones: Zangarmarsh, Netherstorm, Hellfire, Nagrand
- Effects: Fire, Frost, Honey, Lava, Cosmic, Nature, Void. These also change physics, swirl texture and
  particles.

Register a theme in `Themes.lua`. Only the fields that differ from the default theme are needed; it then
appears in the Theme dropdown. The comment at the top of `Themes.lua` lists everything a theme can set.

```lua
Themes.Register("toxic", {
    name = "Toxic",
    fillA = { 0.10, 0.60, 0.10 },
    fillB = { 0.55, 1.00, 0.20 },
    physics = { damping = 6, ambient = 0.4 },              -- thicker liquid
    burst = { texture = "Ember", buoyancy = 40 },          -- rising sparks on XP gains
    ambient = { { area = "surface", rate = 2, texture = "Glow", size = { 6, 10 }, vy = { 8, 16 } } },
})
```

## Tools

```
python -m venv tools/venv
tools/venv/Scripts/python -m pip install lupa numpy pillow

python tools/make_media.py SmoothExperienceBar/Media
tools/venv/Scripts/python tools/harness/run.py SmoothExperienceBar preview      # preview.gif + sheet.png
tools/venv/Scripts/python tools/harness/run.py SmoothExperienceBar preview theme=fel width=800 height=48
tools/venv/Scripts/python tools/harness/slash_test.py SmoothExperienceBar       # commands, settings, themes
tools/venv/Scripts/python tools/harness/probe.py SmoothExperienceBar cosmic     # live particle counts
```
