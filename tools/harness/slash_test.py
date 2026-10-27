"""Run every /seb command against the mock and report Lua errors."""
import os
import sys

from lupa.luajit21 import LuaRuntime

ADDON = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
G = lua.globals()
ns = lua.table()
for f in ("Liquid.lua", "SmoothExperienceBar.lua"):
    G.__load(os.path.join(ADDON, f).replace("\\", "/"), "SmoothExperienceBar", ns)
lua.execute("__fire('ADDON_LOADED', 'SmoothExperienceBar'); __fire('PLAYER_ENTERING_WORLD', true, false)")

for cmd in ["", "test", "test 20000", "test quest", "test turnin", "test rested", "test level",
            "test multi", "test off", "unlock", "lock", "reset", "session"]:
    G.SlashCmdList.SMOOTHEXPERIENCEBAR(cmd)
    for _ in range(240):
        G.__step(1 / 60)
    texts = lua.eval("""function()
        local t = {}
        for _, r in ipairs(__regions) do if r.kind == "FontString" and r.text then t[#t + 1] = r.text end end
        return table.concat(t, " | ", 1, 3)
    end""")()
    print(f"{cmd or '(help)':12} -> {texts}")
