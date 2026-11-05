# Changelog

Player-facing notes for each release. The release workflow copies the
section for the tag's version to GitHub and CurseForge, and stops if there
is none. Write for players: what they can now do or see, and what was
broken and now works. Leave out internal changes. Sections are
`### New` and `### Fixed`; skip one that would be empty.

## 1.2.1

### Fixed
- WoW Forever: Copy Settings From now lists characters by first and last
  name and ruleset (Normal, PVP, RP, RP-PVP or Hardcore), such as
  "Hollywood Hootsman - Normal", instead of a cut-off server name.
  Characters that share a first name now get their own settings, each
  starting from the settings they had before.

## 1.2.0

### New
- Use Default Experience Bar: show the liquid and its effects inside the
  game's own experience bar too, with the time this level and your XP on
  it. Hover it for the rest: XP remaining, completed and rested XP, session
  time, time to level and XP/hour. It keeps the game's frame and moves and
  resizes with it, Edit Mode included. Turn it on in the settings or with
  `/seb skin`.
- Show Separate Bar: untick it to keep only the default experience bar's
  liquid, or keep both.
- Setup wizard: pick where the bar goes, its theme, how lively it is and
  what text it shows, each with live previews. It opens once on your
  account: for new players, and after this update for everyone else,
  starting from your current settings. Ask Me Later brings it back at the
  next login, Skip changes nothing. Open it any time with `/seb setup` or
  from the settings.

## 1.1.5

### Fixed
- WoW Forever: no more "SmoothExperienceBar has been blocked from an
  action only available to the Blizzard UI" popup after opening the
  addon's settings and then another page, such as Social.

## 1.1.4

### Fixed
- WoW Forever: the bar now recognises level 60 as max level, so it hides
  there (or shows a full bar with time played, if you keep it at max
  level).
- WoW Forever: Hide Default Experience Bar now hides the game's tracking
  bars (experience and reputation), and they stay hidden after level-ups
  and Edit Mode. Turning the option off brings back the bars the game
  wants shown.
- WoW Forever: no more errors when the game hides XP from addons during
  combat. The bar catches up as soon as the XP can be read again, and
  XP/hour counts what you earned in the meantime, level-ups included.
- WoW Forever: hidden quests no longer add to the completed quest XP.

## 1.1.3

### Fixed
- After copying another character's settings, the settings page now shows
  the copied values straight away instead of the old ones.

## 1.1.2

### New
- Settings are now saved per character, so each character can have its
  own theme, position, size and effects. Your current settings carry over
  to every character the first time it logs in.
- Copy another character's settings from the new Profile section of the
  settings page.
- Hover over a theme in the theme picker to see it on the bar straight
  away. Close the menu without picking one and the bar goes back to your
  theme.

## 1.1.1

### New
- The front of the liquid leans forward while it pours fast, then rocks
  back and settles.
- Fel, Frost, Plague and Void give off wisps of vapour from the front of
  the liquid.

### Fixed
- Pale themes such as the default and Holy no longer wash out to white
  during big XP gains, so the lightning stays visible.

## 1.1.0

### New
- The liquid has depth: slow dark pockets and bright wisps drift behind
  the magic veins, like a swirling potion.
- Light glows from inside the liquid, pulsing gently and brightening when
  you gain XP.
- Bubbles are smaller and glassier, take on the colour of the magic, and
  drift and circle along with the swirl.
- Lightning flickers in the clouds inside the liquid: faint flashes at
  rest that build into a storm with big or rapid XP gains. Turn it off
  with the new Lightning setting.
- The magic inside the liquid mixes related colours that slowly drift
  and trade places.
- New Glass setting (off by default): the bar becomes a glass tube that
  takes on the liquid's colour and lights up with its glow, XP gains,
  lightning and level-ups.
- New Rounded Liquid setting (off by default): rounds the bar's ends into
  a capsule and shades the liquid so it looks round.

## 1.0.1

### New
- The front of the liquid is smoother, with a soft glowing edge instead of
  a hard stepped line, and the magic inside reaches right up to it.
- The liquid pours more naturally: it eases into motion instead of jumping
  to full speed, and keeps flowing when several kills land in a row
  instead of pausing on each one.
- The liquid froths where it meets completed quest XP or rested XP, and
  the froth builds up as it flows in.

### Fixed
- A dark gap no longer flickers in front of the liquid while it flows into
  completed quest XP or rested XP after a big gain.
- The end of the rested XP no longer twitches backwards before the liquid
  starts to flow.
- The magic inside the liquid no longer stops short of the front while it
  pours, and the front keeps its curve and bright edge during big gains.

## 1.0.0

### New
- A lightweight standalone take on the Luxthos Experience Bar WeakAura:
  level, XP, completed quest XP, rested XP, time this level, session time,
  XP per hour and time to level.
- A settings page (`/seb`, right-click the bar, or Options > AddOns): move,
  resize and scale the bar, toggle each line of text, hide the default
  experience bar, and switch each visual effect on or off.
- A liquid fill that ripples, splashes and absorbs completed quest XP as you
  turn quests in.
- 25 themes: the original look, Class Color, Faction, Item Quality,
  Prismatic, colour themes, Outland zones and effect themes with their own
  particles.
- Runs on WoW Classic Era, TBC Anniversary and WoW Forever.
