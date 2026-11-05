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

`gallery/` holds listing screenshots (1600x900), `hero.gif` and `default-bar.gif`, rendered from the real
addon code by `tools/harness/gallery.py`. The screenshots and `hero.gif` are drawn over
`gallery-backdrop.jpg` (a crop of an in-game screenshot). `default-bar.gif` shows Use Default Experience Bar
over `default-bar-backdrop.png`, an in-game screenshot of WoW Forever's action bars: the script empties the
experience bar in it and draws the liquid there, with the game's segment lines over it and the text on top.
Its position in the screenshot is `DEFAULT_BAR` in the script; measure it again if the screenshot changes.

Text uses the game font; the script looks for a copy of `frizqt__.ttf` (DialogueUI ships one) or
`SEB_FONT`, else falls back to Arial. Session numbers are seeded so they look like a real play session.

The Gallery workflow (`.github/workflows/gallery.yml`) rebuilds all of it on every push to `main`, with the
game font fetched from wago.tools, and commits the images that changed. To try it locally:

```
tools/venv/Scripts/python tools/harness/gallery.py SmoothExperienceBar branding/gallery branding/gallery-backdrop.jpg
```
