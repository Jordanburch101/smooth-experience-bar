-- Bar themes. A theme only needs the fields it changes; anything missing falls back to the
-- default theme. Colours are { r, g, b [, a] } in 0..1, text colours are "RRGGBB" hex.

local _, ns = ...

local Themes = { list = {}, order = {}, default = "luxthos" }
ns.Themes = Themes

function Themes.Register(key, theme)
    theme.key = key
    if key ~= Themes.default then
        setmetatable(theme, { __index = Themes.list[Themes.default] })
    end
    Themes.list[key] = theme
    Themes.order[#Themes.order + 1] = key
end

function Themes.Get(key)
    return Themes.list[key] or Themes.list[Themes.default]
end

Themes.Register("luxthos", {
    name = "Luxthos",

    -- Bar
    fillA  = { 0.337, 0.388, 1.000 },       -- left edge of the fill gradient
    fillB  = { 0.776, 0.380, 1.000 },       -- colour at the liquid front
    lead   = { 0.920, 0.860, 1.000, 0.25 }, -- incoming XP the liquid is about to flow into
    quest  = { 1.000, 0.592, 0.000, 1.00 }, -- completed quest XP
    rested = { 0.310, 0.565, 1.000, 0.545 },
    bg     = { 0, 0, 0, 0.5 },
    flash  = { 0.75, 0.60, 1.00 },          -- level-up flash (additive)

    -- Text
    questText  = "FF9700",
    restedText = "4F90FF",

    -- Liquid
    tip        = { 1.00, 0.92, 1.00 },      -- bright line along the liquid front
    glow       = { 0.85, 0.70, 1.00 },      -- glow around the front
    swirlA     = { 0.85, 0.72, 1.00 },      -- magic veins, two layers
    swirlB     = { 0.55, 0.85, 1.00 },
    bubble     = { 1.00, 1.00, 1.00 },
    splashFrom = { 0.90, 0.75, 1.00 },      -- motes from XP gains fade between these
    splashTo   = { 1.00, 0.55, 0.95 },
    absorbTo   = { 0.80, 0.50, 1.00 },      -- quest turn-in motes start at `quest` and end here
    levelFrom  = { 1.00, 0.95, 1.00 },      -- level-up burst
    levelTo    = { 0.75, 0.50, 1.00 },
})
