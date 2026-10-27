# Branding

The addon icon is the game icon `inv_cosmicdragonmount` (file ID 6841475,
https://www.wowhead.com/icon=6841475/inv-cosmicdragonmount). The addon ships it as its own TGA
(`SmoothExperienceBar/Media/Icon.tga`, built by `tools/make_media.py` from the 64px PNG here) because the file
ID does not exist on every supported client and Forever does not load game files by path.

- `smooth-experience-bar-64.png` - the game's original 64x64 BLP, converted losslessly
  (https://wago.tools/api/casc/6841475). 64x64 is the largest size the game has.
- `smooth-experience-bar-128.png` - upscaled from the 64px original
