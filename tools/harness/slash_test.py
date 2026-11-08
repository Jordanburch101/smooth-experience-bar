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
check(wiz().page == "place" and wui.step.text == "Step 1 of 4", "wizard: Set it up goes to where the bar goes")
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
click(cards.text.none)
check(wiz().page == "text" and cards.text.none.radio.checked, "wizard: text picked")
click(wui.next)
summary = wiz().pages.done.summary.text
check(wiz().page == "done" and "Bar: Both" in summary and "Theme: Fel" in summary and "Effects: Calm" in summary
      and "Text: Just the bar" in summary, f"wizard: summary of the picks ({summary})")
check(wui.next.text == "Finish", "wizard: last step finishes")
click(wui.next, 1)
mine = G.SmoothExperienceBarDB.profiles["Testchar - Mockrealm"]
check(not st.frame.shown and mine.setupPending is None, "wizard: Finish closes it for good")
check(mine.showBar and mine.skinDefaultBar and mine.theme == "fel" and not mine.waves and not mine.lightning
      and not mine.showLevelTime and not mine.showQuestRested,
      "wizard: the picks are applied")
check(G.__settings.theme.GetValue(G.__settings.theme) == "fel", "wizard: applied through the settings controls")
check("204,931" in step("wizard closed", None, 1), "wizard: its XP previews stop and the bar is back to live XP")

lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('setup')")
run(0.2)
check(st.frame.shown and wiz().choice.place == "both" and wiz().choice.effects == "calm" and wiz().choice.text == "none",
      "/seb setup opens it again, starting from the current settings")
click(wui.start)
click(cards.place.default)
click(wui.next)
click(wui.next)
click(wui.next)
check(wiz().page == "done" and "Text:" not in wiz().pages.done.summary.text,
      "wizard: no text step when only the game's bar is used")
click(wui.back)
check(wui.step.text == "Step 3 of 3", f"wizard: step count follows ({wui.step.text})")
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
    for _, k in ipairs({ "showBar", "skinDefaultBar", "theme", "waves", "swirl", "bubbles", "sparkles", "ambient",
                         "lightning", "restedGlow", "glass", "rounding", "flash", "showLevelTime", "showSessionTime",
                         "showXPHour", "showQuestRested" }) do
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
check(sum(1 for i in items if i.kind == "button") == 8, "eight buttons")
setting_count = lua.eval("function() local n = 0 for _ in pairs(__settings) do n = n + 1 end return n end")()
check(sum(1 for i in items if i.kind in ("checkbox", "slider", "dropdown")) == setting_count == 29,
      "a row for every setting")
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
for key in ["showLevelTime", "showSessionTime", "showXPHour", "showQuestRested", "waves", "swirl", "bubbles",
            "sparkles", "ambient", "lightning", "restedGlow", "flash", "glass", "rounding", "segments", "fontOutline", "locked", "hideBlizzardBar", "showBar", "skinDefaultBar", "resetOnReload", "showMaxLevel"]:
    default = G.__settings[key].GetValue(G.__settings[key])
    lua.execute(f"__settings[{key!r}]:SetValue({str(not default).lower()})")
    step(f"{key}={not default}", "SlashCmdList.SMOOTHEXPERIENCEBAR('test')", 1)
    lua.execute(f"__settings[{key!r}]:SetValue({str(default).lower()})")
lua.execute("__settings.showLevelTime:SetValue(false)")
check("Time this level" not in step("showLevelTime off", None, 0.2), "text line can be hidden")
lua.execute("__settings.showLevelTime:SetValue(true)")
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
# next to the separate bar or instead of it (Show Separate Bar).
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
lua.execute("__settings.showBar:SetValue(false)")
check(not bar.shown and skin.shown, "separate bar off: only the default bar's shown")
check(skin_texts() == "204,931 / 311,490 (106,559) | left: Time this level: 6m",
      f"default bar only: still no lines around it ({skin_texts()})")
lua.execute("__settings.showLevelTime:SetValue(false)")
check("left: Level 57" in skin_texts(), "Time This Level off: the default bar shows the level instead")
lua.execute("__settings.showLevelTime:SetValue(true)")
check("left: Time this level" in skin_texts(), "Time This Level back on: the default bar shows it again")
slash("test", 4)
check("229,850" in skin_texts(), "default bar only: still animates with the separate bar hidden")
slash("test off", 2)
lua.execute("__xpBar.StatusBar:SetSize(700, 15)")
run(1.5)
check((skin.w, skin.h) == (700, 15), "skin: follows the XP bar's size")
lua.execute("__settings.hideBlizzardBar:SetValue(true)")
check(containers[1].shown, "skin: the default bar is not hidden while drawn over")
lua.execute("__settings.hideBlizzardBar:SetValue(false)")
lua.execute("__settings.showBar:SetValue(true)")
check(bar.shown and line(bar, "Leveling in").anchors == "LEFT BOTTOMLEFT 0 -18",
      "separate bar back: its lines under it as before")
step("setting off", "__settings.skinDefaultBar:SetValue(false)", 0.2)
check(not skin.shown and bar.shown and (bar.w, bar.h) == (600, 30), "skin off: only the separate bar, as it was")

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

print("== max level")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('test off'); __player.level = 70; __player.xp = 0")
check(step("showMaxLevel off", "__fire('PLAYER_XP_UPDATE', 'player')").startswith("[hidden]"), "hidden at max level")
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
lua2.execute("SmoothExperienceBarDB = { theme = 'fel', width = 820, glass = true, layout = 2, point = { 'TOP', 'UIParent', 'TOP', 0, -90 } }")
G2 = lua2.globals()
G2.__loadAddon(ADDON.replace("\\", "/"), "SmoothExperienceBar")
lua2.execute("__fire('ADDON_LOADED', 'SmoothExperienceBar'); __fire('PLAYER_ENTERING_WORLD', true, false)")
mine = lua2.eval("SmoothExperienceBarDB.profiles['Testchar - Mockrealm']")
check(mine is not None and mine.theme == "fel" and mine.width == 820 and mine.glass,
      "old account-wide settings carried into this character's profile")
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
lua2.execute("SmoothExperienceBarDB.profiles['Alt - Mockrealm'] = { theme = 'frost', width = 640, glass = false, lightning = false }")
lua2.execute("__settings.copyFrom:SetValue('Alt - Mockrealm')")
button = [i for i in lua2.eval("__settingsRows()").values() if i.kind == "button" and i.name == "Copy Settings"]
check(bool(button), "copy button on the settings page")
button[0].onClick()
for _ in range(30):
    G2.__step(1 / 60)
check(mine.theme == "frost" and mine.width == 640 and not mine.glass and not mine.lightning,
      "copying another character's profile replaces this character's settings")
check(G2.SmoothExperienceBarFrame.w == 640, "copied size applied to the bar")
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

if failures:
    print(f"\n{len(failures)} check(s) failed:")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("\nok")
