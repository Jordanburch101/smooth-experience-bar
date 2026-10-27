"""Exercise slash commands, every setting and the settings page buttons against the mock.

Any Lua error aborts with a traceback; otherwise prints what each step left on the bar.
"""
import os
import sys

from lupa.luajit21 import LuaRuntime

ADDON = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))

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
    print(f"{label:28} -> {state()}")


print("== settings page")
layout = G.__settingsLayout
for i in range(len(layout)):
    item = layout[i + 1]
    print(f"  {item.kind:9} {item.key or item.name or item.text}")
print("  category:", G.__settingsCategory.name)

print("== slash commands")
for cmd in ["", "help", "test", "test 20000", "test quest", "test turnin", "test rested", "test level",
            "test multi", "test off", "unlock", "lock", "reset", "session"]:
    step(f"/seb {cmd}", f"SlashCmdList.SMOOTHEXPERIENCEBAR({cmd!r})")
print("  opened settings:", G.__openedCategory)

print("== every setting toggled off and back on")
for key in ["showLevelTime", "showSessionTime", "showXPHour", "showQuestRested", "waves", "swirl",
            "bubbles", "sparkles", "flash", "locked", "hideBlizzardBar", "resetOnReload", "showMaxLevel"]:
    default = G.__settings[key].GetValue(G.__settings[key])
    lua.execute(f"__settings[{key!r}]:SetValue({str(not default).lower()})")
    step(f"{key}={not default}", "SlashCmdList.SMOOTHEXPERIENCEBAR('test')", 1)
    lua.execute(f"__settings[{key!r}]:SetValue({str(default).lower()})")
lua.execute("__settings.hideBlizzardBar:SetValue(true)")
print("  blizzard bar hidden:", not G.MainMenuExpBar.shown)
lua.execute("MainMenuExpBar:Show()")
print("  stays hidden after Show():", not G.MainMenuExpBar.shown)
lua.execute("__settings.hideBlizzardBar:SetValue(false)")
print("  restored:", G.MainMenuExpBar.shown)
for key, value in [("scale", 1.2), ("speed", 0.5), ("speed", 2)]:
    lua.execute(f"__settings[{key!r}]:SetValue({value})")
    step(f"{key}={value}", "SlashCmdList.SMOOTHEXPERIENCEBAR('test level')", 2)
print("  bar scale:", G.SmoothExperienceBarFrame.scale)

print("== themes")
lua.execute("""
    local ns = ...
""")
ns.Themes.Register("test", lua.eval("{ name = 'Test', fillA = {0, 1, 0}, questText = '00FF00' }"))
lua.execute("__settings.theme:SetValue('test')")
step("theme=test", "SlashCmdList.SMOOTHEXPERIENCEBAR('test quest')", 2)
print("  fallback field (rested) from default:", list(ns.Themes.Get("test").rested.values()))
lua.execute("__settings.theme:SetValue('luxthos')")

print("== preview buttons")
for i in range(len(layout)):
    item = layout[i + 1]
    if item.kind == "button":
        item.onClick()
        step(f"button: {item.name}", None, 2)

print("== mouse, lock and resize")
bar = G.SmoothExperienceBarFrame
lua.execute("__openedCategory = nil; SmoothExperienceBarFrame.scripts.OnMouseUp(SmoothExperienceBarFrame, 'RightButton')")
print("  right-click while locked opens settings:", G.__openedCategory, "| mouse enabled:", bar.mouse)
lua.execute("__openedCategory = nil; __combat = true; SmoothExperienceBarFrame.scripts.OnMouseUp(SmoothExperienceBarFrame, 'RightButton')")
print("  in combat, opened:", G.__openedCategory)
lua.execute("__combat = false; __fire('PLAYER_REGEN_ENABLED')")
print("  after combat, opened:", G.__openedCategory)

lua.execute("SmoothExperienceBarFrame.scripts.OnEnter(SmoothExperienceBarFrame)")
print("  tooltip while locked:", G.GameTooltip.shown)
lua.execute("__settings.locked:SetValue(false); SmoothExperienceBarFrame.scripts.OnEnter(SmoothExperienceBarFrame)")
print("  tooltip while unlocked:", [G.GameTooltip.lines[i + 1] for i in range(len(G.GameTooltip.lines))])

grip = lua.eval("""function()
    for _, r in ipairs(__regions) do if r.scripts.OnMouseDown then return r end end
end""")()
print("  grip visible while unlocked:", grip.parent.shown)
grip.scripts.OnMouseDown(grip, "LeftButton")
print("  sizing from:", bar.sizing, "| anchored:", bar.GetPoint(bar)[0])
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
fonts = lua.eval("""function()
    local t = {}
    for _, r in ipairs(__regions) do if r.kind == "FontString" then t[#t + 1] = r.fontSize end end
    return table.concat(t, ",")
end""")()
step("after resize to 900x45", None, 1)
print("  saved size:", G.SmoothExperienceBarDB.width, G.SmoothExperienceBarDB.height,
      "| liquid slice height:", row_h, "| font sizes:", fonts)
lua.execute("__settings.width:SetValue(50); __settings.height:SetValue(500)")
print("  out-of-range width/height clamped to:", G.SmoothExperienceBarDB.width, G.SmoothExperienceBarDB.height)
lua.execute("__settings.locked:SetValue(true)")
print("  grip hidden after lock:", not grip.parent.shown)
lua.execute("ns_reset = nil")
for i in range(len(layout)):
    item = layout[i + 1]
    if item.kind == "button" and item.name.startswith("Reset Position"):
        item.onClick()
print("  after reset:", G.SmoothExperienceBarDB.width, G.SmoothExperienceBarDB.height, G.SmoothExperienceBarDB.scale,
      list(G.SmoothExperienceBarDB.point.values()))

print("== max level")
lua.execute("SlashCmdList.SMOOTHEXPERIENCEBAR('test off'); __player.level = 70; __player.xp = 0")
step("level 70, showMaxLevel off", "__fire('PLAYER_XP_UPDATE', 'player')")
step("level 70, showMaxLevel on", "__settings.showMaxLevel:SetValue(true)")
print("ok")
