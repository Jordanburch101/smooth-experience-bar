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

Register a theme in `Themes.lua`. Only the fields that differ from the default theme are needed; it then
appears in the Theme dropdown.

```lua
Themes.Register("fel", {
    name = "Fel",
    fillA = { 0.10, 0.60, 0.10 },
    fillB = { 0.55, 1.00, 0.20 },
})
```

## Tools

```
python -m venv tools/venv
tools/venv/Scripts/python -m pip install lupa numpy pillow

python tools/make_media.py SmoothExperienceBar/Media
tools/venv/Scripts/python tools/harness/run.py SmoothExperienceBar preview      # preview.gif + sheet.png
tools/venv/Scripts/python tools/harness/slash_test.py SmoothExperienceBar       # commands, settings, themes
```
