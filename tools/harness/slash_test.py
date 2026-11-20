"""Tests: slash commands, every setting, the settings page, themes, mouse and resize, and the
Forever-specific paths, against the WoW mock.

Usage: python slash_test.py <addon dir>
Prints each step and exits 1 if any check fails (a Lua error also fails with a traceback).
"""
import os
import sys

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # some builds of lupa ship without LuaJIT; WoW's Lua is 5.1 either way
    from lupa.lua51 import LuaRuntime

ADDON = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
failures = []


def check(ok, what):
    print(f"  {'ok  ' if ok else 'FAIL'} {what}")
    if not ok:
        failures.append(what)


lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
G = lua.globals()
ns = G.__loadAddon(ADDON.replace("\\", "/"), "SmoothExperienceBar")
lua.execute("__fire('ADDON_LOADED', 'SmoothExperienceBar'); __fire('PLAYER_ENTERING_WORLD', true, false)")
G.ns_defaults = ns.Core.Defaults()

state = lua.eval("""function()
    local t = {}
    for _, r in ipairs(__regions) do
        local bar = SmoothExperienceBarFrame
        if r.kind == "FontString" and (r.parent == bar or r.parent.parent == bar) and r.text and r.text ~= ""
            and r.shown then
            t[#t + 1] = r.text
        end
    end
    return (SmoothExperienceBarFrame.shown and "" or "[hidden] ") .. table.concat(t, " | ")
end""")


def run(seconds=4):
    for _ in range(int(seconds * 60)):
        G.__step(1 / 60)


def step(label, code=None, seconds=4):
    if code:
        lua.execute(code)
    run(seconds)
    text = state()
    print(f"{label:28} -> {text}")
    return text


def slash(cmd, seconds=4):
    return step(f"/seb {cmd}", f"SlashCmdList.SMOOTHEXPERIENCEBAR({cmd!r})", seconds)


print("== /played on login")
try:
    lua.execute("C_Timer.After(0.5, RequestTimePlayed)")
    rejected = False
except Exception:
    rejected = True
check(rejected, "mock rejects a bare C function as a timer callback, like the client")
run(6)
check(bool(G.ChatFrame1.events.TIME_PLAYED_MSG), "chat frames get TIME_PLAYED_MSG back")
check("Time this level: 4m" in state(), "played time shown")

print("== setup wizard")
# A new player: the wizard opens shortly after the first login, and its previews play XP gains.
wiz = lambda: ns.Wizard.State()
st = wiz()
check(st.frame is not None and st.frame.shown and st.page == "welcome", "wizard opens on a new player's first login")
check(st.ui.welcomeSkip.text == "Skip, use the defaults", "wizard: a new player's skip keeps the defaults")
check(lua.eval("UISpecialFrames[1]") == "SmoothExperienceBarSetup", "wizard: Escape closes it like the game's windows")
bg_x = lambda f: f.Bg.points.TOPLEFT
check(st.frame.portraitHidden and st.frame.buttonBarHidden and not st.frame.Inset.shown
      and st.frame.title == "Smooth Experience Bar Setup" and (bg_x(st.frame).x, bg_x(st.frame).y) == (6, -21),
      "wizard: the game's window as Road to Sixty uses it, background from under the title bar")
wui = st.ui
cards = wui.cards


def click(button, seconds=0.1):
    button.scripts.OnClick(button, "LeftButton")
    run(seconds)


click(wui.start)
check(wiz().page == "place" and wui.step.text == "Step 1 of 5", "wizard: Set it up goes to where the bar goes")
scene = wui.scene
check(scene.bar.frame.shown and not scene.skin.frame.shown, "wizard: separate bar picked to start with, previewed")
click(cards.place.both)
check(scene.bar.frame.shown and scene.skin.frame.shown and cards.place.both.radio.checked
      and not cards.place.separate.radio.checked, "wizard: picking Both previews both bars")
click(wui.next)
check(wiz().page == "theme", "wizard: then the theme")
click(cards.theme.fel)
check(cards.theme.fel.radio.checked, "wizard: theme picked")
click(wui.next)
click(cards.effects.calm)
check(wiz().page == "effects" and cards.effects.calm.radio.checked, "wizard: effects picked")
click(wui.next)
# The reputation bar: off to start with, as in the settings; its previews fill up standing after
# standing, one in the standing colours and one in the theme picked.
rep_page = wiz().pages.rep
check(wiz().page == "rep" and cards.rep.off.radio.checked, "wizard: then the reputation bar, off to start with")
rep_previews = rep_page.previews
check(rep_previews.standing.theme.key == "standing" and rep_previews.theme.theme.key == "fel",
      "wizard: reputation previews in the standing colours and in the theme picked")
first = rep_previews.standing.demo.reaction
run(12)  # four gains to fill it (one every 2.2 s), and another five before the standing after
check(rep_previews.standing.demo.reaction != first and rep_previews.standing.pctText.text != "Neutral"
      and rep_previews.standing.levelText.text == "Stormwind",
      f"wizard: the reputation preview fills into the next standing ({rep_previews.standing.pctText.text})")
click(cards.rep.theme)
check(cards.rep.theme.radio.checked and not cards.rep.off.radio.checked, "wizard: reputation bar picked")
click(wui.next)
click(cards.text.none)
check(wiz().page == "text" and cards.text.none.radio.checked, "wizard: text picked")
click(wui.next)
summary = wiz().pages.done.summary.text
check(wiz().page == "done" and "Bar: Both" in summary and "Theme: Fel" in summary and "Effects: Calm" in summary
      and "Text: Just the bar" in summary and "Reputation: Match your theme" in summary,
      f"wizard: summary of the picks ({summary})")
check(wui.next.text == "Finish", "wizard: last step finishes")
click(wui.next, 1)
mine = G.SmoothExperienceBarDB.profiles["Testchar - Mockrealm"]
check(not st.frame.shown and mine.setupPending is None, "wizard: Finish closes it for good")
check(mine.bars == "both" and mine.theme == "fel" and not mine.waves and not mine.lightning
      and not mine.showLevelTime and not mine.showQuestRested and mine.repBar and mine.repTheme == "fel",
      "wizard: the picks are applied")
check(G.__settings.theme.GetValue(G.__settings.theme) == "fel", "wizard: applied through the settings controls")
check("204,931" in step("wizard closed", None, 1), "wizard: its XP previews stop and the bar is back to live XP")

lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('setup')")
run(0.2)
check(st.frame.shown and wiz().choice.place == "both" and wiz().choice.effects == "calm" and wiz().choice.text == "none"
      and wiz().choice.rep == "theme",
      "/seb setup opens it again, starting from the current settings")
lua.execute("__settings.defaultLeft:SetValue('none'); __settings.defaultLabels:SetValue(false)")
click(wui.start)
click(cards.place.default)
preview = (scene.skin.levelText.text, scene.skin.xpText.text, scene.skin.pctText.text)
check(preview[0].startswith("Time this level: ") and " / " in preview[1] and preview[2] == "",
      f"wizard: its default-bar preview keeps the usual text, whatever the settings say ({preview})")
lua.execute("__settings.defaultLeft:SetValue('levelTime'); __settings.defaultLabels:SetValue(true)")
click(wui.next)
click(wui.next)
click(wui.next)
click(wui.next)
check(wiz().page == "done" and "Text:" not in wiz().pages.done.summary.text,
      "wizard: no text step when only the game's bar is used")
click(wui.back)
check(wui.step.text == "Step 4 of 4", f"wizard: step count follows ({wui.step.text})")
click(wui.later, 1)
check(not st.frame.shown and mine.setupPending and mine.setupSnoozed, "wizard: Ask Me Later closes it until the next login")
lua.execute("__fire('PLAYER_ENTERING_WORLD', false, true)")
run(3)
check(not st.frame.shown, "wizard: not again on a reload")
lua.execute("__fire('PLAYER_ENTERING_WORLD', true, false)")
run(3)
check(st.frame.shown and wiz().page == "welcome", "wizard: back at the next login")
click(st.frame.CloseButton, 1)
check(not st.frame.shown and mine.setupPending, "wizard: the window's close button means ask me later too")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('setup')")
run(0.2)
click(wui.welcomeSkip, 1)
check(not st.frame.shown and mine.setupPending is None and mine.setupSnoozed is None, "wizard: Skip ends it")
check(G.SmoothExperienceBarDB.setupOffered, "wizard: offered once for the whole account")
lua.execute("__fire('PLAYER_ENTERING_WORLD', true, false)")
run(3)
check(not st.frame.shown, "wizard: skipped, it stays closed at the next login")
# Back to the defaults for the tests below.
lua.execute("""
    local d = ns_defaults
    for _, k in ipairs({ "bars", "theme", "waves", "swirl", "bubbles", "sparkles", "ambient",
                         "lightning", "restedGlow", "glass", "rounding", "flash", "showLevelTime", "showSessionTime",
                         "showXPHour", "showQuestRested", "repBar", "repTheme" }) do
        __settings[k]:SetValue(d[k])
    end
""")
check("Time this level" in step("defaults again", None, 1), "wizard: settings back to the defaults")

print("== settings page")
layout = G.__settingsRows()
items = [layout[i + 1] for i in range(len(layout))]
for item in items:
    print(f"  {item.kind:9} {item.key or item.name}")
category = G.__settingsCategory
check(category.name == "Smooth Experience Bar" and category.frame is not None, "canvas category registered")
check(any(i.kind == "dropdown" and i.key == "theme" for i in items), "theme dropdown")
check(sum(1 for i in items if i.kind == "button") == 11, "eleven buttons")
# Sections and rows for reputation show only while a reputation bar is used.
row_shown = lambda kind, name: next(i.frame.shown for i in G.__settingsRows().values()
                                    if i.kind == kind and (i.key or i.name) == name)
rep_rows = (("dropdown", "repTheme"), ("header", "Reputation"), ("dropdown", "repLeft"),
            ("button", "Preview Reputation Gain"), ("checkbox", "repTooltip"))
check(not any(row_shown(*r) for r in rep_rows) and row_shown("dropdown", "separateTracks"),
      "settings: no reputation rows while no reputation bar is used")
lua.execute("__settings.separateTracks:SetValue('rep')")
check(all(row_shown(*r) for r in rep_rows),
      "settings: separate bar tracking reputation shows the reputation theme, text, tooltip and previews")
lua.execute("__settings.separateTracks:SetValue('xp'); __settings.repBar:SetValue(true)")
check(all(row_shown(*r) for r in rep_rows), "settings: the game's reputation bar shows them all")
lua.execute("__settings.repBar:SetValue(false); __settings.bars:SetValue('default')")
check(not row_shown("dropdown", "separateTracks") and not row_shown("header", "Separate Bar"),
      "settings: Separate Bar Tracks goes with the separate bar")
lua.execute("__settings.bars:SetValue('separate')")
setting_count = lua.eval("function() local n = 0 for _ in pairs(__settings) do n = n + 1 end return n end")()
size_sliders = [i for i in items if i.kind == "dropdown" and i.frame.SizeSlider]
covered = (sum(1 for i in items if i.kind in ("checkbox", "slider", "dropdown"))
           + 2 * sum(1 for i in items if i.kind == "checkboxslider") + len(size_sliders))
check(covered == setting_count == 64, f"a control for every setting ({covered} of {setting_count})")
# Each bar has its own section, shown only while that bar is used.
shown_rows = lambda: {i.key or i.name for i in G.__settingsRows().values() if i.frame.shown}
bars_dd = next(i for i in items if i.kind == "dropdown" and i.key == "bars")
bars_opts = bars_dd.getOptions()
check([bars_opts[i + 1].label for i in range(len(bars_opts))] == ["Separate Bar", "Default Experience Bar", "Both"],
      "Experience Bar: the setup wizard's three choices")
rows = shown_rows()
check({"Separate Bar", "width", "showXPText", "showXPHour", "rounding", "segments", "hideBlizzardBar", "Reset Position & Size"} <= rows
      and not rows & {"Default Experience Bar", "defaultLeft", "defaultCentre", "defaultRight", "defaultLabels", "defaultTooltip"},
      "separate bar: its section shown, the default bar's not")
lua.execute("__settings.bars:SetValue('default')")
rows = shown_rows()
check({"Default Experience Bar", "defaultLeft", "defaultCentre", "defaultRight", "defaultLabels", "defaultTooltip", "defaultQuestBar",
       "defaultRestedBar", "theme", "speed"} <= rows
      and not rows & {"Separate Bar", "width", "locked", "showXPText", "showXPHour", "rounding", "segments", "hideBlizzardBar", "questBar",
                     "restedBar"},
      "default bar: its section shown, the separate bar's not")
lua.execute("__settings.bars:SetValue('both')")
rows = shown_rows()
check({"width", "defaultCentre"} <= rows and "hideBlizzardBar" not in rows,
      "both: both sections, and no Hide Default Experience Bar while the liquid is in it")
tops = [i.frame.points.TOPLEFT.y for i in G.__settingsRows().values() if i.frame.shown]
check(all(a > b for a, b in zip(tops, tops[1:])), "shown rows laid out one under the other, no gaps")
lua.execute("__settings.bars:SetValue('separate')")
inside = lua.eval("""function(page)
    for _, row in ipairs(__settingsRows()) do
        local f = row.frame
        while f and f ~= page do f = f.parent end
        if not f then return false end
    end
    return true
end""")
check(inside(category.frame), "every row is a frame inside our page")
check(not G.__sharedListTainted, "nothing added to the game's shared settings list (Forever: Social blocked in our name)")
check(not category.frame.shown, "page built hidden")

print("== slash commands")
lua.execute("__openedCategory = nil")
slash("")
check(G.__openedCategory == "Smooth Experience Bar", "/seb opens settings")
check(lua.eval("__settingsCategory.frame.shown and __settingsCategory.frame.parent == __settingsCanvas"),
      "page shown in the settings panel")
check(not G.__builtInOpenPanel, "no frame made inside the open settings panel")
lua.execute("__closeSettings()")
slash("unlock", 0.1)
lua.execute("__openedCategory = nil")
slash("", 0.1)
locked_row = next(i for i in G.__settingsRows().values() if i.key == "locked")
check(locked_row.frame.value is False, "rows read their settings again when the page opens")
lua.execute("__closeSettings()")
slash("lock", 0.1)
slash("help")
check("Level 57 | 229,850" in slash("test"), "test: 8% gain")
check("249,850" in slash("test 20000"), "test 20000")
check("(85.2%)" in slash("test quest"), "test quest: completed quest XP shown")
check("85.2%" in slash("test turnin") and "(85.2%)" not in state(), "test turnin: quest XP absorbed")
slash("test rested")
check("Level 58" in slash("test level"), "test level")
check("Level 60" in slash("test multi"), "test multi: several levels")
check("Level 57 | 204,931 / 311,490" in slash("test off"), "test off: back to live data")
for cmd in ["unlock", "lock", "reset", "session"]:
    slash(cmd)

print("== every setting toggled off and back on")
for key in ["showLevelText", "showXPText", "showPctText", "showLevelTime", "showSessionTime", "showXPHour", "showQuestRested", "waves", "swirl", "bubbles",
            "sparkles", "ambient", "lightning", "restedGlow", "flash", "glass", "rounding", "segments", "fontOutline", "locked", "hideBlizzardBar", "defaultLabels", "defaultTooltip", "questBar", "restedBar", "defaultQuestBar",
            "defaultRestedBar", "resetOnReload", "showMaxLevel", "fadeIdle", "trackedQuestsOnly"]:
    default = G.__settings[key].GetValue(G.__settings[key])
    lua.execute(f"__settings[{key!r}]:SetValue({str(not default).lower()})")
    step(f"{key}={not default}", "SlashCmdList.SMOOTHEXPERIENCEBAR('test')", 1)
    lua.execute(f"__settings[{key!r}]:SetValue({str(default).lower()})")
lua.execute("__settings.showLevelTime:SetValue(false)")
check("Time this level" not in step("showLevelTime off", None, 0.2), "text line can be hidden")
lua.execute("__settings.showLevelTime:SetValue(true)")
lua.execute("__settings.showXPText:SetValue(false)")
xp_off = step("showXPText off", None, 0.2)
check(" / " not in xp_off and xp_off.startswith("Level "), f"XP in the middle of the bar can be hidden ({xp_off})")
xp_off = step("showXPText off, XP gain", "SlashCmdList.SMOOTHEXPERIENCEBAR('test')", 1)
check(" / " not in xp_off and xp_off.startswith("Level "), f"XP stays hidden through an XP gain ({xp_off})")
xp_off = step("showXPText off, level-up", "SlashCmdList.SMOOTHEXPERIENCEBAR('test level')", 2)
check(" / " not in xp_off and xp_off.startswith("Level "), f"XP stays hidden through a level-up ({xp_off})")
step("showXPText off, test off", "SlashCmdList.SMOOTHEXPERIENCEBAR('test off')", 2)
lua.execute("__settings.showXPText:SetValue(true)")
check(" / " in step("showXPText on", None, 0.2), "XP in the middle of the bar back")
lua.execute("__settings.hideBlizzardBar:SetValue(true)")
check(not G.MainMenuExpBar.shown, "default XP bar hidden")
lua.execute("MainMenuExpBar:Show()")
check(not G.MainMenuExpBar.shown, "default XP bar stays hidden when the game shows it")
lua.execute("__settings.hideBlizzardBar:SetValue(false)")
check(G.MainMenuExpBar.shown, "default XP bar restored")
for key, value in [("scale", 1.2), ("speed", 0.5), ("speed", 2)]:
    lua.execute(f"__settings[{key!r}]:SetValue({value})")
    step(f"{key}={value}", "SlashCmdList.SMOOTHEXPERIENCEBAR('test level')", 2)
check(G.SmoothExperienceBarFrame.scale == 1.2, "scale applied")

print("== font, outline and segments")
main_texts = lua.eval("""function()
    local out = {}
    for _, r in ipairs(__regions) do
        if r.kind == "FontString" and r.parent == SmoothExperienceBarFrame then out[#out + 1] = r end
    end
    return out
end""")


def fonts():
    t = main_texts()
    return {(t[i + 1].fontFile, t[i + 1].fontFlags) for i in range(len(t))}


check(fonts() == {(r"Fonts\FRIZQT__.TTF", "OUTLINE")}, f"text starts in the game font with an outline {fonts()}")
font_dd = next(i for i in items if i.kind == "dropdown" and i.key == "font")
opts = font_dd.getOptions()
names = [opts[i + 1].label for i in range(len(opts))]
check(names == ["Friz Quadrata", "Arial Narrow", "Morpheus", "Skurri"], f"font list, one entry per file {names}")
lua.execute("__settings.font:SetValue('QuestTitleFont'); __settings.fontOutline:SetValue(false)")
check(fonts() == {(r"Fonts\MORPHEUS.TTF", "")}, f"font and outline change on the bar {fonts()}")
lua.execute(r"__fontFiles['FONTS\\MORPHEUS.TTF'] = nil; __settings.height:SetValue(31)")
check(fonts() == {(r"Fonts\FRIZQT__.TTF", "")}, f"a font the client cannot load falls back to the game font {fonts()}")
lua.execute(r"""__fontFiles['FONTS\\MORPHEUS.TTF'] = true; __settings.height:SetValue(30)
    __settings.font:SetValue('GameFontNormal'); __settings.fontOutline:SetValue(true)""")
# A text line's (size, y offset), by the frame it is on and its anchor.
font_at = lua.eval("""function(frame, point, relPoint)
    for _, r in ipairs(__regions) do
        if r.kind == "FontString" and (r.parent == frame or r.parent.parent == frame) and r.points[point]
            and r.points[point].relPoint == relPoint then
            return r.fontSize, r.points[point].y
        end
    end
end""")
bar = G.SmoothExperienceBarFrame
text_lines = {"level": ("LEFT", "LEFT"), "xp": ("CENTER", "CENTER"), "pct": ("RIGHT", "RIGHT"),
              "levelTime": ("TOPLEFT", "TOPLEFT"), "session": ("TOPRIGHT", "TOPRIGHT"),
              "xpHour": ("LEFT", "BOTTOMLEFT"), "questRested": ("RIGHT", "BOTTOMRIGHT")}
size_keys = ["levelSize", "xpSize", "pctSize", "levelTimeSize", "sessionTimeSize", "xpHourSize", "questRestedSize"]
line_sizes = lambda: {k: tuple(font_at(bar, *p)) for k, p in text_lines.items()}
before = line_sizes()
check(before == {"level": (16, 0), "xp": (14, 0), "pct": (16, 0), "levelTime": (14, 24), "session": (14, 24),
                 "xpHour": (14, -18), "questRested": (14, -18)},
      f"text sizes at 100% as they were ({before})")
lua.execute("__settings.xpSize:SetValue(150)")
after = line_sizes()
check(after["xp"] == (21, 0) and all(after[k] == before[k] for k in text_lines if k != "xp"),
      f"XP Size: only the XP grows ({after})")
lua.execute("__settings.levelTimeSize:SetValue(200); __settings.xpHourSize:SetValue(150); __settings.levelSize:SetValue(50); "
            "__settings.pctSize:SetValue(75)")
after = line_sizes()
check(after == {"level": (8, 0), "xp": (21, 0), "pct": (12, 0), "levelTime": (28, 38), "session": (14, 24),
                "xpHour": (21, -21.5), "questRested": (14, -18)},
      f"each line its own size; the lines above and below grow away from the bar ({after})")
lua.execute("__settings.height:SetValue(60)")
check(line_sizes()["xp"] == (34, 0), f"text sizes still follow the bar's height ({line_sizes()['xp']})")
lua.execute("__settings.height:SetValue(30)")
for key in size_keys:
    lua.execute(f"__settings.{key}:SetValue(100)")
check(line_sizes() == before, f"text sizes back ({line_sizes()})")
# The separate bar's text rows: each line's checkbox with its size beside it, one row each.
text_rows = {i.key: i.sliderKey for i in items if i.kind == "checkboxslider"}
check(text_rows == {"showLevelText": "levelSize", "showXPText": "xpSize", "showPctText": "pctSize",
                    "showLevelTime": "levelTimeSize", "showSessionTime": "sessionTimeSize", "showXPHour": "xpHourSize",
                    "showQuestRested": "questRestedSize"},
      f"separate bar: each text line and its size on one row ({text_rows})")
text_shown = lua.eval("""function(frame, point, relPoint)
    for _, r in ipairs(__regions) do
        if r.kind == "FontString" and r.parent == frame and r.points[point]
            and r.points[point].relPoint == relPoint then
            return r.shown
        end
    end
end""")
for key, name in [("showLevelText", "level"), ("showPctText", "pct")]:
    lua.execute(f"__settings.{key}:SetValue(false)")
    check(text_shown(bar, *text_lines[name]) is False and text_shown(bar, *text_lines["xp"]),
          f"{key} off hides only that text")
    lua.execute(f"__settings.{key}:SetValue(true)")
    check(text_shown(bar, *text_lines[name]), f"{key} back on shows it")
segment_lines = lua.eval("""function(frame)
    local n, xs = 0, {}
    for _, r in ipairs(__regions) do
        if r.parent == frame and r.kind == "Texture" and r.layer == "ARTWORK" and r.sub == 7 and r.file == "SOLID"
            and r.shown then
            n = n + 1
            xs[#xs + 1] = r.points.TOPLEFT.x
        end
    end
    table.sort(xs)
    return n, xs[1], xs[#xs]
end""")
check(segment_lines(G.SmoothExperienceBarFrame)[0] == 0, "Segmented Bar off by default")
lua.execute("__settings.segments:SetValue(true)")
n, first, last = segment_lines(G.SmoothExperienceBarFrame)
check((n, first, last) == (19, 30, 570), f"Segmented Bar: 19 lines every 5% ({n}, {first}, {last})")
lua.execute("__settings.width:SetValue(800)")
n, first, last = segment_lines(G.SmoothExperienceBarFrame)
check((n, first, last) == (19, 40, 760), f"Segmented Bar: lines follow the width ({n}, {first}, {last})")
lua.execute("__settings.width:SetValue(600); __settings.segments:SetValue(false)")
check(segment_lines(G.SmoothExperienceBarFrame)[0] == 0, "Segmented Bar off again")

print("== themes")
for i in range(len(ns.Themes.order)):
    key = ns.Themes.order[i + 1]
    lua.execute(f"__settings.theme:SetValue({key!r})")
    run(0.5)
check(len(ns.Themes.order) == 25, f"{len(ns.Themes.order)} themes switch without errors")
ns.Themes.Register("test", lua.eval("{ name = 'Test', fillA = {0, 1, 0}, questText = '00FF00' }"))
lua.execute("__settings.theme:SetValue('test')")
check("|cFF00FF00" in step("theme=test", "SlashCmdList.SMOOTHEXPERIENCEBAR('test quest')", 2), "theme text colour used")
check(list(ns.Themes.Get("test").rested.values()) == [0.31, 0.565, 1, 0.545], "missing theme fields fall back")
lua.execute("__settings.theme:SetValue('luxthos')")

print("== theme picker hover")
theme_dd = next(i for i in items if i.kind == "dropdown" and i.key == "theme")


def hover(key):
    # The menu calls each option's onEnter with the option when the mouse enters it.
    opts = theme_dd.getOptions()
    opt = next(opts[i + 1] for i in range(len(opts)) if opts[i + 1].value == key)
    opt.onEnter(opt)


saved = lambda: G.__settings.theme.GetValue(G.__settings.theme)
lua.execute("__menuOpen = true")
hover("test")
check("|cFF00FF00" in step("hover Test", "SlashCmdList.SMOOTHEXPERIENCEBAR('test quest')", 0.5)
      and saved() == "luxthos", "hovered theme shown on the bar, not saved")
hover("luxthos")
check("|cFF00FF00" not in step("hover Luxthos", None, 0.5), "hovering the saved theme shows it again")
hover("test")
lua.execute("__menuOpen = false")
check("|cFF00FF00" not in step("menu closed", None, 0.5) and saved() == "luxthos",
      "closing the menu without picking goes back to the saved theme")
lua.execute("__menuOpen = true")
hover("fel")
hover("test")
lua.execute("__settings.theme:SetValue('test'); __menuOpen = false")
check("|cFF00FF00" in step("picked Test", None, 0.5) and saved() == "test", "picking a hovered theme keeps it")
lua.execute("__settings.theme:SetValue('luxthos')")

print("== preview buttons")
for item in items:
    if item.kind == "button":
        item.onClick()
        step(f"button: {item.name}", None, 2)
check(st.frame.shown, "Setup Wizard button opens the wizard")
click(wui.welcomeSkip, 1)

print("== mouse, lock and resize")
bar = G.SmoothExperienceBarFrame
lua.execute("__openedCategory = nil; SmoothExperienceBarFrame.scripts.OnMouseUp(SmoothExperienceBarFrame, 'RightButton')")
check(G.__openedCategory == "Smooth Experience Bar" and bar.mouse, "right-click opens settings while locked")
lua.execute("__openedCategory = nil; __combat = true; SmoothExperienceBarFrame.scripts.OnMouseUp(SmoothExperienceBarFrame, 'RightButton')")
check(G.__openedCategory is None, "not opened in combat")
lua.execute("__combat = false; __fire('PLAYER_REGEN_ENABLED')")
check(G.__openedCategory == "Smooth Experience Bar", "opened once combat ends")

lua.execute("SmoothExperienceBarFrame.scripts.OnEnter(SmoothExperienceBarFrame)")
check(not G.GameTooltip.shown, "no tooltip while locked")
lua.execute("__settings.locked:SetValue(false); SmoothExperienceBarFrame.scripts.OnEnter(SmoothExperienceBarFrame)")
lines = [G.GameTooltip.lines[i + 1] for i in range(len(G.GameTooltip.lines))]
check("Right-click for settings" in lines, "tooltip with hints while unlocked")

grip = lua.eval("""function()
    for _, r in ipairs(__regions) do if r.scripts.OnMouseDown then return r end end
end""")()
check(grip.parent.shown, "grip visible while unlocked")
grip.scripts.OnMouseDown(grip, "LeftButton")
check(bar.sizing == "BOTTOMRIGHT" and bar.GetPoint(bar)[0] == "TOPLEFT", "grip sizes from the corner, top-left pinned")
lua.execute("SmoothExperienceBarFrame:SetSize(900, 45)")
run(0.5)
grip.scripts.OnMouseUp(grip, "LeftButton")
row_h = lua.eval("""function()
    for _, r in ipairs(__regions) do
        if r.kind == "Texture" and r.parent == SmoothExperienceBarFrame and r.layer == "ARTWORK" and r.sub == 3 and r.h > 0 then
            return r.h
        end
    end
end""")()
db = G.SmoothExperienceBarDB.profiles["Testchar - Mockrealm"]  # settings are per character
check((db.width, db.height) == (900, 45), "resized size saved")
check(row_h == 3, "liquid slices follow the new height")
lua.execute("__settings.width:SetValue(50); __settings.height:SetValue(500)")
check((db.width, db.height) == (200, 60), "size clamped to its limits")
lua.execute("__settings.locked:SetValue(true)")
check(not grip.parent.shown, "grip hidden when locked")
for item in items:
    if item.kind == "button" and item.name.startswith("Reset Position"):
        item.onClick()
check((db.width, db.height, db.scale) == (600, 30, 0.65) and db.point[1] == "TOP", "reset position, size and scale")

print("== tracked quests only")
lua.eval("""function(L)
    __absorbs = 0
    local absorb = L.Absorb
    L.Absorb = function(...) __absorbs = __absorbs + 1; return absorb(...) end
end""")(ns.Liquid)
lua.execute("""
    SlashCmdList.SMOOTHEXPERIENCEBAR('test off')
    __quests = { { id = 21, xp = 10000, complete = true, watched = true }, { id = 22, xp = 20000, complete = true },
                 { id = 23, xp = 40000 } }
    __fire('QUEST_LOG_UPDATE')
""")
check("9.6%|r - Rested" in step("tracked only off", None, 2), "tracked quests only off: every completed quest counted")
check("3.2%|r - Rested" in step("tracked only on", "__settings.trackedQuestsOnly:SetValue(true)", 2),
      "tracked quests only: an untracked completed quest left out")
check(G.__absorbs == 0, "tracked quests only: leaving quests out plays no turn-in")
check("9.6%|r - Rested" in step("quest tracked", "__quests[2].watched = true; __fire('QUEST_WATCH_LIST_CHANGED')", 2),
      "tracked quests only: tracking a quest adds its XP")
check("3.2%|r - Rested" in step("quest untracked", "__quests[2].watched = nil; __fire('QUEST_WATCH_LIST_CHANGED')", 2)
      and G.__absorbs == 0, "tracked quests only: untracking takes its XP off without a turn-in")
check("3.2%|r - Rested" in step("untracked turned in", "__fire('QUEST_TURNED_IN', 22, 20000, 0)", 0.1),
      "tracked quests only: handing in an untracked quest leaves the tracked XP")
lua.execute("table.remove(__quests, 2); __fire('QUEST_LOG_UPDATE')")
run(1)
step("tracked turned in", "__fire('QUEST_TURNED_IN', 21, 10000, 0)", 0.1)
check(G.__absorbs > 0 and "3.2%|r - Rested" not in state(), "tracked quests only: handing in a tracked quest plays the turn-in")
# A turn-in and an untrack in the same scan: the turn-in still plays, for its own XP only.
lua.execute("""
    __quests = { { id = 31, xp = 10000, complete = true, watched = true }, { id = 32, xp = 20000, complete = true, watched = true } }
    __fire('QUEST_LOG_UPDATE')
""")
check("9.6%|r - Rested" in step("two tracked", None, 2), "tracked quests only: both tracked quests counted")
lua.execute("__absorbs = 0; __quests = { { id = 32, xp = 20000, complete = true } }; __fire('QUEST_LOG_UPDATE')")
check("Completed: |cFFFF97000%|r" in step("turn-in and untrack", None, 2) and G.__absorbs > 0,
      "tracked quests only: a turn-in in the same scan as an untrack still plays")
lua.execute("__settings.trackedQuestsOnly:SetValue(false); __quests = {}; __fire('QUEST_LOG_UPDATE')")
run(2)

print("== Forever")
bad = lua.eval("""function()
    local bad = {}
    for _, r in ipairs(__regions) do
        local f = r.file
        if r.kind == "Texture" and f and f ~= "SOLID" and not f:find("^Interface\\\\AddOns\\\\SmoothExperienceBar\\\\") then
            bad[#bad + 1] = f
        end
    end
    return table.concat(bad, ", ")
end""")()
check(not bad, f"no textures loaded from game paths {bad or ''}")
lua.execute("""
    SlashCmdList.SMOOTHEXPERIENCEBAR('test off')
    GetQuestLogTitle, GetNumQuestLogEntries, SelectQuestLogEntry, GetQuestLogSelection = nil, nil, nil, nil
    local log = {
        { isHeader = true, questID = 0 },
        { isHeader = false, questID = 11, done = true, xp = 9000 },
        { isHeader = false, questID = 12, done = false, xp = 5000 },
        { isHeader = false, questID = 13, ready = true, xp = 6000 },
        { isHeader = false, isHidden = true, questID = 14, done = true, xp = 50000 },
    }
    C_QuestLog.GetNumQuestLogEntries = function() return #log end
    C_QuestLog.GetInfo = function(i) return log[i] end
    C_QuestLog.IsComplete = function(id) for _, q in ipairs(log) do if q.questID == id then return q.done end end end
    C_QuestLog.ReadyForTurnIn = function(id) for _, q in ipairs(log) do if q.questID == id then return q.ready end end end
    GetQuestLogRewardXP = function(id) for _, q in ipairs(log) do if q.questID == id then return q.xp end end return 0 end
    __fire('QUEST_LOG_UPDATE')
""")
check("|cFFFF97004.8%" in step("modern quest log", None, 2), "modern quest log: done and ready quests counted, hidden ones not")
lua.execute("""
    C_QuestLog.GetQuestWatchType = function(id) if id == 11 then return 0 end end
    __settings.trackedQuestsOnly:SetValue(true)
""")
check("|cFFFF97002.9%" in step("modern tracked only", None, 2), "modern quest log: tracked quests only counts watched quests")
lua.execute("__settings.trackedQuestsOnly:SetValue(false)")

# Forever has no MainMenuExpBar; its bars sit in StatusTrackingBarManager.barContainers and the UI
# shows them with SetShown rather than Show.
lua.execute("""
    MainMenuExpBar = nil
    StatusTrackingBarManager = CreateFrame('Frame', nil, UIParent)
    StatusTrackingBarManager.barContainers = { CreateFrame('Frame', nil, UIParent), CreateFrame('Frame', nil, UIParent) }
    __settings.hideBlizzardBar:SetValue(true)
""")
containers = lua.eval("StatusTrackingBarManager.barContainers")
check(not containers[1].shown and not containers[2].shown, "Forever: bar containers hidden")
lua.execute("StatusTrackingBarManager.barContainers[1]:SetShown(true)")
check(not containers[1].shown, "Forever: containers stay hidden when the game calls SetShown(true)")
lua.execute("__settings.hideBlizzardBar:SetValue(false)")
check(containers[1].shown and containers[2].shown and G.StatusTrackingBarManager.shown, "Forever: bars restored")
lua.execute("""
    local c = StatusTrackingBarManager.barContainers[2]
    c:Hide()
    __settings.hideBlizzardBar:SetValue(true)
    c:SetShown(true)
    __settings.hideBlizzardBar:SetValue(false)
""")
check(containers[2].shown, "Forever: a bar the game showed while hidden comes back when the option is off")
lua.execute("""
    local c = StatusTrackingBarManager.barContainers[2]
    __settings.hideBlizzardBar:SetValue(true)
    c:SetShown(false)
    __settings.hideBlizzardBar:SetValue(false)
""")
check(not containers[2].shown, "Forever: a bar the game hid meanwhile stays hidden when the option is off")

# Use Default Experience Bar: a second bar drawn over the game's own XP bar (setting, or /seb skin),
# next to the separate bar or instead of it (Experience Bar: Both or Default Experience Bar).
lua.execute("__chat = {}")
slash("skin", 0.2)
check(any("Could not find the default experience bar" in m for m in G.__chat.values())
      and lua.eval("SmoothExperienceBarDefaultFrame == nil"), "skin: says so and makes nothing when there is no XP bar")
slash("skin", 0.2)
lua.execute("""
    local container = StatusTrackingBarManager.barContainers[1]
    local rep = CreateFrame('Frame', nil, container)
    rep.StatusBar = CreateFrame('Frame', nil, rep)
    local xp = CreateFrame('Frame', nil, container)
    xp.StatusBar = CreateFrame('Frame', nil, xp)
    xp.StatusBar:SetSize(571, 13)
    xp.StatusBar:SetFrameStrata('MEDIUM')
    xp.StatusBar:SetFrameLevel(4)
    xp.ExhaustionTick = CreateFrame('Frame', nil, xp)
    -- The game's own XP text, shown with Status Text set to always show.
    xp.OverlayFrame = CreateFrame('Frame', nil, xp)
    xp.OverlayFrame.Text = xp.OverlayFrame:CreateFontString(nil, 'OVERLAY')
    xp.OverlayFrame.Text:SetText('XP: 204931 / 311490')
    -- Text kept somewhere else on the bar, and another addon's text on it.
    __xpTextElsewhere = xp.StatusBar:CreateFontString(nil, 'OVERLAY')
    __xpTextElsewhere:SetText('204,931 / 311,490')
    __otherText = xp:CreateFontString(nil, 'OVERLAY')
    __otherText:SetText('Rested')
    container.bars = { [1] = rep, [4] = xp }
    -- The segment lines sit in a frame above the bar.
    local lines = CreateFrame('Frame', nil, container)
    lines:SetFrameStrata('MEDIUM')
    lines:SetFrameLevel(30)
    __xpBar = xp
    __chat = {}
""")
bar = G.SmoothExperienceBarFrame
slash("skin", 1)
skin = G.SmoothExperienceBarDefaultFrame
check(lua.eval("SmoothExperienceBarDefaultFrame.parent == __xpBar") and (skin.w, skin.h) == (571, 13) and skin.shown,
      "skin: on the default XP bar, at its size")
check(skin.GetFrameStrata(skin) == "MEDIUM" and skin.level > 4 and skin.scale == 1, "skin: drawn above its fill")
check(lua.eval("SmoothExperienceBarFrame.parent == UIParent") and bar.shown and (bar.w, bar.h) == (600, 30)
      and bar.scale == 0.65, "both: the separate bar stays as it was")
check(any("Drawing over" in m and "571x13" in m for m in G.__chat.values()), "skin: reported in chat")
game_text = lua.eval("__xpBar.OverlayFrame.Text")
check(game_text.alpha == 0, "skin: the game's own XP text hidden under the default bar's, so it does not show twice")
check(lua.eval("__xpTextElsewhere").alpha == 0 and lua.eval("__otherText").alpha == 1,
      "skin: other XP numbers on the bar hidden too, other text there left alone")

# Show as Experience Bar on a faction: Forever gives the reputation bar the main container and shows
# XP in the second container's own XP bar. The skin moves with it, at once, and back again.
lua.execute("""
    StatusTrackingBarInfo = { BarsEnum = { None = -1, Reputation = 1, Experience = 4 } }
    local second = StatusTrackingBarManager.barContainers[2]
    local xp2 = CreateFrame('Frame', nil, second)
    xp2.barIndex = 4
    xp2.StatusBar = CreateFrame('Frame', nil, xp2)
    xp2.StatusBar:SetSize(571, 13)
    xp2:Hide()
    second.bars = { [4] = xp2 }
    __xpBar2 = xp2
""")
run(1.1)
check(lua.eval("SmoothExperienceBarDefaultFrame.parent == __xpBar"), "skin: stays on the shown XP bar, not a hidden one")
lua.execute("__xpBar:Hide(); __xpBar2:Show()")
check(lua.eval("SmoothExperienceBarDefaultFrame.parent == __xpBar2") and skin.shown and game_text.alpha == 1,
      "watched faction: the skin follows XP to the second container straight away, the old bar's text restored")
lua.execute("__xpBar2:Hide(); __xpBar:Show()")
check(lua.eval("SmoothExperienceBarDefaultFrame.parent == __xpBar") and game_text.alpha == 0,
      "faction unwatched: the skin goes back to the main container's XP bar")


# A view's text line starting with prefix: its anchors ("POINT relPoint x y"), whether shown, its parent.
line = lua.eval("""function(frame, prefix)
    for _, r in ipairs(__regions) do
        if r.kind == "FontString" and (r.parent == frame or r.parent.parent == frame) and r.text
            and r.text:find(prefix, 1, true) == 1 then
            local out = {}
            for p, a in pairs(r.points) do out[#out + 1] = string.format("%s %s %g %g", p, a.relPoint, a.x, a.y) end
            return { anchors = table.concat(out, ","), shown = r.shown, parent = r.parent }
        end
    end
end""")
# The skin view's text: the time this level on the left, the XP in the middle, nothing else.
skin_texts = lua.eval("""function()
    local out = {}
    for _, r in ipairs(__regions) do
        if r.kind == "FontString" and r.parent.parent == SmoothExperienceBarDefaultFrame and r.shown
            and r.text and r.text ~= "" then
            out[#out + 1] = r.points.LEFT and ("left: " .. r.text) or r.text
        end
    end
    table.sort(out)
    return table.concat(out, " | ")
end""")
time_line = line(skin, "Time this level")
check(time_line.shown and time_line.parent.level > 30 and time_line.parent.GetFrameStrata(time_line.parent) == "MEDIUM",
      "skin: text above the segment lines")
check(skin_texts() == "204,931 / 311,490 (106,559) | left: Time this level: 6m",
      f"both: the default bar shows the time this level and XP only ({skin_texts()})")
# Rounded Liquid: shade shown and both end masks on every texture of a view.
rounded = lua.eval("""function(frame)
    local shade, masked, textures = false, true, 0
    for _, r in ipairs(__regions) do
        if r.parent == frame and r.kind == "Texture" then
            textures = textures + 1
            if r.file and r.file:find("Shade$") then shade = r.shown end
            if not r.masks or #r.masks ~= 2 then masked = false end
        end
    end
    return shade and masked and textures > 0
end""")
check(rounded(skin) and not rounded(bar), "skin: always rounded, while the separate bar follows its setting (off)")
lua.execute("__settings.rounding:SetValue(true)")
check(rounded(skin) and rounded(bar), "Rounded Liquid on: the separate bar rounds, the default bar stays round")
lua.execute("__settings.rounding:SetValue(false)")
check(rounded(skin) and not rounded(bar), "Rounded Liquid off: only the separate bar changes")
check(line(bar, "Time this level").shown and line(bar, "Leveling in").shown and line(bar, "Level 57").shown,
      "both: the separate bar keeps all its lines")

# Hovering the default bar: a tooltip with what the separate bar shows around itself.
tooltip = lambda: [G.GameTooltip.lines[i + 1] for i in range(len(G.GameTooltip.lines))]
lua.execute("SmoothExperienceBarDefaultFrame.scripts.OnEnter(SmoothExperienceBarDefaultFrame)")
lines = tooltip()
print("  tooltip:", lines)
check(G.GameTooltip.shown and lua.eval("GameTooltip.owner == SmoothExperienceBarDefaultFrame"), "skin: tooltip on hover")
check(lines[0] == "Level 57" and "Experience = 204,931 / 311,490 (65.8%)" in lines and "Remaining = 106,559" in lines
      and "Completed quests = |cFFFF97004.8%|r (15,000 XP)" in lines and "Rested = |cFF4F90FF6.4%|r (20,000 XP)" in lines,
      "skin tooltip: XP, remaining, completed and rested XP in the theme's colours")
check(any(l.startswith("Time this level = ") for l in lines) and any(l.startswith("Time this session = ") for l in lines)
      and any(l.startswith("Leveling in = ") for l in lines) and any(l.startswith("XP per hour = ") for l in lines)
      and lines[-1] == "Right-click for settings", "skin tooltip: session times, leveling time, XP/hour and the settings hint")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('test')")
run(1.2)
check("Experience = 229,850 / 311,490 (73.8%)" in tooltip(), f"skin tooltip: stays current while open ({tooltip()[1]})")
lua.execute("SmoothExperienceBarDefaultFrame.scripts.OnLeave(SmoothExperienceBarDefaultFrame)")
run(1.2)
check(not G.GameTooltip.shown, "skin tooltip: hidden on leave, and the ticker does not bring it back")
slash("test off", 2)
lua.execute("__settings.bars:SetValue('default')")
check(not bar.shown and skin.shown, "default bar only: the separate bar hidden")
check(skin_texts() == "204,931 / 311,490 (106,559) | left: Time this level: 6m",
      f"default bar only: still no lines around it ({skin_texts()})")
lua.execute("__settings.showLevelTime:SetValue(false)")
check("left: Time this level" in skin_texts(), "the separate bar's Time This Level leaves the default bar alone")
lua.execute("__settings.showXPText:SetValue(false)")
check("204,931 / 311,490" in skin_texts(), "the separate bar's XP leaves the default bar alone")
lua.execute("__settings.showXPText:SetValue(true)")
lua.execute("__settings.showLevelTime:SetValue(true); __settings.defaultLeft:SetValue('none')")
check(skin_texts() == "204,931 / 311,490 (106,559)", f"default bar's Left Text set to Nothing: nothing on its left ({skin_texts()})")
lua.execute("__settings.defaultLeft:SetValue('levelTime')")
check("left: Time this level" in skin_texts(), "default bar's Left Text back to Time This Level: it shows it again")
lua.execute("__settings.defaultCentre:SetValue('none')")
check(skin_texts() == "left: Time this level: 6m" and game_text.alpha == 1,
      f"default bar's Centre Text set to Nothing: no XP of ours on it, the game's own back ({skin_texts()})")
lua.execute("__settings.defaultRight:SetValue('xp')")
check("204,931 / 311,490" in skin_texts() and game_text.alpha == 0,
      f"our XP on the right: the game's own hidden so it does not show twice ({skin_texts()})")
lua.execute("__settings.defaultRight:SetValue('none'); __settings.defaultCentre:SetValue('xp')")
check("204,931 / 311,490" in skin_texts() and game_text.alpha == 0, "default bar's XP back on, the game's hidden again")
# The default bar's three texts by where they sit: left, middle and right ("" when empty).
slots = lua.eval("""function()
    local out = { left = "", centre = "", right = "" }
    for _, r in ipairs(__regions) do
        if r.kind == "FontString" and r.parent.parent == SmoothExperienceBarDefaultFrame and r.shown and r.text then
            if r.points.LEFT then out.left = r.text
            elseif r.points.CENTER then out.centre = r.text
            elseif r.points.RIGHT then out.right = r.text end
        end
    end
    return out
end""")
# The commenter's layout: time this level, XP/hour and time to level, just the numbers. A session
# 1h 30m in at about 97K XP/hour, so the rate and the time to level are real numbers.
session_was = lua.eval("{ SmoothExperienceBarCharDB.startTime, SmoothExperienceBarCharDB.gainedXP }")
lua.execute("SmoothExperienceBarCharDB.startTime = time() - 5400; SmoothExperienceBarCharDB.gainedXP = 146000")
lua.execute("__settings.defaultCentre:SetValue('xpHour'); __settings.defaultRight:SetValue('toLevel')")
t = slots()
check(t.left == "Time this level: 6m" and t.centre == "XP/hour: 97.3K" and t.right == "Leveling in: 1h 5m"
      and game_text.alpha == 0,
      f"XP/hour in the middle and time to level on the right, labelled ({t.left} | {t.centre} | {t.right})")
lua.execute("__settings.defaultLabels:SetValue(false)")
t = slots()
check((t.left, t.centre, t.right) == ("6m", "97.3K/h", "1h 5m"),
      f"Text Labels off: just the numbers ({t.left} | {t.centre} | {t.right})")
lua.execute("SmoothExperienceBarCharDB.startTime, SmoothExperienceBarCharDB.gainedXP = ...", *session_was.values())
lua.execute("__settings.defaultLabels:SetValue(true)")
lua.execute("__settings.defaultCentre:SetValue('percent'); __settings.defaultRight:SetValue('rested')")
t = slots()
check(t.centre == "65.8% (70.6%)" and t.right.startswith("Rested: |cFF") and t.right.endswith("6.4%|r"),
      f"percentage in the middle, rested on the right in the theme's colour ({t.centre} | {t.right})")
# While the liquid pours, the XP follows it; the time on the left is left to the 1 s ticker.
lua.execute("__settings.defaultCentre:SetValue('xp'); __settings.defaultRight:SetValue('none')")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('test')")
run(0.3)
mid = slots().centre
run(2)
check(mid != slots().centre and slots().centre.startswith("229,850 / 311,490"),
      f"the default bar's XP follows the liquid as it pours ({mid} -> {slots().centre})")
slash("test off", 2)
check(skin_texts() == "204,931 / 311,490 (106,559) | left: Time this level: 6m", f"back to the usual look ({skin_texts()})")
# Text sizes: each of the default bar's three texts has its own, apart from the separate bar's.
skin_frame = G.SmoothExperienceBarDefaultFrame
sizes = lambda: (font_at(skin_frame, "LEFT", "LEFT")[0], font_at(skin_frame, "CENTER", "CENTER")[0],
                 font_at(skin_frame, "RIGHT", "RIGHT")[0])
before, bar_xp = sizes(), font_at(bar, "CENTER", "CENTER")[0]
lua.execute("__settings.defaultCentreSize:SetValue(150)")
after = sizes()
check(after[1] > before[1] and (after[0], after[2]) == (before[0], before[2])
      and font_at(bar, "CENTER", "CENTER")[0] == bar_xp,
      f"default bar's Centre Text Size: only its middle text grows ({before} -> {after})")
lua.execute("__settings.defaultLeftSize:SetValue(50); __settings.defaultRightSize:SetValue(200)")
after = sizes()
check(after[0] < before[0] and after[2] > before[2], f"Left and Right Text Size: each its own ({before} -> {after})")
lua.execute("__settings.defaultLeftSize:SetValue(100); __settings.defaultCentreSize:SetValue(100); "
            "__settings.defaultRightSize:SetValue(100)")
check(sizes() == before, f"default bar's text sizes back ({sizes()})")
# On the settings page each of the three has its size slider on its own row, beside the dropdown.
slot_rows = {i.key: i.frame for i in G.__settingsRows().values() if i.kind == "dropdown" and i.frame.SizeSlider}
check(set(slot_rows) == {"defaultLeft", "defaultCentre", "defaultRight", "repLeft", "repCentre", "repRight"}
      and all(f.Control.steppersHidden and f.Control.Dropdown.w < 220 for f in slot_rows.values()),
      "default and reputation bars: Left, Centre and Right each with a size slider, the dropdown narrowed to make room")
centre_slider = slot_rows["defaultCentre"].SizeSlider
check(centre_slider.Slider.value == 100 and centre_slider.label == "100%", "size slider starts at the setting")
centre_slider.SetValue(centre_slider, 125)
check(lua.eval("__settings.defaultCentreSize:GetValue()") == 125
      and sizes()[1] > before[1], f"moving the size slider sizes the centre text ({sizes()})")
lua.execute("__settings.defaultCentreSize:SetValue(100)")
check(centre_slider.Slider.value == 100 and centre_slider.label == "100%",
      "size slider follows the setting changed elsewhere (a copied profile)")
check(all(f.SizeSlider.enabled for k, f in slot_rows.items() if k != "defaultRight")
      and not slot_rows["defaultRight"].SizeSlider.enabled, "size slider greyed out while its text shows Nothing")
lua.execute("__settings.defaultRight:SetValue('percent')")
check(slot_rows["defaultRight"].SizeSlider.enabled, "and live again once it shows something")
lua.execute("__settings.defaultRight:SetValue('none')")
preview_xp = lua.eval("""function(ns)
    __settings.defaultCentreSize:SetValue(200)
    local v = ns.Core.NewPreview(UIParent, "skin")
    local size = v.xpText.fontSize
    __settings.defaultCentreSize:SetValue(100)
    return size
end""")(ns)
check(preview_xp == before[1], f"wizard previews keep the usual text size whatever the settings ({preview_xp})")
# Completed quest and rested segments: (shown, width) of each, per bar.
segment = lua.eval('''function(frame, sub)
    for _, r in ipairs(__regions) do
        if r.parent == frame and r.kind == "Texture" and r.layer == "ARTWORK" and r.sub == sub and r.file == "SOLID" then
            return r.shown and r.w or 0
        end
    end
end''')
quest_w = lambda f: segment(f, 1)
rested_w = lambda f: segment(f, 0)
lua.execute("__settings.bars:SetValue('both')")
run(0.5)
both_q, both_r = quest_w(skin), rested_w(skin)
check(both_q > 0 and both_r > 0 and quest_w(bar) > 0 and rested_w(bar) > 0,
      f"both bars show completed quest and rested XP ({both_q:.1f}, {both_r:.1f})")
lua.execute("__settings.defaultQuestBar:SetValue(false)")
run(0.2)
check(quest_w(skin) == 0 and rested_w(skin) > 0 and quest_w(bar) > 0,
      "default bar's Completed Quest Bar off: only its quest segment goes, rested moves up to the fill")
lua.execute("__settings.defaultRestedBar:SetValue(false)")
run(0.2)
check(quest_w(skin) == 0 and rested_w(skin) == 0 and rested_w(bar) > 0, "default bar's Rested Bar off: its rested segment goes")
lua.execute("__settings.questBar:SetValue(false); __settings.restedBar:SetValue(false)")
run(0.2)
check(quest_w(bar) == 0 and rested_w(bar) == 0, "separate bar's Completed Quest Bar and Rested Bar off")
lua.execute('''__settings.questBar:SetValue(true); __settings.restedBar:SetValue(true)
    __settings.defaultQuestBar:SetValue(true); __settings.defaultRestedBar:SetValue(true)
    __settings.bars:SetValue('default')''')
lua.execute("GameTooltip:Hide(); __settings.defaultTooltip:SetValue(false)")
lua.execute("SmoothExperienceBarDefaultFrame.scripts.OnEnter(SmoothExperienceBarDefaultFrame)")
check(not G.GameTooltip.shown, "default bar's Tooltip off: no tooltip on hover")
lua.execute("__settings.defaultTooltip:SetValue(true)")
slash("test", 4)
check("229,850" in skin_texts(), "default bar only: still animates with the separate bar hidden")
slash("test off", 2)
lua.execute("__xpBar.StatusBar:SetSize(700, 15)")
run(1.5)
check((skin.w, skin.h) == (700, 15), "skin: follows the XP bar's size")
lua.execute("__settings.hideBlizzardBar:SetValue(true)")
check(containers[1].shown, "skin: the default bar is not hidden while drawn over")
lua.execute("__settings.hideBlizzardBar:SetValue(false)")
lua.execute("__settings.bars:SetValue('both')")
check(bar.shown and line(bar, "Leveling in").anchors == "LEFT BOTTOMLEFT 0 -18",
      "separate bar back: its lines under it as before")
step("setting off", "__settings.bars:SetValue('separate')", 0.2)
check(not skin.shown and bar.shown and (bar.w, bar.h) == (600, 30), "skin off: only the separate bar, as it was")
check(game_text.alpha == 1 and lua.eval("__xpTextElsewhere").alpha == 1, "skin off: the game's own XP text back")

print("== reputation bar")
lua.execute("__settings.bars:SetValue('both')")
# The liquid over the game's own reputation bar, which the game shows while a faction is watched.
# Each container has its own reputation bar, as it has its own XP bar.
lua.execute("""
    local function RepBar(container)
        local b = CreateFrame('Frame', nil, container)
        b.barIndex = 1
        b.StatusBar = CreateFrame('Frame', nil, b)
        b.StatusBar:SetSize(571, 13)
        b.StatusBar:SetFrameStrata('MEDIUM')
        b.StatusBar:SetFrameLevel(4)
        b.OverlayFrame = CreateFrame('Frame', nil, b)
        b.OverlayFrame.Text = b.OverlayFrame:CreateFontString(nil, 'OVERLAY')
        b.OverlayFrame.Text:SetText('Stormwind 1500 / 3000')
        b:Hide()
        container.bars[1] = b
        return b
    end
    local containers = StatusTrackingBarManager.barContainers
    __repBar, __repBar2 = RepBar(containers[1]), RepBar(containers[2])
""")
rep = lambda: ns.Reputation.State()
rep_texts = lambda: tuple(rep().view[k].text for k in ("levelText", "xpText", "pctText"))
rep_game_text = lambda: lua.eval("__repBar.OverlayFrame.Text")
# Watching a faction on Forever: reputation takes the main container, XP moves up to the second.
lua.execute("""
    __watchedFaction = { name = 'Stormwind', reaction = 4, currentReactionThreshold = 0,
                         nextReactionThreshold = 3000, currentStanding = 1500, factionID = 72 }
    __xpBar:Hide(); __xpBar2:Show(); __repBar:Show()
    __fire('UPDATE_FACTION')
""")
run(1.1)
check(rep().view is None and rep_game_text().alpha == 1, "reputation bar: off to start with, nothing made or hidden")
lua.execute("__chat = {}; __settings.repBar:SetValue(true)")
run(0.5)
rv = rep().view
check(lua.eval("SmoothExperienceBarReputationFrame.parent == __repBar") and (rv.frame.w, rv.frame.h) == (571, 13)
      and rv.frame.shown and lua.eval("SmoothExperienceBarDefaultFrame.parent == __xpBar2"),
      "reputation bar: on the game's reputation bar at its size, the XP one still on the XP bar")
check(not any("watch a faction" in m for m in G.__chat.values()), "reputation bar: no hint while a faction is watched")
check(rep_texts() == ("Stormwind", "1,500 / 3,000", "Neutral") and rep_game_text().alpha == 0,
      f"reputation bar: faction, reputation and standing, the game's own text hidden ({rep_texts()})")
neutral = rv.theme
check(neutral.key == "standing" and neutral.fillB[1] > neutral.fillB[3] and neutral.fillB[2] > neutral.fillB[3],
      "reputation bar: the game's yellow for Neutral to start with")
check(rv.frame.level > 4 and rv.textFrame.level > rv.frame.level, "reputation bar: drawn above the fill, text above that")

# The game's end caps over the ends of a bar above the action bars. Forever's are Edit Mode frames
# (with a Selection) 154 wide, whose art stops 20 short of their inner edge. The bars' fills sit at
# x 660 to 1231, y 1027 to 1040 in the mock.
lua.execute("""
    MainActionBar = CreateFrame('Frame', nil, UIParent)
    MainActionBar.EndCaps = CreateFrame('Frame', nil, MainActionBar)
    function __placeCaps(left, right)
        local caps = MainActionBar.EndCaps
        local function Cap(x)
            local cap = CreateFrame('Frame', nil, caps)
            cap:SetSize(154, 95)
            cap.screenLeft, cap.screenTop = x, 1100
            cap.Selection = CreateFrame('Frame', nil, cap)
            cap.Selection:Hide()
            cap.Texture = cap:CreateTexture(nil, 'OVERLAY')
            return cap
        end
        caps.LeftEndCap, caps.RightEndCap = Cap(left), Cap(right)
    end
    -- The left gryphon's art reaches 44 in from the bar's left end, the right one's 61 in.
    __placeCaps(570, 1150)
""")
run(1.1)
text_x = lambda fs, point: fs.points[point].x
check(text_x(rv.levelText, "LEFT") == 59 and text_x(rv.pctText, "RIGHT") == -76,
      f"end caps: the left and right text moved in just clear of their art ({text_x(rv.levelText, 'LEFT')}, "
      f"{text_x(rv.pctText, 'RIGHT')})")
check(line(skin, "Time this level").anchors == "LEFT LEFT 59 0", "end caps: the default XP bar's left text too")
lua.execute("__placeCaps(500, 1240)")
run(1.1)
check(text_x(rv.levelText, "LEFT") == 5 and text_x(rv.pctText, "RIGHT") == -5,
      "end caps: only the empty part of their frames over the bar, the text stays at the edges")
lua.execute("__placeCaps(570, 1150); MainActionBar.EndCaps:Hide()")
run(1.1)
check(text_x(rv.levelText, "LEFT") == 5 and text_x(rv.pctText, "RIGHT") == -5,
      "end caps hidden (no faction art, or Edit Mode moved the bar): back to the edges")
lua.execute("MainActionBar = nil")

lua.execute("__watchedFaction.currentStanding = 2100; __fire('UPDATE_FACTION')")
run(0.35)  # past the moment the gain is held before the liquid moves
mid = rep_texts()[1]
mid_value = int(mid.split(" / ")[0].replace(",", ""))
run(2)
check(1500 < mid_value < 2100 and rep_texts()[1] == "2,100 / 3,000",
      f"reputation gain: the numbers follow the liquid as it pours ({mid} -> {rep_texts()[1]})")

# A new standing: the liquid pours to the end of Neutral, then flashes into Friendly's green.
lua.execute("""
    __watchedFaction.reaction, __watchedFaction.currentReactionThreshold = 5, 3000
    __watchedFaction.nextReactionThreshold, __watchedFaction.currentStanding = 9000, 3600
    __fire('UPDATE_FACTION')
""")
run(0.05)
check(rep().shown.wrap and rep_texts()[2] == "Neutral", "new standing: Neutral pours to its end first")
run(3)
friendly = rep().view.theme
check(rep_texts() == ("Stormwind", "600 / 6,000", "Friendly") and not rep().shown.wrap,
      f"new standing: then Friendly from empty ({rep_texts()})")
check(friendly.fillB[2] > friendly.fillB[1] and friendly.fillB[2] > friendly.fillB[3] and friendly.key == "standing",
      "new standing: in the game's green for Friendly")

lua.execute("SmoothExperienceBarReputationFrame.scripts.OnEnter(SmoothExperienceBarReputationFrame)")
rep_tip = [G.GameTooltip.lines[i + 1] for i in range(len(G.GameTooltip.lines))]
print("  tooltip:", rep_tip)
check(rep_tip[0] == "Stormwind" and "Friendly" in rep_tip[1] and "Reputation = 600 / 6,000 (10%)" in rep_tip
      and "To Honored = 5,400" in rep_tip and "To Exalted = 38,400" in rep_tip
      and "Gained this session = +2,100" in rep_tip and any(l.startswith("Time this session = ") for l in rep_tip)
      and any(l.startswith("Honored in = ") and not l.endswith("--") for l in rep_tip)
      and any(l.startswith("Reputation per hour = ") for l in rep_tip)
      and rep_tip[-1] == "Right-click for settings",
      "reputation tooltip: standing, reputation, to next and to Exalted, and this session's gains, time and rate")
lua.execute("SmoothExperienceBarReputationFrame.scripts.OnLeave(SmoothExperienceBarReputationFrame)")

lua.execute("__settings.repCentre:SetValue('none'); __settings.repRight:SetValue('remaining')")
check(rep_texts() == ("Stormwind", "", "5,400 to Honored") and rep_game_text().alpha == 1,
      f"reputation texts: Centre set to Nothing gives the game's text back, Right to the next standing ({rep_texts()})")
lua.execute("__settings.repCentre:SetValue('value'); __settings.repRight:SetValue('standing')")
check(rep_game_text().alpha == 0, "reputation texts: back, the game's hidden again")
lua.execute("__settings.repTheme:SetValue('fel')")
check(rep().view.theme.key == "fel", "reputation theme: any of the themes")
lua.execute("__settings.repTheme:SetValue('standing')")
check(rep().view.theme.key == "standing", "reputation theme: back to standing colours")
before = rep().view.xpText.fontSize
lua.execute("__settings.repCentreSize:SetValue(150)")
after = rep().view.xpText.fontSize
check(before and after > before and rep().view.levelText.fontSize < after,
      f"reputation Centre Text Size: only its middle text grows ({before} -> {after})")
lua.execute("__settings.repCentreSize:SetValue(100)")

slash("test rep", 2)
check(rep_texts()[1] == "1,200 / 6,000", f"/seb test rep: a tenth of the standing ({rep_texts()[1]})")
slash("test off", 2)
check(rep_texts()[1] == "600 / 6,000", f"/seb test off: back to the real reputation ({rep_texts()[1]})")

# Unwatched: the game hides its bar, and ours with it. Watched again with reputation in the second
# container (as on Era, where XP keeps the main one): ours follows.
lua.execute("__watchedFaction = nil; __repBar:Hide(); __xpBar2:Hide(); __xpBar:Show(); __fire('UPDATE_FACTION')")
run(0.2)
check(not lua.eval("SmoothExperienceBarReputationFrame:IsVisible()"), "faction unwatched: the reputation bar goes with the game's")
lua.execute("""
    __watchedFaction = { name = 'Darnassus', reaction = 6, currentReactionThreshold = 9000,
                         nextReactionThreshold = 21000, currentStanding = 12000, factionID = 69 }
    __repBar2:Show()
    __fire('UPDATE_FACTION')
""")
run(0.2)
check(lua.eval("SmoothExperienceBarReputationFrame.parent == __repBar2") and rep_texts() == ("Darnassus", "3,000 / 12,000", "Honored"),
      f"another faction, in the second container: ours follows, straight to its standing ({rep_texts()})")
lua.execute("__settings.repBar:SetValue(false)")
check(not rep().view.frame.shown and lua.eval("__repBar2.OverlayFrame.Text").alpha == 1,
      "reputation bar off: ours hidden, the game's text back")
lua.execute("__watchedFaction = nil; __repBar2:Hide(); __fire('UPDATE_FACTION')")
lua.execute("__chat = {}; __settings.repBar:SetValue(true)")
check(any("watch a faction" in m for m in G.__chat.values()),
      "reputation bar turned on with no faction watched: says how to watch one")
lua.execute("__settings.repBar:SetValue(false)")

print("== separate bar tracking reputation")
same = lua.eval("function(a, b) return a == b end")
# Tracks: Reputation. The separate bar shows the watched faction in the reputation theme and text,
# without XP's lines around it or its completed quest and rested segments.
lua.execute("""
    SmoothExperienceBarCharDB.repSession = nil -- this block's session starts here
    __watchedFaction = { name = 'Stormwind', reaction = 5, currentReactionThreshold = 3000,
                         nextReactionThreshold = 9000, currentStanding = 4500, factionID = 72 }
    __fire('UPDATE_FACTION')
    __settings.separateTracks:SetValue('rep')
""")
run(0.3)
check(rep().bar is not None and same(rep().bar.frame, bar) and bar.shown and not rep().view.frame.shown,
      "Tracks Reputation: the separate bar shows reputation, the game's bar left alone (it is off)")
check(state().startswith("Stormwind | 1,500 / 6,000 | Friendly |"),
      f"Tracks Reputation: faction, reputation and standing ({state()})")
check(quest_w(bar) == 0 and rested_w(bar) == 0 and rep().bar.theme.key == "standing",
      "Tracks Reputation: no completed quest or rested XP, in the standing colours")
lua.execute("__watchedFaction.currentStanding = 5100; __fire('UPDATE_FACTION')")
run(1.5)
check("2,100 / 6,000" in state(), f"Tracks Reputation: reputation gains pour into it ({state()})")
# The lines around it, in XP's places: this session's gains, the session time, the time to the next standing
# at this session's rate, and what is left to Exalted (3,900 + Honored + Revered).
around = state().split(" | ")[3:]
print("  around:", around)
check("Gained this session: +600" in around and any(a.startswith("Time this session: ") for a in around)
      and any(a.startswith("Honored in: ") and a.endswith(" Rep/Hour)") for a in around)
      and "To Exalted: 36,900" in around, f"Tracks Reputation: reputation's lines around the bar ({around})")
lua.execute("__settings.showLevelTime:SetValue(false); __settings.showQuestRested:SetValue(false)")
around = state().split(" | ")[3:]
check(not any(a.startswith("Gained") or a.startswith("To Exalted") for a in around) and len(around) == 2,
      f"Tracks Reputation: each line follows its Text setting ({around})")
lua.execute("__settings.showLevelTime:SetValue(true); __settings.showQuestRested:SetValue(true)")
# Hovering it while locked: the reputation tooltip, under the bar.
lua.execute("SmoothExperienceBarFrame.scripts.OnEnter(SmoothExperienceBarFrame)")
sep_tip = [G.GameTooltip.lines[i + 1] for i in range(len(G.GameTooltip.lines))]
print("  tooltip:", sep_tip)
check(G.GameTooltip.shown and same(G.GameTooltip.owner, bar) and sep_tip[0] == "Stormwind"
      and "To Exalted = 36,900" in sep_tip and "Gained this session = +600" in sep_tip
      and any(l.startswith("Reputation per hour = ") for l in sep_tip),
      "Tracks Reputation: hovering the bar shows the reputation tooltip with this session's stats")
lua.execute("SmoothExperienceBarFrame.scripts.OnLeave(SmoothExperienceBarFrame)")
slash("test", 1)
check("2,100 / 6,000" in state() and "229,850" not in state(), "Tracks Reputation: XP gains leave it alone")
slash("test off", 1)
# Reset Session: this session's reputation starts again, and the very next gain counts.
slash("session", 0.2)
lua.execute("__watchedFaction.currentStanding = 5400; __fire('UPDATE_FACTION')")
run(1.5)
check("Gained this session: +300" in state(), f"Tracks Reputation: after Reset Session the next gain counts ({state()})")
# Segmented Bar reaches it while it tracks reputation.
lua.execute("__settings.segments:SetValue(true)")
check(rep().bar.segments[1].shown, "Tracks Reputation: Segmented Bar applies to it")
# Fade When Idle: reputation gains bring it back, XP gains (which it does not show) do not.
lua.execute("__settings.fadeIdle:SetValue(true); __settings.fadeDelay:SetValue(2)")
run(4.5)
faded = bar.alpha
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('test')")  # an XP gain, without touching the real XP
run(0.3)
xp_woke = bar.alpha
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('test off')")
lua.execute("__watchedFaction.currentStanding = 5500; __fire('UPDATE_FACTION')")
run(0.3)
check(faded == 0 and xp_woke == 0 and bar.alpha > 0,
      f"Tracks Reputation: faded, an XP gain leaves it, a reputation gain brings it back ({faded}, {xp_woke}, {bar.alpha})")
lua.execute("__settings.fadeIdle:SetValue(false); __settings.fadeDelay:SetValue(ns_defaults.fadeDelay)")
run(0.5)
lua.execute("__settings.repLeft:SetValue('remaining'); __settings.repLeftSize:SetValue(150)")
check(state().startswith("3,500 to Honored"), f"Tracks Reputation: the Reputation section's text ({state()})")
lua.execute("__settings.repLeft:SetValue('name'); __settings.repLeftSize:SetValue(100)")
lua.execute("__watchedFaction = nil; __fire('UPDATE_FACTION')")
run(0.2)
check(not bar.shown, "Tracks Reputation: hidden while no faction is watched")
lua.execute("__chat = {}")
slash("test rep", 0.2)
check(any("Watch a faction" in m for m in G.__chat.values()) and not bar.shown,
      "Tracks Reputation: no preview of a faction no longer watched")
lua.execute("__settings.separateTracks:SetValue('xp')")
run(0.3)
check(rep().bar is None and bar.shown and state().startswith("Level 57 | 204,931 / 311,490")
      and "Time this level" in state() and quest_w(bar) > 0,
      f"Tracks Experience again: XP, its lines and segments back ({state()})")
check(lua.eval("SmoothExperienceBarFrame") and rep().bar is None and ns.Bar.main.segments[1].shown,
      "Tracks Experience again: Segmented Bar still on it")
lua.execute("__settings.segments:SetValue(false)")
# Hide Default Experience Bar leaves the game's status bars alone while the reputation bar is drawn in them.
lua.execute("__settings.bars:SetValue('separate'); __settings.hideBlizzardBar:SetValue(true)")
check(not containers[1].shown, "Hide Default Experience Bar: the game's bars hidden")
lua.execute("__settings.repBar:SetValue(true)")
check(containers[1].shown and not row_shown("checkbox", "hideBlizzardBar"),
      "Default Reputation Bar on: they show again for it, and Hide Default Experience Bar is not offered")
lua.execute("__settings.repBar:SetValue(false)")
check(not containers[1].shown, "Default Reputation Bar off: hidden again")
lua.execute("__settings.hideBlizzardBar:SetValue(false); __settings.bars:SetValue('both')")
# Re-running the setup keeps a reputation theme of its own, unless another reputation card is picked.
lua.execute("__settings.repBar:SetValue(true); __settings.repTheme:SetValue('frost')")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('setup')")
run(0.2)
click(wui.start)
while wiz().page != "done":
    click(wui.next)
click(wui.next, 0.5)
check(lua.eval("__settings.repTheme:GetValue()") == "frost" and not st.frame.shown,
      "setup again: a reputation theme of its own is kept")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('setup')")
run(0.2)
click(wui.start)
while wiz().page != "rep":
    click(wui.next)
click(cards.rep.standing)
click(cards.rep.theme)
while wiz().page != "done":
    click(wui.next)
click(wui.next, 0.5)
check(lua.eval("__settings.repTheme:GetValue()") == lua.eval("__settings.theme:GetValue()"),
      "setup again: picking another reputation card, then Match Your Theme, matches the theme")
lua.execute("__settings.repBar:SetValue(false); __settings.repTheme:SetValue('standing')")
lua.execute("__settings.bars:SetValue('separate')")

# XP values can be secret in combat: nothing may break, and the bar and XP/hour catch up afterwards.
chardb = G.SmoothExperienceBarCharDB
lua.execute("__player.secret = true; __combat = true; __player.xp = __player.xp + 5000")
during = step("secret XP gain", "__fire('PLAYER_XP_UPDATE', 'player'); __fire('UPDATE_EXHAUSTION')", 2)
check("204,931 / 311,490" in during, "secret XP: bar keeps its last values, no errors")
slash("session", 1)
check(chardb.lastXP is None, "secret XP: session reset waits for readable XP")
lua.execute("__player.xp = __player.xp + 1000; __fire('PLAYER_XP_UPDATE', 'player')")
slash("test", 1)
slash("test off", 1)
lua.execute("__player.secret = false; __combat = false")
after = step("XP readable again", None, 2)
check("210,931" in after, "secret XP: bar catches up once the values are readable")
check(chardb.gainedXP == 0 and chardb.lastXP == 210931, "secret XP: session restarts from the first readable XP")
lua.execute("__player.xp = __player.xp + 3000; __fire('PLAYER_XP_UPDATE', 'player')")
check(chardb.gainedXP == 3000, "secret XP: the first kill after that counts")
# Reset in combat with no XP change before the values are readable again.
lua.execute("__player.secret = true; SlashCmdList.SMOOTHEXPERIENCEBAR('session'); __player.secret = false")
run(1.5)
lua.execute("__player.xp = __player.xp + 3000; __fire('PLAYER_XP_UPDATE', 'player')")
check(chardb.gainedXP == 3000, "secret XP: after a reset in combat, the first readable kill counts")
lua.execute("__player.secret = true; __player.xp = __player.xp + 2000; __fire('PLAYER_XP_UPDATE', 'player')")
run(0.5)
lua.execute("__player.secret = false")
check("218,931" in step("XP readable again", None, 2) and chardb.gainedXP == 5000,
      "secret XP: XP/hour counts gains made while secret")
# Two levels while secret: the rest of 57, all of 58 (estimated at the current level's size), 1,000 into 59.
lua.execute("""
    __player.secret = true
    __player.level, __player.xp = 59, 1000
    __fire('PLAYER_XP_UPDATE', 'player'); __fire('PLAYER_LEVEL_UP', 59)
""")
run(0.5)
lua.execute("__player.secret = false")
check("Level 59 | 1,000 / 311,490" in step("two levels while secret", None, 6), "secret XP: bar catches up over two levels")
check(chardb.gainedXP == 5000 + (311490 - 218931) + 1000 + 311490 and chardb.lastLevel == 59,
      "secret XP: XP/hour counts every level gained while secret")
lua.execute("__player.secretRested = true; __player.xp = 1500")
check("1,500 / 311,490" in step("rested secret", "__fire('PLAYER_XP_UPDATE', 'player')", 1),
      "secret rested XP alone does not stop the bar")
lua.execute("__player.secretRested = false")
step("secret turn-in reward", "__fire('QUEST_TURNED_IN', 11, __secret(), 0)", 1)  # must not error

print("== fade when idle")
alpha = lambda: G.SmoothExperienceBarFrame.GetAlpha(G.SmoothExperienceBarFrame)
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('test off'); __settings.bars:SetValue('separate'); __settings.locked:SetValue(true)")
lua.execute("SmoothExperienceBarFrame.scripts.OnLeave(SmoothExperienceBarFrame)")  # earlier tests hovered it
run(1)
check(alpha() == 1, "fade: off by default, the bar stays")
lua.execute("__settings.fadeDelay:SetValue(5); __settings.fadeIdle:SetValue(true)")
run(4)
check(alpha() == 1, "fade: still shown before the delay")
run(3)
check(alpha() == 0 and G.SmoothExperienceBarFrame.mouse, "fade: gone after the delay, still takes the mouse")
lua.execute("SmoothExperienceBarFrame.scripts.OnEnter(SmoothExperienceBarFrame)")
run(0.5)
check(alpha() == 1, "fade: back while hovered")
run(10)
check(alpha() == 1, "fade: stays while hovered")
lua.execute("SmoothExperienceBarFrame.scripts.OnLeave(SmoothExperienceBarFrame)")
run(7)
check(alpha() == 0, "fade: fades again after the mouse leaves")
lua.execute("__combat = true; __fire('PLAYER_REGEN_DISABLED')")
run(1)
check(alpha() == 0, "fade: combat alone does not bring it back")
lua.execute("__combat = false; __fire('PLAYER_REGEN_ENABLED')")
run(1)
check(alpha() == 0, "fade: nor does combat ending")
t = step("faded XP gain", "SlashCmdList.SMOOTHEXPERIENCEBAR('test')", 1); check("Level" in t and alpha() == 1,
      "fade: an XP gain shows the bar, which kept up while faded")
run(7)
check(alpha() == 0, "fade: and fades again")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('unlock')")
run(10)
check(alpha() == 1, "fade: never while unlocked")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('lock'); __settings.fadeOpacity:SetValue(30)")
run(7)
check(abs(alpha() - 0.3) < 1e-9, f"fade: down to the faded opacity ({alpha()})")
check("Level" in step("dimmed", None, 0.5), "fade: a dimmed bar keeps drawing")
lua.execute("SmoothExperienceBarFrame.scripts.OnEnter(SmoothExperienceBarFrame)")
run(0.5)
check(alpha() == 1, "fade: hovering a dimmed bar reveals it fully")
lua.execute("SmoothExperienceBarFrame.scripts.OnLeave(SmoothExperienceBarFrame)")
run(7)
check(abs(alpha() - 0.3) < 1e-9, "fade: dims again after the mouse leaves")
lua.execute("__settings.fadeIdle:SetValue(false)")
run(10)
check(alpha() == 1, "fade: turned off, the bar stays")
lua.execute("__settings.fadeDelay:SetValue(ns_defaults.fadeDelay); __settings.fadeOpacity:SetValue(ns_defaults.fadeOpacity); "
            "SlashCmdList.SMOOTHEXPERIENCEBAR('test off')")
run(1)

print("== max level")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('test off'); __player.level = 70; __player.xp = 0")
check(step("showMaxLevel off", "__fire('PLAYER_XP_UPDATE', 'player')").startswith("[hidden]"), "hidden at max level")
# Tracks: Experience, Reputation at Max Level. At the cap the separate bar shows the watched faction.
lua.execute("""
    __watchedFaction = { name = 'Stormwind', reaction = 5, currentReactionThreshold = 3000,
                         nextReactionThreshold = 9000, currentStanding = 4500, factionID = 72 }
    __fire('UPDATE_FACTION')
    __settings.separateTracks:SetValue('auto')
""")
run(1.2)
check(state().startswith("Stormwind | 1,500 / 6,000 | Friendly |"),
      f"Tracks Experience, Reputation at Max Level: reputation at the cap ({state()})")
lua.execute("__settings.separateTracks:SetValue('xp'); __watchedFaction = nil; __fire('UPDATE_FACTION')")
check(state().startswith("[hidden]"), "Tracks Experience again: hidden at max level once more")
check("Max Level" in step("showMaxLevel on", "__settings.showMaxLevel:SetValue(true)"), "full bar at max level")
# Forever: level cap 60, and GetMaxPlayerLevel may be missing.
lua.execute("""
    __settings.showMaxLevel:SetValue(false)
    __eraGetMaxPlayerLevel = GetMaxPlayerLevel
    GetMaxPlayerLevel, MAX_PLAYER_LEVEL = nil, nil
    __player.level, __player.xp, __player.max = 59, 1000, 200000
""")
check(not step("Forever level 59", "__fire('PLAYER_XP_UPDATE', 'player')").startswith("[hidden]"), "Forever: shown below the cap")
lua.execute("__player.level, __player.xp, __player.max = 60, 0, 0")
check(step("Forever level 60", "__fire('PLAYER_LEVEL_UP', 60)").startswith("[hidden]"),
      "Forever: no XP left to earn counts as max level")
lua.execute("__player.max = 209800; IsPlayerAtEffectiveMaxLevel = function() return true end")
check(step("Forever at cap", "__fire('PLAYER_XP_UPDATE', 'player')").startswith("[hidden]"),
      "Forever: IsPlayerAtEffectiveMaxLevel counts as max level")
lua.execute("IsPlayerAtEffectiveMaxLevel = nil; GetMaxPlayerLevel = __eraGetMaxPlayerLevel")

print("== per-character profiles")
# A fresh client session whose saved settings come from before profiles, when they were account-wide.
# It stands for Era and Anniversary, which have no issecretvalue.
lua2 = LuaRuntime(unpack_returned_tuples=True)
lua2.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
lua2.execute("issecretvalue = nil; __interface = 11509")
lua2.execute("SmoothExperienceBarDB = { theme = 'fel', width = 820, glass = true, layout = 2, point = { 'TOP', 'UIParent', 'TOP', 0, -90 }, "
              "showBar = false, skinDefaultBar = true, showLevelTime = false, defaultXPText = false, defaultRight = 'bogus' }")
G2 = lua2.globals()
G2.__loadAddon(ADDON.replace("\\", "/"), "SmoothExperienceBar")
lua2.execute("__fire('ADDON_LOADED', 'SmoothExperienceBar'); __fire('PLAYER_ENTERING_WORLD', true, false)")
mine = lua2.eval("SmoothExperienceBarDB.profiles['Testchar - Mockrealm']")
check(mine is not None and mine.theme == "fel" and mine.width == 820 and mine.glass,
      "old account-wide settings carried into this character's profile")
check(mine.bars == "default" and mine.showBar is None and mine.skinDefaultBar is None,
      "the old bar checkboxes become the Experience Bar choice")
check(mine.defaultLeft == "none" and mine.defaultLevelTime is None,
      "before 1.3: the default bar's left follows the old Time This Level (off: nothing there)")
check(mine.defaultCentre == "none" and mine.defaultXPText is None,
      "before 1.6: the default bar's XP checkbox, off, becomes nothing in its middle")
check(mine.defaultRight == "none", "a saved text choice the addon does not know goes back to the default")
for _ in range(240):
    G2.__step(1 / 60)
setup2 = lua2.eval("SmoothExperienceBarSetup")
check(setup2 is not None and setup2.shown and mine.setupPending and lua2.eval("SmoothExperienceBarDB.setupOffered"),
      "someone who had the addon before the wizard sees it once after updating")
has_text = lua2.eval("""function(text)
    for _, r in ipairs(__regions) do if r.text == text then return true end end
    return false
end""")
check(has_text("Skip, keep my settings") and not has_text("Skip, use the defaults"),
      "updating player: skipping keeps their settings, and says so")
lua2.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('setup')")
era_bg = lua2.eval("SmoothExperienceBarSetup.Bg.points.TOPLEFT")
check((era_bg.x, era_bg.y) == (2, -21), "Era: the window's background keeps the classic border's own inset")
check(lua2.eval("SmoothExperienceBarDB.theme") is None and lua2.eval("SmoothExperienceBarDB.legacy.theme") == "fel",
      "old settings moved out of the top level and kept for other characters")
copy_dd = [i for i in lua2.eval("__settingsRows()").values() if i.kind == "dropdown" and i.key == "copyFrom"]
check(copy_dd and copy_dd[0].options[1].label == "No other characters yet", "copy list says when there is no one to copy")
lua2.execute("SmoothExperienceBarDB.profiles['Alt - Mockrealm'] = { theme = 'frost', width = 640, glass = false, lightning = false, "
             "defaultCentre = 'xpHour', defaultRight = 'bogus' }")
lua2.execute("__settings.copyFrom:SetValue('Alt - Mockrealm')")
button = [i for i in lua2.eval("__settingsRows()").values() if i.kind == "button" and i.name == "Copy Settings"]
check(bool(button), "copy button on the settings page")
button[0].onClick()
for _ in range(30):
    G2.__step(1 / 60)
check(mine.theme == "frost" and mine.width == 640 and not mine.glass and not mine.lightning,
      "copying another character's profile replaces this character's settings")
check(G2.SmoothExperienceBarFrame.w == 640, "copied size applied to the bar")
check(mine.defaultCentre == "xpHour" and mine.defaultRight == "none",
      "copied text choices kept, and one the addon does not know goes back to the default")
check(G2.__settings.theme.GetValue(G2.__settings.theme) == "frost", "settings page shows the copied values")

# Another character on an account that has had the wizard: no wizard.
lua3 = LuaRuntime(unpack_returned_tuples=True)
lua3.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
lua3.execute("SmoothExperienceBarDB = { setupOffered = true, profiles = { ['Alt - Mockrealm'] = { theme = 'fel' } } }")
lua3.globals().__loadAddon(ADDON.replace("\\", "/"), "SmoothExperienceBar")
lua3.execute("__fire('ADDON_LOADED', 'SmoothExperienceBar'); __fire('PLAYER_ENTERING_WORLD', true, false)")
for _ in range(240):
    lua3.globals().__step(1 / 60)
check(lua3.eval("SmoothExperienceBarSetup") is None
      and lua3.eval("SmoothExperienceBarDB.profiles['Testchar - Mockrealm'].setupPending") is None,
      "the wizard is offered once per account: not again on another character")
check(any("Copied settings from Alt - Mockrealm" in m for m in G2.__chat.values()), "copy confirmed in chat")

# Forever: characters have a surname and play under a ruleset, not a realm. Profiles saved before
# surnames were keyed by first name and server name.
def forever_session(rules, setup=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
    lua.execute("""
        __player.name, __player.surname, __player.realm = 'Hotdog', 'Hootsman', 'CAMWOW AU1 Realm 1 PvE'
        Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = ' ' } }
        Enum = { GameRule = { PvPRuleset = 1, RPRuleset = 2, HardcoreRuleset = 3 } }
        __rules = {}
        C_GameRules = { IsGameRuleActive = function(rule) return __rules[rule] == true end }
        SmoothExperienceBarDB = { setupOffered = true, profiles = {
            ['Hotdog - CAMWOW AU1 Realm 1 PvE'] = { theme = 'fel', width = 900 },
            ['Hollywood - CAMWOW AU1 Realm 1 PvE'] = { theme = 'frost' },
        } }
    """)
    for rule in rules:
        lua.execute(f"__rules[Enum.GameRule.{rule}] = true")
    lua.execute(setup)
    lua.globals().__loadAddon(ADDON.replace("\\", "/"), "SmoothExperienceBar")
    lua.execute("__fire('ADDON_LOADED', 'SmoothExperienceBar'); __fire('PLAYER_ENTERING_WORLD', true, false)")
    return lua

lua4 = forever_session([])
forever_profiles = lua4.eval("SmoothExperienceBarDB.profiles")
mine4 = forever_profiles["Hotdog Hootsman - Normal"]
check(mine4 is not None and mine4.theme == "fel" and mine4.width == 900,
      "Forever: profile keyed by first and last name and ruleset, starting from the old first-name profile")
check(forever_profiles["Hotdog - CAMWOW AU1 Realm 1 PvE"] is not None,
      "Forever: old profile kept for another character with the same first name")
copy_dd4 = [i for i in lua4.eval("__settingsRows()").values() if i.kind == "dropdown" and i.key == "copyFrom"]
check(copy_dd4 and copy_dd4[0].options[1].label == "No other characters yet",
      "Forever: old first-name profiles are left off the copy list")
lua4.execute("SmoothExperienceBarDB.profiles['Hollywood Hootsman - Normal'] = { theme = 'frost' }")
copy_dd4 = [i for i in lua4.eval("__settingsRows()").values() if i.kind == "dropdown" and i.key == "copyFrom"]
labels4 = [o.label for o in copy_dd4[0].options.values()]
check(labels4 == ["Hollywood Hootsman - Normal"], f"Forever: copy list names other characters in full, got {labels4}")
check(lua4.eval("__settings.copyFrom:GetValue()") == "", "copy choice is empty when there is no one to copy")
# A later login: Hollywood has logged in since the update, so the old keys are already noted.
lua5 = forever_session([], """
    local db = SmoothExperienceBarDB
    db.oldKeys = { ['Hotdog - CAMWOW AU1 Realm 1 PvE'] = true, ['Hollywood - CAMWOW AU1 Realm 1 PvE'] = true }
    db.profiles['Hollywood Hootsman - Normal'] = { theme = 'frost' }
""")
check(lua5.eval("__settings.copyFrom:GetValue()") == "Hollywood Hootsman - Normal",
      "copy choice starts on the first other character, not a value outside the list")
for rules, label in ((["PvPRuleset"], "PVP"), (["RPRuleset"], "RP"), (["RPRuleset", "PvPRuleset"], "RP-PVP"),
                     (["HardcoreRuleset"], "Hardcore")):
    key = "Hotdog Hootsman - " + label
    check(forever_session(rules).eval(f"SmoothExperienceBarDB.profiles['{key}']") is not None,
          f"Forever: {label} ruleset names the profile")

print("== what's new (the in-game changelog)")
sys.path.insert(0, os.path.join(HERE, ".."))
import whatsnew_data  # noqa: E402

SAMPLE = """# Changelog

Notes for players.

## 1.2.0

### New
- **A feature**: the window shows
  this under its title.
- A `/seb` thing on **two**
  lines.

### Fixed
- One fix.

## 1.1.0

### New
- Older.

## Unreleased draft
- not a version
"""
parsed = whatsnew_data.parse(SAMPLE)
check([v["version"] for v in parsed] == ["1.2.0", "1.1.0"]
      and parsed[0]["sections"] == [("New", [("A feature", "The window shows this under its title."),
                                            "A /seb thing on two lines."]), ("Fixed", ["One fix."])]
      and parsed[1]["sections"] == [("New", ["Older."])],
      "whatsnew_data.py reads the changelog's versions and notes as players read them, Markdown marks dropped")
check(whatsnew_data.for_release(parsed, "1.1.0")[0]["version"] == "1.1.0"
      and whatsnew_data.for_release(parsed, "1.3.0") is None,
      "for a release it leaves out later versions, and has nothing for a version without a section")
real = whatsnew_data.parse(open(os.path.join(HERE, "..", "..", "CHANGELOG.md"), encoding="utf-8").read())
DATA = whatsnew_data.lua(real)
KNOWN = "{ setupOffered = true, profiles = { ['Testchar - Mockrealm'] = {} }%s }"


def wn_session(saved, version, data=DATA):
    """A fresh client: saved is SmoothExperienceBarDB (nil for a new account), version the toc's, data the notes."""
    w = LuaRuntime(unpack_returned_tuples=True)
    w.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
    w.execute(f"SmoothExperienceBarDB = {saved}; __addonVersion = {version!r}")
    w.globals().__ns = w.globals().__loadAddon(ADDON.replace("\\", "/"), "SmoothExperienceBar")
    w.globals().__wnd = data
    # As the build's WhatsNewData.lua, whatever one is on this disk.
    w.execute("__ns.WhatsNewData = nil; if __wnd then assert(loadstring(__wnd))(nil, __ns) end")
    w.execute("__fire('ADDON_LOADED', 'SmoothExperienceBar'); __fire('PLAYER_LOGIN'); "
              "__fire('PLAYER_ENTERING_WORLD', true, false)")
    return w


def wn_run(w, seconds):
    for _ in range(int(seconds * 60)):
        w.globals().__step(1 / 60)


def window(w):
    return w.eval("SmoothExperienceBarWhatsNew ~= nil and SmoothExperienceBarWhatsNew.shown")


def pool_texts(w, font):
    return w.eval(f"""(function()
        local out = {{}}
        for _, fs in ipairs(SmoothExperienceBarWhatsNew.pools.{font} or {{}}) do
            if fs.shown then out[#out + 1] = fs.text end
        end
        return out
    end)()""")


newest, older = real[0]["version"], real[2]["version"]

wn = wn_session(KNOWN % "", "@project-version@")
wn_run(wn, 7)
check(not window(wn) and wn.eval("SmoothExperienceBarDB.whatsNewSeen") is None, "what's new: a dev build shows nothing")

wn = wn_session("nil", newest)
wn_run(wn, 7)
check(not window(wn) and wn.eval("SmoothExperienceBarDB.whatsNewSeen") == newest,
      "what's new: a new account (the setup wizard greets it) shows nothing and notes its version quietly")

wn = wn_session(KNOWN % "", newest)
wn_run(wn, 5)
check(not window(wn) and wn.eval("SmoothExperienceBarDB.whatsNewSeen") is None,
      "what's new: an account that had the addon, updating: not yet")
wn_run(wn, 2)
check(window(wn) and wn.eval("SmoothExperienceBarWhatsNew.subtitle.text") == "Version " + newest
      and wn.eval("SmoothExperienceBarDB.whatsNewSeen") == newest,
      "what's new: then, six seconds after login, this version's notes, noted as seen once shown")
check(not wn.eval("SmoothExperienceBarSetup and SmoothExperienceBarSetup.shown"),
      "what's new: and not the setup wizard as well")

wn = wn_session(KNOWN % f", whatsNewSeen = {older!r}", newest)
wn_run(wn, 7)
heads = list(pool_texts(wn, "GameFontHighlightLarge").values())
notes = len(pool_texts(wn, "GameFontHighlight"))
want = sum(len(n) for v in real[:2] for _, n in v["sections"])
check(heads == [real[0]["version"], real[1]["version"]] and notes == want,
      f"what's new: updating from {older}, every version since, newest first, each note ({heads}, {notes} notes)")
def titled(v):
    return [n[0] for _, ns_ in v["sections"] for n in ns_ if isinstance(n, tuple)]


upto = next((i for i, v in enumerate(real) if titled(v)), None)
if upto is not None:
    titles = [t for v in real[:upto + 1] for t in titled(v)]
    seen_before = real[upto + 1]["version"] if upto + 1 < len(real) else "0.0.1"
    tw = wn_session(KNOWN % f", whatsNewSeen = {seen_before!r}", newest)
    wn_run(tw, 7)
    shown_titles = set(pool_texts(tw, "GameFontNormal").values())
    check(all(t in shown_titles for t in titles),
          f"what's new: each note's title on a line of its own ({len(titles)} titles to {real[upto]['version']})")
else:
    check(True, "what's new: no titled notes in the changelog yet")

wn = wn_session(KNOWN % f", whatsNewSeen = {newest!r}", newest)
wn_run(wn, 7)
check(not window(wn), "what's new: a version already seen shows nothing")

# The setup wizard still to come (Ask Me Later): it walks through what is new, so the notes are only noted.
pending = (KNOWN % f", whatsNewSeen = {older!r}").replace("profiles = { ['Testchar - Mockrealm'] = {} }",
                                                          "profiles = { ['Testchar - Mockrealm'] = { setupPending = true, setupSnoozed = true } }")
wn = wn_session(pending, newest)
wn_run(wn, 7)
check(not window(wn) and wn.eval("SmoothExperienceBarDB.whatsNewSeen") == newest,
      "what's new: with the setup wizard still to come, nothing shows and the notes are noted as seen")

wn = wn_session(KNOWN % f", whatsNewSeen = {older!r}", newest)
wn.execute("__combat = true")
wn_run(wn, 7)
check(not window(wn) and wn.eval("SmoothExperienceBarDB.whatsNewSeen") == older, "what's new: never in combat, it waits")
wn.execute("__combat = false; __fire('PLAYER_REGEN_ENABLED')")
check(window(wn) and wn.eval("SmoothExperienceBarDB.whatsNewSeen") == newest, "what's new: and shows once combat ends")
wn.execute("SmoothExperienceBarWhatsNew:Hide(); SlashCmdList.SMOOTHEXPERIENCEBAR('changes')")
check(window(wn), "what's new: /seb changes opens it again")
wn.execute("""(function()
    for _, f in ipairs(__frames) do
        if f.parent == SmoothExperienceBarWhatsNew and f.text == "Open Settings" then f.scripts.OnClick(f) end
    end
end)()""")
check(not window(wn) and wn.eval("__openedCategory") == "Smooth Experience Bar",
      "what's new: Open Settings closes it and opens the settings")
wn_button = [i for i in wn.eval("__settingsRows()").values() if i.kind == "button" and i.name == "What's New"]
check(len(wn_button) == 1, "what's new: a What's New button on the settings page")
wn_button[0].onClick()
check(window(wn), "what's new: which opens it")
many = [{"version": f"1.{i}.0", "sections": [("New", ["x"])]} for i in range(12, 0, -1)]
wn.globals().__many = whatsnew_data.lua(many)
wn.execute("assert(loadstring(__many))(nil, __ns)")
check(wn.eval("#__ns.WhatsNew.Unseen(__ns.WhatsNewData, '1.12.0', '0.1.0')") == 8
      and wn.eval("__ns.WhatsNew.Unseen(__ns.WhatsNewData, '1.12.0', '0.1.0').cut"),
      "what's new: at most eight versions, then a line pointing to the release notes")
copy = wn_session("{ setupOffered = true, profiles = { ['Testchar - Mockrealm'] = {}, ['Other - Realm'] = "
                  "{ separateTracks = 'sideways', repTheme = 'nope', repCentre = 'gone', repLeft = 'standing' } } }",
                  newest)
copy.execute("__ns.Core.CopyProfile('Other - Realm')")
check(copy.eval("__settings.separateTracks:GetValue()") == "xp" and copy.eval("__settings.repTheme:GetValue()") == "standing"
      and copy.eval("__settings.repCentre:GetValue()") == "value" and copy.eval("__settings.repLeft:GetValue()") == "standing",
      "copying a profile: reputation settings not known go back to their defaults, the rest are copied")
nodata = wn_session(KNOWN % "", newest, None)
nodata.execute("__chat = {}; SlashCmdList.SMOOTHEXPERIENCEBAR('changes')")
check(any("no changelog" in m for m in nodata.eval("__chat").values()),
      "what's new: a dev install without notes says how to make them")

if failures:
    print(f"\n{len(failures)} check(s) failed:")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("\nok")
