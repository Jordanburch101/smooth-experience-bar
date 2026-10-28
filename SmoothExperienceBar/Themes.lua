-- Bar themes. A theme only needs the fields it changes; anything missing falls back to the
-- default theme. Colours are { r, g, b [, a] } in 0..1, text colours are "RRGGBB" hex.
--
-- Besides colours a theme can set (see Liquid.lua for the defaults):
--   physics   = { amplitude, stiffness, damping, coupling, slosh, ambient }  how the liquid moves
--   fillSpeed = multiplier on how fast the liquid flows to a new level
--   swirl     = { texture, flow = { u, v }, alpha, pulse, pulseRate }      the veins inside
--   clouds    = { texture, dark, light, scale }                           slow clouds behind the veins
--   core      = { alpha, pulseRate }                                      glow through the middle (glow colour)
--   bubbles   = { texture, blend, rate, energyRate, rise, size, alpha }
--   burst     = { texture, blend, mode = "throw" | "attract", buoyancy, drag, spin, twinkle }
--   ambient   = { { area, rate, energyRate, texture, blend, size, life, vx, vy, buoyancy, drag,
--                   spin, twinkle, grow, alpha, from, to }, ... }          continuous particles
--   Resolve(self)          -> theme   pick colours once the player is known (class, faction)
--   Colors(self, t, frac)  -> fillA, fillB, accent   animate colours every frame

local _, ns = ...

local sqrt, floor = math.sqrt, math.floor

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

--------------------------------------------------------------------------------
-- Colour helpers
--------------------------------------------------------------------------------

local WHITE = { 1, 1, 1 }
local DEFAULT_QUEST = { 1.000, 0.592, 0.000 }
local DEFAULT_RESTED = { 0.310, 0.565, 1.000 }
-- Swapped in when a theme's fill is too close to the usual quest orange or rested blue.
local ALT_QUEST, ALT_QUEST_TEXT = { 1.00, 0.88, 0.25, 1.00 }, "FFE040"
local ALT_RESTED, ALT_RESTED_TEXT = { 0.62, 0.40, 1.00, 0.55 }, "9E66FF"

local function Mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function Scale(c, k)
    return { c[1] * k, c[2] * k, c[3] * k }
end

local function Dist(a, b)
    return sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local function HSV(h, s, v)
    h = (h % 1) * 6
    local i = floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v end
    return v, p, q
end

-- A full colour set built from one base colour, for class and similar themes.
local function FromColor(c, template)
    local t = {
        fillA = Scale(c, 0.42), fillB = Mix(c, WHITE, 0.15),
        lead = Mix(c, WHITE, 0.8), flash = Mix(c, WHITE, 0.3),
        tip = Mix(c, WHITE, 0.75), glow = Mix(c, WHITE, 0.3),
        swirlA = Mix(c, WHITE, 0.55), swirlB = Mix(c, WHITE, 0.35), bubble = Mix(c, WHITE, 0.8),
        splashFrom = Mix(c, WHITE, 0.6), splashTo = c, absorbTo = Mix(c, WHITE, 0.3),
        levelFrom = Mix(c, WHITE, 0.85), levelTo = c,
    }
    t.lead[4] = 0.25
    if Dist(t.fillB, DEFAULT_RESTED) < 0.45 then t.rested, t.restedText = ALT_RESTED, ALT_RESTED_TEXT end
    if Dist(t.fillB, DEFAULT_QUEST) < 0.45 then t.quest, t.questText = ALT_QUEST, ALT_QUEST_TEXT end
    return setmetatable(t, { __index = template })
end

--------------------------------------------------------------------------------
-- Default
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Smart themes
--------------------------------------------------------------------------------

Themes.Register("class", {
    name = "Class Color",
    Resolve = function(self)
        local _, class = UnitClass("player")
        local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
        local cc = class and colors and colors[class]
        if not cc then return self end
        local c = { cc.r, cc.g, cc.b }
        if c[1] + c[2] + c[3] > 2.6 then c = Scale(c, 0.8) end -- priests: silver rather than white
        return FromColor(c, self)
    end,
})

local ALLIANCE = {
    fillA = { 0.06, 0.14, 0.48 }, fillB = { 0.25, 0.50, 1.00 },
    rested = ALT_RESTED, restedText = ALT_RESTED_TEXT,
    tip = { 1.00, 0.90, 0.55 }, glow = { 1.00, 0.85, 0.40 },
    swirlA = { 1.00, 0.85, 0.40 }, swirlB = { 0.50, 0.70, 1.00 },
    splashFrom = { 1.00, 0.92, 0.60 }, splashTo = { 1.00, 0.75, 0.25 }, absorbTo = { 1.00, 0.85, 0.40 },
    levelFrom = { 1.00, 0.95, 0.75 }, levelTo = { 0.40, 0.60, 1.00 }, flash = { 1.00, 0.85, 0.40 },
}

local HORDE = {
    fillA = { 0.30, 0.02, 0.02 }, fillB = { 0.85, 0.12, 0.08 },
    tip = { 1.00, 0.80, 0.50 }, glow = { 1.00, 0.55, 0.25 },
    swirlA = { 1.00, 0.60, 0.30 }, swirlB = { 0.70, 0.25, 0.15 },
    splashFrom = { 1.00, 0.75, 0.40 }, splashTo = { 0.90, 0.20, 0.10 }, absorbTo = { 1.00, 0.45, 0.20 },
    levelFrom = { 1.00, 0.85, 0.60 }, levelTo = { 0.85, 0.15, 0.10 }, flash = { 1.00, 0.40, 0.20 },
}

Themes.Register("faction", {
    name = "Faction",
    Resolve = function(self)
        local faction = UnitFactionGroup("player")
        local set = faction == "Alliance" and ALLIANCE or faction == "Horde" and HORDE
        if not set then return self end
        return setmetatable(set, { __index = self })
    end,
})

-- Item quality colours, in order, as the bar fills.
local QUALITY = {
    { 0.62, 0.62, 0.62 }, -- poor
    { 0.90, 0.90, 0.90 }, -- common
    { 0.12, 1.00, 0.00 }, -- uncommon
    { 0.00, 0.44, 0.87 }, -- rare
    { 0.64, 0.21, 0.93 }, -- epic
    { 1.00, 0.50, 0.00 }, -- legendary
}
local qualityA, qualityB, qualityAccent = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }

Themes.Register("quality", {
    name = "Item Quality",
    -- The legendary band is orange, so completed quests use the alternate yellow.
    quest = ALT_QUEST, questText = ALT_QUEST_TEXT,
    rested = ALT_RESTED, restedText = ALT_RESTED_TEXT,
    tip = { 1, 1, 1 }, swirlB = { 1, 1, 1 }, bubble = { 1, 1, 1 },
    Colors = function(self, t, frac)
        local n = #QUALITY
        local pos = math.min(n - 0.001, frac * n)
        local i = floor(pos) + 1
        local into = pos - (i - 1)
        -- Hold each quality for most of its band, blending into the next over the last 20%.
        local c = QUALITY[i]
        if into > 0.8 and i < n then c = Mix(c, QUALITY[i + 1], (into - 0.8) / 0.2) end
        for k = 1, 3 do
            qualityB[k] = c[k]
            qualityA[k] = c[k] * 0.4
            qualityAccent[k] = c[k] + (1 - c[k]) * 0.35
        end
        return qualityA, qualityB, qualityAccent
    end,
})

local prismA, prismB, prismAccent = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }

Themes.Register("prismatic", {
    name = "Prismatic",
    rested = ALT_RESTED, restedText = ALT_RESTED_TEXT,
    tip = { 1, 1, 1 }, swirlB = { 1, 1, 1 }, bubble = { 1, 1, 1 },
    Colors = function(self, t)
        local h = t * 0.04 -- one full cycle every 25 seconds
        prismA[1], prismA[2], prismA[3] = HSV(h, 0.85, 0.55)
        prismB[1], prismB[2], prismB[3] = HSV(h + 0.1, 0.65, 1)
        prismAccent[1], prismAccent[2], prismAccent[3] = HSV(h + 0.1, 0.4, 1)
        return prismA, prismB, prismAccent
    end,
})

--------------------------------------------------------------------------------
-- Colour themes
--------------------------------------------------------------------------------

Themes.Register("arcane", {
    name = "Arcane",
    fillA      = { 0.55, 0.10, 0.65 },
    fillB      = { 0.30, 0.85, 1.00 },
    lead       = { 0.90, 0.90, 1.00, 0.25 },
    rested     = ALT_RESTED, restedText = ALT_RESTED_TEXT,
    flash      = { 0.80, 0.60, 1.00 },
    tip        = { 0.90, 1.00, 1.00 },
    glow       = { 0.60, 0.90, 1.00 },
    swirlA     = { 1.00, 0.60, 1.00 },
    swirlB     = { 0.50, 1.00, 1.00 },
    bubble     = { 0.90, 0.90, 1.00 },
    splashFrom = { 1.00, 0.70, 1.00 },
    splashTo   = { 0.40, 0.90, 1.00 },
    absorbTo   = { 0.60, 0.80, 1.00 },
    levelFrom  = { 1.00, 1.00, 1.00 },
    levelTo    = { 0.90, 0.40, 1.00 },
    burst      = { texture = "Star", twinkle = 6 },
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

Themes.Register("ember", {
    name = "Ember",
    fillA      = { 0.50, 0.10, 0.00 },
    fillB      = { 1.00, 0.62, 0.10 },
    lead       = { 1.00, 0.90, 0.70, 0.25 },
    quest      = ALT_QUEST, questText = ALT_QUEST_TEXT,
    flash      = { 1.00, 0.60, 0.20 },
    tip        = { 1.00, 0.95, 0.70 },
    glow       = { 1.00, 0.60, 0.20 },
    swirlA     = { 1.00, 0.70, 0.30 },
    swirlB     = { 1.00, 0.45, 0.15 },
    bubble     = { 1.00, 0.85, 0.60 },
    splashFrom = { 1.00, 0.90, 0.50 },
    splashTo   = { 1.00, 0.35, 0.05 },
    absorbTo   = { 1.00, 0.60, 0.20 },
    levelFrom  = { 1.00, 0.95, 0.70 },
    levelTo    = { 1.00, 0.40, 0.05 },
    swirl      = { texture = "Heat", flow = { 0.2, -1 }, alpha = 0.8 },
    burst      = { texture = "Ember", buoyancy = 45 },
})

Themes.Register("tidal", {
    name = "Tidal",
    fillA      = { 0.00, 0.22, 0.34 },
    fillB      = { 0.10, 0.80, 0.80 },
    lead       = { 0.80, 1.00, 1.00, 0.25 },
    rested     = ALT_RESTED, restedText = ALT_RESTED_TEXT,
    flash      = { 0.50, 1.00, 1.00 },
    tip        = { 0.95, 1.00, 1.00 },
    glow       = { 0.50, 1.00, 1.00 },
    swirlA     = { 0.70, 1.00, 1.00 },
    swirlB     = { 0.40, 0.90, 1.00 },
    bubble     = { 1.00, 1.00, 1.00 },
    splashFrom = { 0.90, 1.00, 1.00 },
    splashTo   = { 0.30, 0.90, 0.90 },
    absorbTo   = { 0.50, 1.00, 1.00 },
    levelFrom  = { 1.00, 1.00, 1.00 },
    levelTo    = { 0.30, 0.90, 1.00 },
    physics    = { damping = 2.2, coupling = 1100, slosh = 0.25, ambient = 1.8 }, -- livelier waves
    swirl      = { texture = "Caustics", flow = { 1, 0.2 }, alpha = 1.2 },
    bubbles    = { rate = 1.5, energyRate = 20 },
})

Themes.Register("plague", {
    name = "Plague",
    fillA      = { 0.22, 0.28, 0.04 },
    fillB      = { 0.75, 0.85, 0.15 },
    lead       = { 0.95, 1.00, 0.70, 0.25 },
    flash      = { 0.80, 1.00, 0.30 },
    tip        = { 0.95, 1.00, 0.70 },
    glow       = { 0.80, 1.00, 0.30 },
    swirlA     = { 0.80, 1.00, 0.30 },
    swirlB     = { 0.60, 0.80, 0.20 },
    bubble     = { 0.85, 1.00, 0.45 },
    splashFrom = { 0.90, 1.00, 0.50 },
    splashTo   = { 0.50, 0.70, 0.10 },
    absorbTo   = { 0.75, 0.90, 0.20 },
    levelFrom  = { 1.00, 1.00, 0.70 },
    levelTo    = { 0.55, 0.75, 0.10 },
    swirl      = { texture = "Nebula", alpha = 1.3 },
    bubbles    = { rate = 1.2 },
})

Themes.Register("midnight", {
    name = "Midnight",
    fillA      = { 0.04, 0.06, 0.22 },
    fillB      = { 0.55, 0.62, 0.80 },
    lead       = { 0.90, 0.92, 1.00, 0.25 },
    flash      = { 0.70, 0.75, 1.00 },
    tip        = { 0.90, 0.95, 1.00 },
    glow       = { 0.70, 0.80, 1.00 },
    swirlA     = { 0.80, 0.85, 1.00 },
    swirlB     = { 0.60, 0.65, 0.90 },
    bubble     = { 0.90, 0.92, 1.00 },
    splashFrom = { 0.90, 0.95, 1.00 },
    splashTo   = { 0.60, 0.70, 1.00 },
    absorbTo   = { 0.70, 0.80, 1.00 },
    levelFrom  = { 1.00, 1.00, 1.00 },
    levelTo    = { 0.60, 0.70, 1.00 },
    swirl      = { alpha = 0.7 },
})

Themes.Register("sunset", {
    name = "Sunset",
    fillA      = { 0.62, 0.10, 0.45 },
    fillB      = { 1.00, 0.55, 0.20 },
    lead       = { 1.00, 0.90, 0.80, 0.25 },
    quest      = ALT_QUEST, questText = ALT_QUEST_TEXT,
    flash      = { 1.00, 0.55, 0.45 },
    tip        = { 1.00, 0.92, 0.80 },
    glow       = { 1.00, 0.60, 0.40 },
    swirlA     = { 1.00, 0.70, 0.60 },
    swirlB     = { 1.00, 0.50, 0.70 },
    bubble     = { 1.00, 0.92, 0.85 },
    splashFrom = { 1.00, 0.85, 0.60 },
    splashTo   = { 1.00, 0.40, 0.60 },
    absorbTo   = { 1.00, 0.55, 0.45 },
    levelFrom  = { 1.00, 0.95, 0.85 },
    levelTo    = { 1.00, 0.40, 0.50 },
})

--------------------------------------------------------------------------------
-- Outland zones
--------------------------------------------------------------------------------

Themes.Register("zangarmarsh", {
    name = "Zangarmarsh",
    fillA      = { 0.03, 0.18, 0.32 },
    fillB      = { 0.20, 0.75, 0.75 },
    lead       = { 0.80, 1.00, 0.95, 0.25 },
    rested     = ALT_RESTED, restedText = ALT_RESTED_TEXT,
    flash      = { 0.40, 1.00, 0.90 },
    tip        = { 0.85, 1.00, 0.95 },
    glow       = { 0.40, 1.00, 0.90 },
    swirlA     = { 0.50, 1.00, 0.90 },
    swirlB     = { 0.40, 0.70, 1.00 },
    bubble     = { 0.80, 1.00, 0.95 },
    splashFrom = { 0.70, 1.00, 0.90 },
    splashTo   = { 0.30, 0.80, 1.00 },
    absorbTo   = { 0.50, 1.00, 0.90 },
    levelFrom  = { 0.90, 1.00, 0.95 },
    levelTo    = { 0.30, 0.80, 1.00 },
    swirl      = { texture = "Caustics", alpha = 0.8, flow = { 0.6, 0.3 } },
    -- Glowing mushroom spores drifting in the liquid and floating up out of it.
    ambient    = {
        { area = "liquid", rate = 1.5, texture = "Glow", size = { 9, 16 }, life = { 2, 3.5 },
          vx = { -4, 4 }, vy = { 2, 8 }, buoyancy = 2, drag = 0.5, twinkle = 0.7,
          from = { 0.60, 1.00, 0.90 }, to = { 0.30, 0.80, 1.00 } },
        { area = "surface", rate = 0.6, texture = "Glow", size = { 8, 13 }, life = { 2, 3 },
          vx = { -6, 6 }, vy = { 6, 14 }, buoyancy = 2, drag = 0.4, twinkle = 0.9,
          from = { 0.60, 1.00, 0.90 }, to = { 0.40, 0.70, 1.00 } },
    },
})

Themes.Register("netherstorm", {
    name = "Netherstorm",
    fillA      = { 0.22, 0.04, 0.42 },
    fillB      = { 0.65, 0.35, 1.00 },
    lead       = { 0.85, 1.00, 0.95, 0.25 },
    flash      = { 0.40, 1.00, 0.90 },
    tip        = { 0.60, 1.00, 0.95 },
    glow       = { 0.40, 1.00, 0.90 },
    swirlA     = { 0.40, 1.00, 0.90 },
    swirlB     = { 0.60, 0.50, 1.00 },
    bubble     = { 0.70, 1.00, 0.95 },
    splashFrom = { 0.60, 1.00, 0.95 },
    splashTo   = { 0.60, 0.40, 1.00 },
    absorbTo   = { 0.40, 1.00, 0.90 },
    levelFrom  = { 0.80, 1.00, 1.00 },
    levelTo    = { 0.60, 0.40, 1.00 },
    swirl      = { texture = "Tendrils", flow = { 1.5, 0 } }, -- crackling mana arcs
    burst      = { texture = "Star", twinkle = 8 },
})

Themes.Register("hellfire", {
    name = "Hellfire",
    fillA      = { 0.28, 0.03, 0.02 },
    fillB      = { 0.85, 0.26, 0.06 },
    lead       = { 1.00, 0.85, 0.70, 0.25 },
    quest      = ALT_QUEST, questText = ALT_QUEST_TEXT,
    flash      = { 1.00, 0.50, 0.20 },
    tip        = { 1.00, 0.85, 0.60 },
    glow       = { 1.00, 0.50, 0.20 },
    swirlA     = { 1.00, 0.60, 0.30 },
    swirlB     = { 0.50, 1.00, 0.30 },
    bubble     = { 0.50, 1.00, 0.30 }, -- fel bubbles in the fire
    splashFrom = { 0.60, 1.00, 0.40 },
    splashTo   = { 0.30, 0.90, 0.20 },
    absorbTo   = { 1.00, 0.50, 0.20 },
    levelFrom  = { 1.00, 0.90, 0.70 },
    levelTo    = { 0.40, 1.00, 0.20 },
    swirl      = { texture = "Cracks", alpha = 0.6, flow = { 0.4, 0 } },
    bubbles    = { rate = 1 },
})

Themes.Register("nagrand", {
    name = "Nagrand",
    fillA      = { 0.15, 0.45, 0.15 },
    fillB      = { 0.45, 0.75, 1.00 },
    lead       = { 0.95, 1.00, 1.00, 0.25 },
    rested     = ALT_RESTED, restedText = ALT_RESTED_TEXT,
    flash      = { 0.80, 0.95, 1.00 },
    tip        = { 1.00, 1.00, 1.00 },
    glow       = { 0.80, 0.95, 1.00 },
    swirlA     = { 1.00, 1.00, 1.00 },
    swirlB     = { 0.80, 0.95, 1.00 },
    bubble     = { 1.00, 1.00, 1.00 },
    splashFrom = { 1.00, 1.00, 1.00 },
    splashTo   = { 0.50, 0.80, 1.00 },
    absorbTo   = { 0.70, 0.90, 1.00 },
    levelFrom  = { 1.00, 1.00, 1.00 },
    levelTo    = { 0.40, 0.80, 0.30 },
    swirl      = { texture = "Nebula", alpha = 0.9, flow = { 0.5, 0 } }, -- drifting clouds
})

--------------------------------------------------------------------------------
-- Effect themes: these change how the liquid moves and what it throws off
--------------------------------------------------------------------------------

Themes.Register("fire", {
    name = "Fire",
    fillA      = { 0.45, 0.05, 0.00 },
    fillB      = { 1.00, 0.55, 0.08 },
    lead       = { 1.00, 0.90, 0.60, 0.25 },
    quest      = ALT_QUEST, questText = ALT_QUEST_TEXT,
    flash      = { 1.00, 0.55, 0.15 },
    tip        = { 1.00, 0.95, 0.70 },
    glow       = { 1.00, 0.55, 0.15 },
    swirlA     = { 1.00, 0.75, 0.30 },
    swirlB     = { 1.00, 0.40, 0.05 },
    splashFrom = { 1.00, 0.90, 0.50 },
    splashTo   = { 1.00, 0.25, 0.00 },
    absorbTo   = { 1.00, 0.50, 0.10 },
    levelFrom  = { 1.00, 0.95, 0.70 },
    levelTo    = { 1.00, 0.30, 0.00 },
    -- Quick, jumpy and always flickering.
    physics    = { stiffness = 140, damping = 2.5, coupling = 1200, slosh = 0.22, ambient = 2.2 },
    fillSpeed  = 1.3,
    swirl      = { texture = "Heat", flow = { 0.1, -2.5 }, alpha = 1.3 },
    bubbles    = { rate = 0, energyRate = 0 },
    burst      = { texture = "Ember", buoyancy = 60, drag = 1.2 },
    ambient    = {
        { area = "surface", rate = 5, energyRate = 25, texture = "Ember", size = { 7, 12 }, life = { 0.6, 1.3 },
          vx = { -10, 10 }, vy = { 20, 45 }, buoyancy = 30, drag = 1, twinkle = 5,
          from = { 1.00, 0.90, 0.50 }, to = { 1.00, 0.25, 0.00 } },
    },
})

Themes.Register("frost", {
    name = "Frost",
    fillA      = { 0.10, 0.32, 0.85 },
    fillB      = { 0.45, 0.90, 1.00 },
    lead       = { 0.85, 0.95, 1.00, 0.25 },
    rested     = ALT_RESTED, restedText = ALT_RESTED_TEXT,
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
    -- Thick and slow, nearly frozen.
    physics    = { stiffness = 60, damping = 7, coupling = 500, slosh = 0.1, ambient = 0.3 },
    fillSpeed  = 0.7,
    swirl      = { texture = "Frost", flow = { 0.3, 0 }, alpha = 1.1 },
    bubbles    = { rate = 0, energyRate = 0 },
    burst      = { texture = "Snow", buoyancy = -15, drag = 1.2, spin = { -2, 2 } },
    ambient    = {
        -- Ice crystals forming along the front.
        { area = "front", rate = 3, energyRate = 6, texture = "Crystal", size = { 8, 14 }, life = { 1.5, 3 },
          vx = { -2, 0 }, vy = { -1, 1 }, buoyancy = 0, drag = 3, grow = true, alpha = 0.8,
          from = { 0.90, 1.00, 1.00 }, to = { 0.60, 0.85, 1.00 } },
        -- Snow drifting down onto the bar.
        { area = "above", rate = 1.2, texture = "Snow", size = { 7, 12 }, life = { 2.5, 4 },
          vx = { 3, 10 }, vy = { -14, -8 }, buoyancy = 0, drag = 0.2, spin = { -1.5, 1.5 }, alpha = 0.8,
          from = { 1.00, 1.00, 1.00 }, to = { 0.70, 0.90, 1.00 } },
    },
})

Themes.Register("honey", {
    name = "Honey",
    fillA      = { 0.55, 0.30, 0.02 },
    fillB      = { 1.00, 0.75, 0.20 },
    lead       = { 1.00, 0.95, 0.75, 0.25 },
    quest      = { 1.00, 0.38, 0.12, 1.00 }, -- both usual and alternate quest colours are too close to honey
    questText  = "FF6120",
    flash      = { 1.00, 0.80, 0.30 },
    tip        = { 1.00, 0.95, 0.70 },
    glow       = { 1.00, 0.80, 0.30 },
    swirlA     = { 1.00, 0.90, 0.50 },
    swirlB     = { 1.00, 0.70, 0.30 },
    bubble     = { 1.00, 0.95, 0.70 },
    splashFrom = { 1.00, 0.90, 0.50 },
    splashTo   = { 0.90, 0.55, 0.05 },
    absorbTo   = { 1.00, 0.75, 0.20 },
    levelFrom  = { 1.00, 0.95, 0.70 },
    levelTo    = { 0.95, 0.60, 0.10 },
    -- Very slow and sticky, with big lazy waves.
    physics    = { amplitude = 14, stiffness = 25, damping = 5, coupling = 250, slosh = 0.35, ambient = 0.5 },
    fillSpeed  = 0.45,
    swirl      = { texture = "Nebula", alpha = 0.9, flow = { 0.3, 0.05 } },
    bubbles    = { rate = 0.3, energyRate = 3, rise = { 4, 8 }, size = { 5, 9 }, alpha = 0.7 },
    burst      = { texture = "Glow", buoyancy = -30, drag = 2.5 }, -- drips that fall
})

Themes.Register("lava", {
    name = "Lava",
    fillA      = { 0.25, 0.02, 0.00 },
    fillB      = { 1.00, 0.35, 0.00 },
    lead       = { 1.00, 0.80, 0.50, 0.25 },
    quest      = ALT_QUEST, questText = ALT_QUEST_TEXT,
    flash      = { 1.00, 0.45, 0.10 },
    tip        = { 1.00, 0.80, 0.30 },
    glow       = { 1.00, 0.40, 0.05 },
    swirlA     = { 1.00, 0.75, 0.20 },
    swirlB     = { 1.00, 0.40, 0.05 },
    bubble     = { 1.00, 0.60, 0.10 },
    splashFrom = { 1.00, 0.90, 0.40 },
    splashTo   = { 1.00, 0.25, 0.00 },
    absorbTo   = { 1.00, 0.50, 0.10 },
    levelFrom  = { 1.00, 0.90, 0.50 },
    levelTo    = { 1.00, 0.30, 0.00 },
    -- Heavy and slow; the cracks throb with heat.
    physics    = { stiffness = 35, damping = 4, coupling = 350, slosh = 0.25, ambient = 0.7 },
    fillSpeed  = 0.55,
    swirl      = { texture = "Cracks", flow = { 0.15, 0 }, alpha = 1.4, pulse = 0.25, pulseRate = 0.35 },
    bubbles    = { texture = "Glow", blend = "ADD", rate = 0.8, energyRate = 6, rise = { 5, 10 }, size = { 5, 9 }, alpha = 0.8 },
    burst      = { texture = "Ember", buoyancy = -40, drag = 0.8 }, -- sparks that arc up and fall back
    ambient    = {
        { area = "surface", rate = 0.8, energyRate = 8, texture = "Mote", size = { 5, 9 }, life = { 0.5, 1 },
          vx = { -15, 15 }, vy = { 30, 60 }, buoyancy = -80, drag = 0.5,
          from = { 1.00, 0.90, 0.50 }, to = { 1.00, 0.30, 0.00 } },
    },
})

Themes.Register("cosmic", {
    name = "Cosmic",
    fillA      = { 0.03, 0.02, 0.12 },
    fillB      = { 0.30, 0.15, 0.55 },
    bg         = { 0, 0, 0, 0.7 },
    lead       = { 0.80, 0.80, 1.00, 0.25 },
    flash      = { 0.60, 0.50, 1.00 },
    tip        = { 0.80, 0.80, 1.00 },
    glow       = { 0.50, 0.40, 1.00 },
    swirlA     = { 0.60, 0.40, 1.00 },
    swirlB     = { 0.30, 0.60, 1.00 },
    splashFrom = { 1.00, 1.00, 1.00 },
    splashTo   = { 0.60, 0.70, 1.00 },
    absorbTo   = { 0.80, 0.80, 1.00 },
    levelFrom  = { 1.00, 1.00, 1.00 },
    levelTo    = { 0.60, 0.50, 1.00 },
    swirl      = { texture = "Nebula", alpha = 1.6, flow = { 0.4, 0.1 } },
    bubbles    = { rate = 0, energyRate = 0 },
    burst      = { texture = "Star", twinkle = 5, buoyancy = 0, drag = 1.2 },
    ambient    = {
        -- Stars twinkling inside the liquid.
        { area = "liquid", rate = 8, energyRate = 10, texture = "Mote", size = { 8, 14 }, life = { 1.5, 3 },
          vx = { -1, 1 }, vy = { -1, 1 }, buoyancy = 0, drag = 1, twinkle = 1.5,
          from = { 1.00, 1.00, 1.00 }, to = { 0.70, 0.80, 1.00 } },
    },
})

Themes.Register("nature", {
    name = "Nature",
    fillA      = { 0.10, 0.30, 0.05 },
    fillB      = { 0.45, 0.80, 0.20 },
    lead       = { 0.90, 1.00, 0.75, 0.25 },
    flash      = { 0.70, 1.00, 0.40 },
    tip        = { 0.90, 1.00, 0.70 },
    glow       = { 0.70, 1.00, 0.40 },
    swirlA     = { 1.00, 1.00, 0.70 },
    swirlB     = { 0.70, 1.00, 0.40 },
    bubble     = { 0.90, 1.00, 0.80 },
    splashFrom = { 0.60, 0.90, 0.30 },
    splashTo   = { 0.90, 0.75, 0.20 },
    absorbTo   = { 0.60, 0.90, 0.30 },
    levelFrom  = { 0.80, 1.00, 0.50 },
    levelTo    = { 0.90, 0.75, 0.20 },
    swirl      = { texture = "Caustics", alpha = 0.7, flow = { 0.4, 0.2 } }, -- dappled sunlight
    bubbles    = { rate = 0.3 },
    burst      = { texture = "Leaf", blend = "BLEND", buoyancy = -12, drag = 1.5, spin = { -3, 3 } },
    ambient    = {
        -- Leaves drifting down onto the bar.
        { area = "above", rate = 0.5, energyRate = 3, texture = "Leaf", blend = "BLEND", size = { 7, 11 },
          life = { 2.5, 4 }, vx = { 4, 12 }, vy = { -12, -6 }, buoyancy = 0, drag = 0.2, spin = { -2, 2 },
          from = { 0.60, 0.90, 0.30 }, to = { 0.90, 0.75, 0.20 } },
        -- Specks of pollen glinting in the liquid.
        { area = "liquid", rate = 1, texture = "Mote", size = { 6, 10 }, life = { 1, 2 },
          vx = { -3, 3 }, vy = { 2, 6 }, buoyancy = 0, drag = 1, twinkle = 2,
          from = { 1.00, 0.95, 0.60 }, to = { 1.00, 0.85, 0.30 } },
    },
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
    splashFrom = { 0.70, 0.50, 1.00 },
    splashTo   = { 0.35, 0.15, 0.80 },
    absorbTo   = { 0.55, 0.30, 1.00 },
    levelFrom  = { 0.85, 0.70, 1.00 },
    levelTo    = { 0.40, 0.15, 0.90 },
    physics    = { damping = 2.8, ambient = 1.4 },
    swirl      = { texture = "Tendrils", flow = { -0.6, 0 }, alpha = 1.3 }, -- writhing back against the flow
    bubbles    = { rate = 0, energyRate = 0 },
    -- Instead of throwing motes out, the void pulls them in.
    burst      = { texture = "Mote", mode = "attract", drag = 1.5 },
    ambient    = {
        { area = "above", mode = "attract", rate = 1.5, energyRate = 6, texture = "Glow", size = { 9, 15 },
          life = { 1.5, 2.5 }, vx = { -10, 10 }, vy = { -5, 5 }, drag = 1.2,
          from = { 0.60, 0.30, 1.00 }, to = { 0.20, 0.05, 0.50 } },
    },
})
