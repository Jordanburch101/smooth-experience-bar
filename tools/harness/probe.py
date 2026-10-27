"""Print live particle counts for a theme, to debug effects.

Usage: python probe.py <addon dir> <theme> [seconds]
"""
import os
import sys

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # some builds of lupa ship without LuaJIT
    from lupa.lua51 import LuaRuntime

ADDON, THEME = sys.argv[1], sys.argv[2]
SECONDS = float(sys.argv[3]) if len(sys.argv) > 3 else 3
HERE = os.path.dirname(os.path.abspath(__file__))

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
G = lua.globals()
G.__loadAddon(ADDON.replace("\\", "/"), "SmoothExperienceBar")
lua.execute(f"__fire('ADDON_LOADED', 'SmoothExperienceBar'); __settings.theme:SetValue({THEME!r}); "
            "__fire('PLAYER_ENTERING_WORLD', true, false)")

count = lua.eval("""function()
    local motes, ambient, shown, alpha = 0, 0, 0, 0
    for _, r in ipairs(__regions) do
        if r.kind == "Texture" and r.layer == "OVERLAY" and r.sub == 4 and r.shown then
            shown = shown + 1
            alpha = alpha + r.alpha
        end
    end
    return shown, alpha
end""")
for step in range(int(SECONDS * 60)):
    G.__step(1 / 60)
    if step % 30 == 29:
        shown, alpha = count()
        print(f"t={(step + 1) / 60:4.1f}s  visible motes={shown:3d}  mean alpha={alpha / max(1, shown):.2f}")

print(lua.eval("""function()
    local out = {}
    for _, r in ipairs(__regions) do
        if r.kind == "Texture" and r.layer == "OVERLAY" and r.sub == 4 and r.shown and #out < 6 then
            local l, t, w = r:Rect()
            out[#out + 1] = string.format("  %s blend=%s alpha=%.2f size=%.1f at=(%.0f,%.0f) colour=%.2f,%.2f,%.2f",
                tostring(r.file):match("[^\\\\]+$"), r.blend, r.alpha, w, l, t, r.vc[1], r.vc[2], r.vc[3])
        end
    end
    return table.concat(out, "\\n")
end""")())
