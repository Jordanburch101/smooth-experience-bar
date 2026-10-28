# Changelog

Player-facing notes for each release. The release workflow copies the
section for the tag's version to GitHub and CurseForge, and stops if there
is none. Write for players: what they can now do or see, and what was
broken and now works. Leave out internal changes. Sections are
`### New` and `### Fixed`; skip one that would be empty.

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
