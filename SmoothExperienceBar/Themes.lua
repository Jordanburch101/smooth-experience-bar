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

Themes.Register("fel", {
    name = "Fel",
    fillA      = { 0.10, 0.42, 0.06 },
    fillB      = { 0.55, 1.00, 0.15 },
    lead       = { 0.85, 1.00, 0.70, 0.25 },
    flash      = { 0.50, 1.00, 0.30 },
    tip        = { 0.90, 1.00, 0.80 },
    glow       = { 0.50, 1.00, 0.30 },
    swirlA     = { 0.70, 1.00, 0.40 },
    swirlB     = { 0.30, 1.00, 0.60 },
    bubble     = { 0.85, 1.00, 0.80 },
    splashFrom = { 0.80, 1.00, 0.50 },
    splashTo   = { 0.30, 1.00, 0.20 },
    absorbTo   = { 0.50, 1.00, 0.30 },
    levelFrom  = { 0.95, 1.00, 0.85 },
    levelTo    = { 0.40, 1.00, 0.20 },
})

Themes.Register("frost", {
    name = "Frost",
    fillA      = { 0.10, 0.32, 0.85 },
    fillB      = { 0.45, 0.90, 1.00 },
    lead       = { 0.85, 0.95, 1.00, 0.25 },
    rested     = { 0.62, 0.40, 1.00, 0.55 }, -- purple so it stands apart from the icy fill
    restedText = "9E66FF",
    flash      = { 0.60, 0.85, 1.00 },
    tip        = { 0.90, 1.00, 1.00 },
    glow       = { 0.60, 0.90, 1.00 },
    swirlA     = { 0.80, 0.95, 1.00 },
    swirlB     = { 0.50, 0.80, 1.00 },
    splashFrom = { 0.85, 0.95, 1.00 },
    splashTo   = { 0.40, 0.80, 1.00 },
    absorbTo   = { 0.60, 0.90, 1.00 },
    levelFrom  = { 1.00, 1.00, 1.00 },
    levelTo    = { 0.50, 0.85, 1.00 },
})

Themes.Register("holy", {
    name = "Holy",
    fillA      = { 0.80, 0.50, 0.08 },
    fillB      = { 1.00, 0.92, 0.45 },
    lead       = { 1.00, 1.00, 0.85, 0.25 },
    quest      = { 1.00, 0.38, 0.12, 1.00 }, -- redder orange so it reads against gold
    questText  = "FF6120",
    flash      = { 1.00, 0.90, 0.50 },
    tip        = { 1.00, 1.00, 0.90 },
    glow       = { 1.00, 0.90, 0.50 },
    swirlA     = { 1.00, 0.95, 0.70 },
    swirlB     = { 1.00, 0.85, 0.50 },
    bubble     = { 1.00, 1.00, 0.90 },
    splashFrom = { 1.00, 0.95, 0.70 },
    splashTo   = { 1.00, 0.80, 0.30 },
    absorbTo   = { 1.00, 0.85, 0.40 },
    levelFrom  = { 1.00, 1.00, 0.90 },
    levelTo    = { 1.00, 0.80, 0.30 },
})

Themes.Register("void", {
    name = "Void",
    fillA      = { 0.16, 0.04, 0.32 },
    fillB      = { 0.55, 0.25, 0.95 },
    bg         = { 0, 0, 0, 0.6 },
    lead       = { 0.75, 0.60, 1.00, 0.25 },
    flash      = { 0.50, 0.25, 1.00 },
    tip        = { 0.85, 0.70, 1.00 },
    glow       = { 0.60, 0.30, 1.00 },
    swirlA     = { 0.75, 0.50, 1.00 },
    swirlB     = { 0.40, 0.30, 1.00 },
    bubble     = { 0.80, 0.70, 1.00 },
    splashFrom = { 0.70, 0.50, 1.00 },
    splashTo   = { 0.35, 0.15, 0.80 },
    absorbTo   = { 0.55, 0.30, 1.00 },
    levelFrom  = { 0.85, 0.70, 1.00 },
    levelTo    = { 0.40, 0.15, 0.90 },
})

Themes.Register("blood", {
    name = "Blood",
    fillA      = { 0.38, 0.02, 0.05 },
    fillB      = { 0.95, 0.15, 0.15 },
    lead       = { 1.00, 0.75, 0.75, 0.25 },
    flash      = { 1.00, 0.30, 0.30 },
    tip        = { 1.00, 0.80, 0.80 },
    glow       = { 1.00, 0.30, 0.30 },
    swirlA     = { 1.00, 0.50, 0.50 },
    swirlB     = { 1.00, 0.30, 0.40 },
    bubble     = { 1.00, 0.85, 0.85 },
    splashFrom = { 1.00, 0.60, 0.60 },
    splashTo   = { 0.90, 0.15, 0.20 },
    absorbTo   = { 1.00, 0.30, 0.30 },
    levelFrom  = { 1.00, 0.85, 0.85 },
    levelTo    = { 0.90, 0.20, 0.20 },
})
