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

state = lua.eval("""function()
    local t = {}
    for _, r in ipairs(__regions) do
        if r.kind == "FontString" and r.text and r.text ~= "" and r.shown then t[#t + 1] = r.text end
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

print("== settings page")
layout = G.__settingsLayout
items = [layout[i + 1] for i in range(len(layout))]
for item in items:
    print(f"  {item.kind:9} {item.key or item.name or item.text}")
check(G.__settingsCategory.name == "Smooth Experience Bar", "category registered")
check(any(i.kind == "dropdown" and i.key == "theme" for i in items), "theme dropdown")
check(sum(1 for i in items if i.kind == "button") == 6, "six buttons")

print("== slash commands")
lua.execute("__openedCategory = nil")
slash("")
check(G.__openedCategory == "Smooth Experience Bar", "/seb opens settings")
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
            "sparkles", "ambient", "restedGlow", "flash", "locked", "hideBlizzardBar", "resetOnReload", "showMaxLevel"]:
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

print("== preview buttons")
for item in items:
    if item.kind == "button":
        item.onClick()
        step(f"button: {item.name}", None, 2)

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
db = G.SmoothExperienceBarDB
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
    }
    C_QuestLog.GetNumQuestLogEntries = function() return #log end
    C_QuestLog.GetInfo = function(i) return log[i] end
    C_QuestLog.IsComplete = function(id) for _, q in ipairs(log) do if q.questID == id then return q.done end end end
    C_QuestLog.ReadyForTurnIn = function(id) for _, q in ipairs(log) do if q.questID == id then return q.ready end end end
    GetQuestLogRewardXP = function(id) for _, q in ipairs(log) do if q.questID == id then return q.xp end end return 0 end
    __fire('QUEST_LOG_UPDATE')
""")
check("|cFFFF97004.8%" in step("modern quest log", None, 2), "modern quest log: done and ready quests counted")

print("== max level")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('test off'); __player.level = 70; __player.xp = 0")
check(step("showMaxLevel off", "__fire('PLAYER_XP_UPDATE', 'player')").startswith("[hidden]"), "hidden at max level")
check("Max Level" in step("showMaxLevel on", "__settings.showMaxLevel:SetValue(true)"), "full bar at max level")

if failures:
    print(f"\n{len(failures)} check(s) failed:")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("\nok")
