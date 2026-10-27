# Branding

The addon icon is the game icon `inv_cosmicdragonmount` (file ID 6841475,
https://www.wowhead.com/icon=6841475/inv-cosmicdragonmount).

- `icon-original-64.png` - the game's 64x64 BLP converted losslessly, border included
  (https://wago.tools/api/casc/6841475). 64x64 is the largest size the game has. `tools/make_media.py`
  builds the in-game `SmoothExperienceBar/Media/Icon.tga` from it; the addon ships its own TGA because the
  file ID does not exist on every supported client and Forever does not load game files by path.
- `smooth-experience-bar-56.png` - the original with the 4 px game border cropped off, lossless. Use this
  (or the upscales) for CurseForge and other listings.
- `smooth-experience-bar-64.png`, `-128.png`, `-256.png` - upscaled from the 56px crop

## Gallery

`gallery/` holds listing screenshots (1600x900) and `hero.gif`, rendered from the real addon code by
`tools/harness/gallery.py` over `gallery-backdrop.jpg` (a crop of an in-game screenshot). Text uses the game
font; the script looks for a copy of `frizqt__.ttf` (DialogueUI ships one) or `SEB_FONT`, else falls back to
Arial. Session numbers are seeded so they look like a real play session.

```
tools/venv/Scripts/python tools/harness/gallery.py SmoothExperienceBar branding/gallery branding/gallery-backdrop.jpg
```
