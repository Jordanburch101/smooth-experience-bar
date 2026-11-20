# Smooth Experience Bar

World of Warcraft addon: a lightweight standalone take on the Luxthos Experience Bar WeakAura, with a liquid
fill and themes. One `.toc` for WoW Forever, Classic Era and TBC Anniversary (`## Interface: 16001, 11509, 20506`).
The README covers the layout and tools; this file holds the rules.

## Rules

- **Forever:** game files by path often fail to load there. Use `SetColorTexture` for solid fills and the
  addon's own TGAs in `SmoothExperienceBar/Media/` (made by `tools/make_media.py`), never `Interface\...`
  game paths. Take fonts from game font objects. Forever has the modern APIs (`C_QuestLog`); keep a classic
  fallback for Era and Anniversary. `tools/harness/slash_test.py` checks both.
- **Tests:** run `tools/venv/Scripts/python tools/harness/slash_test.py SmoothExperienceBar` before every
  commit; it exits 1 on any failed check. The mock (`tools/harness/wowmock.lua`) should be as strict as the
  client: when the client rejects something the mock accepted, make the mock reject it too.
- **Visual changes:** render a preview (`tools/harness/run.py`) and look at it. The Gallery workflow
  rebuilds `branding/gallery/` (`tools/harness/gallery.py`: every image, including `hero.webp` and
  `default-bar.webp`) on every push to `main` and commits the images, so don't commit gallery images by hand.
  Pull after pushing: the workflow's commit lands on `main`.
- **Commits:** stage the files you changed by name, never `git add -A`; the folder can hold files that are
  not part of the repo. Commit messages are plain and professional.
- **Changelog:** add player-facing notes to `CHANGELOG.md` under the next version as features land
  (`### New`, `### Fixed`, no internal changes). The same notes are the in-game What's New window
  (`WhatsNew.lua`, as Smooth Animated Bars'): every player sees them once after updating, so each note must read
  well on its own. Start a note with a bold title (`- **Reputation Bar**: ...`) to show the title on a line of its
  own there.
- **Store page:** `branding/curseforge.md` is the CurseForge description. Update it (and the README) as features
  land, in the same plain style; its images are the gallery's, linked from `main`.

## Release

1. Add the version's section to `CHANGELOG.md`: `## X.Y.Z` with `### New` and `### Fixed`, written for
   players. `bash scripts/changelog.sh X.Y.Z` prints what the release will use. `scripts/package.ps1` writes
   `WhatsNewData.lua` (the in-game notes, not committed) from it with `tools/whatsnew_data.py`, prints
   "WhatsNewData.lua: N versions, newest X.Y.Z" (the newest must be this version), and fails if the version has no
   section.
2. Run the tests, commit and push `main`.
3. Push an annotated tag: `git tag -a vX.Y.Z -m "Smooth Experience Bar X.Y.Z"`, then `git push origin vX.Y.Z`.
   The version comes from the tag (the toc says `@project-version@`); tags containing `beta` or `alpha`
   become pre-releases.
4. The Release workflow fails at once if the changelog section is missing, then tests, builds, makes the
   GitHub release with the zip and notes, and uploads to CurseForge (project 1768424). Watch it to the end
   (`gh run watch <id> --exit-status`): the GitHub release can succeed while the upload fails.
5. If the store page changed, paste `branding/curseforge.md` into the CurseForge description once the Gallery
   workflow has committed any new images it shows.
6. If only the CurseForge upload failed, fix the cause on `main`, then run
   `gh workflow run curseforge-check.yml -f tag=vX.Y.Z` to upload that release again.
