-- Liquid rendering for the experience fill: a wobbling front, swirling magic inside,
-- bubbles and glowing motes. Positions are in bar units (pixels before the bar's scale).
-- How the liquid moves and what it throws off comes from the theme; see Themes.lua.

local _, ns = ...

local exp, min, max, abs, sin, cos, sqrt, floor, random, pi =
    math.exp, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt, math.floor, math.random, math.pi

local MEDIA = "Interface\\AddOns\\SmoothExperienceBar\\Media\\"
local SWIRL_W, SWIRL_H = 256, 64

local CFG = {
    rows        = 15,      -- horizontal slices that make up the liquid front
    step        = 1 / 120, -- fixed physics step
    energyDecay = 0.8,     -- per second
    bubbles     = 36,      -- pool sizes
    motes       = 64,
    edgeW       = 6,       -- width of the bright line texture along the front, px
    edgeCore    = 0.7,     -- where the line sits across Edge.tga (EDGE_CORE in make_media.py)
    foamW       = 12,      -- froth ahead of the front where it meets quest or rested XP, px
}

-- Defaults for the theme tables of the same name. A theme only lists what it changes.
local PHYSICS = {
    amplitude = 10,   -- how far the front can bulge or dip, px
    stiffness = 90,   -- spring pulling each slice back to rest
    damping   = 3.5,
    coupling  = 900,  -- how strongly neighbouring slices pull on each other (wave speed)
    slosh     = 0.18, -- front displacement per px/s change in fill speed
    ambient   = 1.0,  -- idle wobble, px
}

local SWIRL = {
    texture = "Swirl",
    flow    = { 1, 0 }, -- drift direction of the veins (u toward the front, v upward)
    alpha   = 1,        -- multiplier on the swirl brightness
    pulse   = 0,        -- extra brightness that throbs at pulseRate Hz
    pulseRate = 0.5,
}

-- Slow clouds behind the veins for depth: dark pockets and light wisps, larger and slower than the veins.
local CLOUDS = {
    texture = "Nebula",
    dark    = 0.55, -- alpha of the darkening layer
    light   = 0.25, -- alpha of the light layer, tinted swirlB
    scale   = 0.55, -- texture repeats per SWIRL_W px; lower = bigger clouds
}

-- Light from inside the liquid: a soft band through the middle in the theme's glow colour.
local CORE = {
    alpha     = 1,   -- multiplier on the core brightness
    pulseRate = 0.2, -- Hz
}

local BUBBLES = {
    texture = "Bubble",
    blend   = "BLEND",
    rate    = 0.5,          -- per second when calm
    energyRate = 14,        -- extra per second at full energy
    rise    = { 12, 26 },   -- px/s
    size    = { 3, 6 },
    alpha   = 0.45,
    drift   = 1,            -- slow drifters anywhere in the liquid, per second per unit of rate
}

-- Motes thrown off by XP gains, turn-ins and level-ups.
-- mode "throw" flings them out of the front; "attract" spawns them around it and pulls them in.
local BURST = {
    texture  = "Mote",
    blend    = "ADD",
    mode     = "throw",
    buoyancy = 20,   -- px/s^2 upward
    drag     = 1.8,
    spin     = nil,  -- { min, max } rad/s
    twinkle  = nil,  -- Hz
}

local function Rand(a, b)
    return a + (b - a) * random()
end

local function RandRange(r, default)
    if not r then return default end
    return Rand(r[1], r[2])
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function Merge(defaults, over)
    local t = {}
    for k, v in pairs(defaults) do t[k] = v end
    if over then
        for k, v in pairs(over) do t[k] = v end
    end
    return t
end

local Liquid = {}
Liquid.__index = Liquid
ns.Liquid = Liquid

-- opts holds the user toggles (waves, swirl, bubbles, sparkles, ambient, restedGlow) and is read live.
function Liquid.New(parent, width, height, theme, opts)
    local self = setmetatable({}, Liquid)
    self.parent, self.width, self.height, self.opts = parent, width, height, opts
    self.rowH = height / CFG.rows

    local function Tex(layer, sublevel, file, blend, wrap)
        local t = parent:CreateTexture(nil, layer, nil, sublevel)
        if not file then
            t:SetColorTexture(1, 1, 1, 1) -- solid; tinted with vertex colours and gradients
        elseif wrap then
            t:SetTexture(file, wrap, wrap)
        else
            t:SetTexture(file)
        end
        if blend then t:SetBlendMode(blend) end
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        t:Hide()
        return t
    end

    self.body = Tex("ARTWORK", 3)
    self.body:SetPoint("TOPLEFT")
    self.body:SetPoint("BOTTOMLEFT")

    self.rows, self.tips, self.foam, self.pos, self.vel = {}, {}, {}, {}, {}
    for i = 1, CFG.rows do
        local row = Tex("ARTWORK", 3)
        row:SetHeight(self.rowH)
        self.rows[i] = row

        self.tips[i] = Tex("ARTWORK", 6, MEDIA .. "Edge", "ADD")
        self.foam[i] = Tex("ARTWORK", 5, MEDIA .. "Foam", "ADD")
        self.pos[i], self.vel[i] = 0, 0
    end
    self:LayoutTips()

    -- Textures that fill the inside of the liquid. Each is one texture up to the rearmost point of the
    -- front plus a cap per slice carrying it on to that slice's end, so nothing spills into a dip.
    local function Layer(sublevel, file, blend)
        local layer = { main = Tex("ARTWORK", sublevel, MEDIA .. file, blend, "REPEAT"), caps = {}, u = 0, v = 0 }
        layer.main:SetPoint("TOPLEFT")
        layer.main:SetPoint("BOTTOMLEFT")
        for i = 1, CFG.rows do
            layer.caps[i] = Tex("ARTWORK", sublevel, MEDIA .. file, blend, "REPEAT")
        end
        return layer
    end
    self.ends = {}
    self.cloudDark = Layer(4, "Nebula", "BLEND")
    self.cloudLight = Layer(5, "Nebula", "ADD")
    self.core = Layer(5, "Core", "ADD")
    self.swirlA = Layer(5, "Swirl", "ADD")
    self.swirlB = Layer(5, "Swirl", "ADD")
    self.cloudLight.u, self.swirlB.u = 0.5, 0.37

    self.restGlow = Tex("ARTWORK", 5, MEDIA .. "Glow", "ADD")

    self.glow = Tex("ARTWORK", 7, MEDIA .. "Glow", "ADD")
    self.glow:SetSize(36, height * 1.7)

    self.bubbles = {}
    for i = 1, CFG.bubbles do
        self.bubbles[i] = { tex = Tex("OVERLAY", 3, MEDIA .. "Bubble"), active = false }
    end

    self.motes, self.moteNext = {}, 1
    for i = 1, CFG.motes do
        self.motes[i] = { tex = Tex("OVERLAY", 4, MEDIA .. "Mote", "ADD"), active = false, file = "Mote", blend = "ADD" }
    end

    self.gradA, self.gradB, self.gradC = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
    self.t, self.acc, self.energy, self.fizzAcc, self.driftAcc = 0, 0, 0, 0, 0
    self.edge, self.speed, self.back = 0, 0, 0
    self.flowX, self.flowY = 0, 0
    self.ambientAcc = {}
    self.rested = false
    self:SetTheme(theme)
    return self
end

function Liquid:SetTheme(theme)
    self.theme = theme
    self.phys = Merge(PHYSICS, theme.physics)
    self.swirl = Merge(SWIRL, theme.swirl)
    self.clouds = Merge(CLOUDS, theme.clouds)
    self.coreStyle = Merge(CORE, theme.core)
    self.bubbleStyle = Merge(BUBBLES, theme.bubbles)
    self.burst = Merge(BURST, theme.burst)
    self.levelBurst = Merge(self.burst, { mode = "throw" })
    self.ambient = nil
    if theme.ambient then
        self.ambient = {}
        for i, em in ipairs(theme.ambient) do
            self.ambient[i] = Merge(BURST, em)
        end
    end
    self.ambientAcc = {}
    self.accent = nil
    self.contact = nil -- recoloured on the next SetContact

    for _, tip in ipairs(self.tips) do
        tip:SetVertexColor(unpack(theme.tip))
    end
    self:LayerTexture(self.swirlA, self.swirl.texture)
    self:LayerTexture(self.swirlB, self.swirl.texture)
    self:LayerTexture(self.cloudDark, self.clouds.texture)
    self:LayerTexture(self.cloudLight, self.clouds.texture)
    self:LayerColor(self.swirlA, theme.swirlA)
    self:LayerColor(self.swirlB, theme.swirlB)
    self:LayerColor(self.cloudDark, { 0, 0, 0 })
    self:LayerColor(self.cloudLight, theme.swirlB)
    self:LayerColor(self.core, theme.glow)
    self.glow:SetVertexColor(unpack(theme.glow))
    self.restGlow:SetVertexColor(theme.rested[1], theme.rested[2], theme.rested[3])

    -- Bubbles take on some of the veins' colour so they belong to the liquid.
    local bs, bc, vc = self.bubbleStyle, theme.bubble, theme.swirlA
    for _, b in ipairs(self.bubbles) do
        b.tex:SetTexture(MEDIA .. bs.texture)
        b.tex:SetBlendMode(bs.blend)
        b.tex:SetVertexColor(Lerp(bc[1], vc[1], 0.5), Lerp(bc[2], vc[2], 0.5), Lerp(bc[3], vc[3], 0.5))
    end
    -- Particles from the previous theme would look out of place.
    for _, m in ipairs(self.motes) do
        m.active = false
        m.tex:Hide()
    end
end

function Liquid:LayerTexture(layer, name)
    local file = MEDIA .. name
    layer.main:SetTexture(file, "REPEAT", "REPEAT")
    for _, cap in ipairs(layer.caps) do cap:SetTexture(file, "REPEAT", "REPEAT") end
end

function Liquid:LayerColor(layer, c)
    layer.main:SetVertexColor(c[1], c[2], c[3])
    for _, cap in ipairs(layer.caps) do cap:SetVertexColor(c[1], c[2], c[3]) end
end

local function HideLayer(layer)
    layer.main:Hide()
    for _, cap in ipairs(layer.caps) do cap:Hide() end
end

-- ku, kv: texture units per px across and down. Caps use the same mapping as the main texture,
-- so each continues it without a seam.
function Liquid:DrawLayer(layer, ku, kv, alpha)
    local back, ends, rowH, parent = self.back, self.ends, self.rowH, self.parent
    if back < 1 or alpha <= 0.002 then
        HideLayer(layer)
        return
    end
    local u, v = layer.u, layer.v
    local main = layer.main
    main:SetWidth(back)
    main:SetTexCoord(u, u + back * ku, v, v + self.height * kv)
    main:SetAlpha(alpha)
    main:Show()
    local ub = u + back * ku
    for i, cap in ipairs(layer.caps) do
        local e = ends[i]
        if e and e - back >= 0.5 then
            local y = (i - 1) * rowH
            cap:SetPoint("TOPLEFT", parent, "TOPLEFT", back, -y)
            cap:SetSize(e - back, rowH)
            cap:SetTexCoord(ub, u + e * ku, v + y * kv, v + (y + rowH) * kv)
            cap:SetAlpha(alpha)
            cap:Show()
        else
            cap:Hide()
        end
    end
end

-- Each slice's line and froth are 1.5 slices tall so they overlap their neighbours on the
-- textures' ramps. The first and last drop their outer ramp so they stay inside the bar.
function Liquid:LayoutTips()
    local rowH, n = self.rowH, CFG.rows
    for i, tip in ipairs(self.tips) do
        local top, h, v0, v1 = rowH * 0.25, rowH * 1.5, 0, 1
        if i == 1 then
            top, h, v0 = 0, rowH * 1.25, 1 / 3
        elseif i == n then
            h, v1 = rowH * 1.25, 2 / 3
        end
        tip:SetSize(CFG.edgeW, h)
        tip:SetTexCoord(0, 1, v0, v1)
        tip.dy = top
        self.foam[i]:SetHeight(h)
        self.foam[i]:SetTexCoord(0, 1, v0, v1)
    end
end

-- The segment the front is pushing into: its colour and where it ends (px), or nil for empty bar.
function Liquid:SetContact(color, reach)
    self.reach = reach
    if color == self.contact then return end
    self.contact = color
    if color then
        local r, g, b = color[1], color[2], color[3]
        for _, f in ipairs(self.foam) do
            f:SetVertexColor(Lerp(r, 1, 0.6), Lerp(g, 1, 0.6), Lerp(b, 1, 0.6))
        end
    end
end

function Liquid:SetSize(width, height)
    self.width, self.height = width, height
    self.rowH = height / CFG.rows
    for i = 1, CFG.rows do
        self.rows[i]:SetHeight(self.rowH)
    end
    self:LayoutTips()
    self.glow:SetSize(36, height * 1.7)
end

function Liquid:SetOptions(opts)
    self.opts = opts
    self:ApplyOptions()
end

-- Clear anything a toggle just switched off.
function Liquid:ApplyOptions()
    local opts = self.opts
    if not opts.waves then
        for i = 1, CFG.rows do self.pos[i], self.vel[i] = 0, 0 end
    end
    if not opts.bubbles then
        for _, b in ipairs(self.bubbles) do
            b.active = false
            b.tex:Hide()
        end
    end
    for _, m in ipairs(self.motes) do
        if m.active and ((m.ambient and not opts.ambient) or (not m.ambient and not opts.sparkles)) then
            m.active = false
            m.tex:Hide()
        end
    end
end

-- Whether the player has rested XP, for the optional rested glow.
function Liquid:SetRested(rested)
    self.rested = rested
end

--------------------------------------------------------------------------------
-- Events from the bar
--------------------------------------------------------------------------------

-- Jump the front without sloshing, e.g. on load or when a level wraps back to 0.
function Liquid:Snap(edge)
    self.edge, self.speed, self.back = edge, 0, edge
end

-- How far back the front reaches this frame; it can dip behind the edge while sloshing.
function Liquid:Back()
    return self.back
end

-- Colours for burst motes; themes with animated colours tint them with the current accent.
function Liquid:BurstColors(from, to)
    if self.accent then return from, self.accent end
    return from, to
end

-- XP gained. intensity 0..1, fromX..toX is where the new XP will land.
function Liquid:Splash(intensity, fromX, toX)
    self.energy = min(1.5, self.energy + 0.08 + intensity * 0.9)

    -- Ripple out from a random point on the front.
    if self.opts.waves then
        local n = CFG.rows
        local centre = random(1, n)
        local kick = 40 + 160 * intensity
        for i = 1, n do
            local d = (i - centre) / n
            self.vel[i] = self.vel[i] + kick * exp(-d * d * 8)
        end
    end

    local h, theme, style = self.height, self.theme, self.burst
    local from, to = self:BurstColors(theme.splashFrom, theme.splashTo)
    for _ = 1, floor(1 + intensity * 18) do
        local s = 0.5 + intensity
        local life, size = Rand(0.5, 1.1) + intensity * 0.4, Rand(8, 14) * (0.7 + 0.5 * intensity)
        if style.mode == "attract" then
            local a, d = Rand(0, 2 * pi), Rand(25, 60) * (0.7 + 0.5 * intensity)
            self:EmitMote(fromX + cos(a) * d, h / 2 + sin(a) * d * 0.6, -sin(a) * 30, cos(a) * 30,
                life + 0.6, size, from, to, style)
        else
            self:EmitMote(Rand(fromX - 6, max(fromX, toX)), Rand(2, h - 2),
                Rand(-20, 60) * s, Rand(10, 70) * s, life, size, from, to, style)
        end
    end
    for _ = 1, floor(intensity * 8) do
        self:EmitBubble(Rand(max(4, fromX - 40), max(4, fromX - 2)))
    end
end

-- Completed-quest XP turned in: motes stream from the quest segment into the liquid.
function Liquid:Absorb(fromX, toX, intensity)
    local h, theme, style = self.height, self.theme, self.burst
    for _ = 1, floor(4 + intensity * 16) do
        self:EmitMote(Rand(fromX, max(fromX, toX)), Rand(2, h - 2),
            -Rand(40, 140), Rand(-10, 25),
            Rand(0.6, 1.1), Rand(8, 13),
            theme.quest, theme.absorbTo, style)
    end
end

function Liquid:LevelUp()
    self.energy = 1.5
    if self.opts.waves then
        for i = 1, CFG.rows do
            self.vel[i] = self.vel[i] + Rand(120, 220)
        end
    end
    local w, h, theme = self.width, self.height, self.theme
    local from, to = self:BurstColors(theme.levelFrom, theme.levelTo)
    for _ = 1, 30 do
        self:EmitMote(Rand(0, w), Rand(0, h),
            Rand(-30, 30), Rand(40, 120),
            Rand(0.8, 1.6), Rand(10, 18),
            from, to, self.levelBurst)
    end
end

-- Nothing visible is moving beyond the idle wobble and slow ambient particles, so the caller
-- can lower the update rate.
function Liquid:IsQuiet()
    if self.energy > 0.02 then return false end
    for i = 1, CFG.rows do
        if abs(self.vel[i]) > 1 or abs(self.pos[i]) > 0.3 then return false end
    end
    for _, m in ipairs(self.motes) do
        if m.active and not m.ambient then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Particles
--------------------------------------------------------------------------------

-- from/to are the colours the mote fades between over its life; style is a BURST-like table.
function Liquid:EmitMote(x, y, vx, vy, life, size, from, to, style, ambient)
    if ambient then
        if not self.opts.ambient then return end
    elseif not self.opts.sparkles then
        return
    end
    local m = self.motes[self.moteNext]
    self.moteNext = self.moteNext % #self.motes + 1
    m.x, m.y, m.vx, m.vy, m.age, m.life, m.size = x, y, vx, vy, 0, life, size
    m.r1, m.g1, m.b1, m.r2, m.g2, m.b2 = from[1], from[2], from[3], to[1], to[2], to[3]
    m.style, m.ambient = style, ambient
    m.spin = RandRange(style.spin, 0)
    m.rot = Rand(0, 2 * pi)
    m.phase = Rand(0, 2 * pi)
    local tex = m.tex
    if m.file ~= style.texture then
        m.file = style.texture
        tex:SetTexture(MEDIA .. style.texture)
    end
    if m.blend ~= style.blend then
        m.blend = style.blend
        tex:SetBlendMode(style.blend)
    end
    if tex.SetRotation then tex:SetRotation(style.spin and m.rot or 0) end
    m.active = true
    tex:Show()
end

-- Continuous particles from a theme's `ambient` list (embers, snow, spores, stars...).
-- area: "liquid" anywhere in the liquid, "surface" along its top, "front" at the liquid front,
-- "above" over the bar so they can drift down onto it.
function Liquid:EmitAmbient(em, edge)
    local w, h = self.width, self.height
    local x, y
    if em.area == "front" then
        if edge < 4 or edge > w - 2 then return end
        x, y = Rand(edge - 6, edge + 1), Rand(2, h - 2)
    elseif em.area == "surface" then
        if edge < 8 then return end
        x, y = Rand(2, edge - 2), Rand(h - 5, h)
    elseif em.area == "above" then
        x, y = Rand(0, min(w, edge + 40)), Rand(h + 4, h + 14)
    else
        if edge < 8 then return end
        x, y = Rand(2, edge - 4), Rand(2, h - 2)
    end
    local from, to = em.from or self.theme.splashFrom, em.to or self.theme.splashTo
    if self.accent then to = self.accent end
    self:EmitMote(x, y, RandRange(em.vx, 0), RandRange(em.vy, 0), RandRange(em.life, 1.5),
        RandRange(em.size, 8), from, to, em, true)
end

-- Fizz rises from the bottom, mostly small. Drifters start anywhere in the liquid and rise slowly.
-- Both are carried along by the swirl and circle in small eddies.
function Liquid:EmitBubble(x, drifter)
    if not self.opts.bubbles then return end
    local bs = self.bubbleStyle
    local s1, s2 = bs.size[1], bs.size[2]
    for _, b in ipairs(self.bubbles) do
        if not b.active then
            if drifter then
                b.x, b.y = x, Rand(3, self.height * 0.6)
                b.vx, b.vy = Rand(-1, 2), Rand(bs.rise[1] * 0.25, bs.rise[1] * 0.5)
                b.size = Rand(s1 * 0.8, s2 * 0.9)
                b.phase, b.freq, b.sway = Rand(0, 6.28), Rand(1.2, 2.4), 2.5
            else
                b.x, b.y = x, Rand(2, 6)
                b.vx, b.vy = Rand(2, 8), Rand(bs.rise[1], bs.rise[2])
                b.size = random() < 0.6 and Rand(s1 * 0.5, s1 * 0.8) or Rand(s1 * 0.8, s2 * 0.8)
                b.phase, b.freq, b.sway = Rand(0, 6.28), Rand(3, 6), 1.5
            end
            b.age, b.pop = 0, nil
            b.active = true
            b.tex:Show()
            return
        end
    end
end

function Liquid:UpdateParticles(dt)
    local parent, h, edge, t = self.parent, self.height, self.edge, self.t
    local bubbleAlpha = self.bubbleStyle.alpha

    for _, b in ipairs(self.bubbles) do
        if b.active then
            if b.pop then
                b.pop = b.pop + dt
                local p = b.pop / 0.15
                if p >= 1 then
                    b.active = false
                    b.tex:Hide()
                else
                    b.tex:SetSize(b.size * (1 + p), b.size * (1 + p))
                    b.tex:SetAlpha(bubbleAlpha * (1 - p))
                end
            else
                b.age = b.age + dt
                b.x = b.x + (b.vx + self.flowX + self.speed * 0.3) * dt
                b.y = b.y + (b.vy + self.flowY) * dt
                -- Fades in, and grows a little on the way up as the pressure drops.
                local size = b.size * (1 + 0.25 * b.y / h)
                if b.y >= h - size * 0.5 or b.x > edge - 2 then
                    b.pop, b.size = 0, size -- the pop grows from here
                end
                b.tex:SetSize(size, size)
                b.tex:SetAlpha(bubbleAlpha * min(1, b.age / 0.25))
            end
            local a = b.phase + t * b.freq
            b.tex:SetPoint("CENTER", parent, "BOTTOMLEFT", b.x + sin(a) * b.sway, b.y + cos(a) * b.sway * 0.6)
        end
    end

    for _, m in ipairs(self.motes) do
        if m.active then
            local st = m.style
            m.age = m.age + dt
            local p = m.age / m.life
            local done = p >= 1
            if not done then
                local drag = exp(-(st.drag or 1.8) * dt)
                if st.mode == "attract" then
                    -- Pulled toward the middle of the liquid front, faster as they close in.
                    local dx, dy = edge - m.x, h / 2 - m.y
                    local d = sqrt(dx * dx + dy * dy)
                    if d < 4 then
                        done = true
                    else
                        local pull = 500 + 4000 / (d + 10)
                        m.vx = (m.vx + dx / d * pull * dt) * drag
                        m.vy = (m.vy + dy / d * pull * dt) * drag
                    end
                else
                    m.vx = m.vx * drag
                    m.vy = m.vy * drag + (st.buoyancy or 20) * dt
                end
            end
            if done then
                m.active = false
                m.tex:Hide()
            else
                m.x = m.x + m.vx * dt
                m.y = m.y + m.vy * dt
                local size, alpha
                if m.ambient then
                    -- Lingering particles: fade in, hold, fade out.
                    size = m.size * (1 - 0.2 * p)
                    alpha = min(1, p / 0.2, (1 - p) / 0.3)
                else
                    -- Bursts flare and die away.
                    size = m.size * (1 - 0.5 * p)
                    alpha = (p < 0.1 and p / 0.1 or 1) * (1 - p) ^ 1.5
                end
                if st.grow then
                    size = m.size * min(1, 0.3 + 0.7 * p / 0.2) * (1 - 0.3 * p)
                end
                if st.twinkle then
                    alpha = alpha * (0.55 + 0.45 * sin(m.phase + t * st.twinkle * 2 * pi))
                end
                if m.spin ~= 0 and m.tex.SetRotation then
                    m.rot = m.rot + m.spin * dt
                    m.tex:SetRotation(m.rot)
                end
                m.tex:SetSize(size, size)
                m.tex:SetVertexColor(Lerp(m.r1, m.r2, p), Lerp(m.g1, m.g2, p), Lerp(m.b1, m.b2, p))
                m.tex:SetAlpha(alpha * (st.alpha or 1))
                m.tex:SetPoint("CENTER", parent, "BOTTOMLEFT", m.x, m.y)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Simulation and drawing
--------------------------------------------------------------------------------

function Liquid:Simulate(dt)
    local pos, vel, n, phys = self.pos, self.vel, CFG.rows, self.phys
    local k, d, c, limit = phys.stiffness, phys.damping, phys.coupling, phys.amplitude * 1.2
    local s = CFG.step

    self.acc = min(self.acc + dt, s * 8)
    while self.acc >= s do
        self.acc = self.acc - s
        for i = 1, n do
            local p = pos[i]
            local lap = (pos[i - 1] or p) + (pos[i + 1] or p) - 2 * p
            vel[i] = vel[i] + (-k * p - d * vel[i] + c * lap) * s
        end
        for i = 1, n do
            local p = pos[i] + vel[i] * s
            if p > limit then
                p, vel[i] = limit, 0
            elseif p < -limit then
                p, vel[i] = -limit, 0
            end
            pos[i] = p
        end
    end
end

function Liquid:Update(dt, edge)
    self.t = self.t + dt

    -- The liquid's inertia: speeding up drags the front back, slowing down sloshes it forward.
    local speed = (edge - self.edge) / dt
    local dv = speed - self.speed
    self.edge, self.speed = edge, speed
    if dv ~= 0 and self.opts.waves then
        local kick = -dv * self.phys.slosh
        local n = CFG.rows
        for i = 1, n do
            self.vel[i] = self.vel[i] + kick * sin(pi * (i - 0.5) / n)
        end
    end

    self:Simulate(dt)
    self.energy = self.energy * exp(-CFG.energyDecay * dt)

    local bs = self.bubbleStyle
    self.fizzAcc = self.fizzAcc + dt * (bs.rate + self.energy * bs.energyRate)
    while self.fizzAcc >= 1 do
        self.fizzAcc = self.fizzAcc - 1
        if edge > 16 then self:EmitBubble(Rand(4, edge - 8)) end
    end
    self.driftAcc = self.driftAcc + dt * bs.rate * bs.drift
    while self.driftAcc >= 1 do
        self.driftAcc = self.driftAcc - 1
        if edge > 24 then self:EmitBubble(Rand(4, edge - 14), true) end
    end

    if self.ambient and self.opts.ambient then
        for i, em in ipairs(self.ambient) do
            local acc = (self.ambientAcc[i] or 0) + dt * (em.rate + (em.energyRate or 0) * self.energy)
            while acc >= 1 do
                acc = acc - 1
                self:EmitAmbient(em, edge)
            end
            self.ambientAcc[i] = acc
        end
    end

    self:Draw(dt)
    self:UpdateParticles(dt)
end

function Liquid:Draw(dt)
    local parent, w, h, amp = self.parent, self.width, self.height, self.phys.amplitude
    local edge, energy, t = self.edge, self.energy, self.t
    local opts, theme = self.opts, self.theme
    local wobble = opts.waves and self.phys.ambient * (0.6 + energy) or 0
    -- The body stops behind the deepest dent Simulate and the wobble allow, so no slice of the
    -- front ever falls behind it and flattens into the body's straight end.
    local base = max(0, edge - amp * 1.2 - wobble * 1.5 - 0.5)

    local fa, fb = theme.fillA, theme.fillB
    if theme.Colors then
        -- Animated themes pick their colours each frame from time and progress.
        local accent
        fa, fb, accent = theme:Colors(t, w > 0 and edge / w or 0)
        self.accent = accent
        if accent then
            self.glow:SetVertexColor(accent[1], accent[2], accent[3])
            self:LayerColor(self.swirlA, accent)
            self:LayerColor(self.core, accent)
        end
    end

    -- Gradient stretched over the whole fill, like the WeakAura; the body stops where the front begins.
    local tb = edge > 0 and base / edge or 0
    self.gradA:SetRGBA(fa[1], fa[2], fa[3], 1)
    self.gradB:SetRGBA(Lerp(fa[1], fb[1], tb), Lerp(fa[2], fb[2], tb), Lerp(fa[3], fb[3], tb), 1)
    self.gradC:SetRGBA(fb[1], fb[2], fb[3], 1)

    if base >= 0.5 then
        self.body:SetGradient("HORIZONTAL", self.gradA, self.gradB)
        self.body:SetWidth(base)
        self.body:Show()
    else
        self.body:Hide()
    end

    local tipAlpha = 0.25 + 0.5 * min(1, energy)
    local rowH, back, ends = self.rowH, edge, self.ends
    -- Froth where the front meets quest or rested XP: faint at rest, brighter and pushed further
    -- ahead while the liquid pours into it.
    local contact, reach = self.contact, self.reach or 0
    local stir = min(1, max(0, self.speed) / 150 + energy * 0.5)
    local foamA, foamW = 0.2 + 0.8 * stir, CFG.foamW * (1 + stir)
    for i = 1, CFG.rows do
        local row, tip, foam = self.rows[i], self.tips[i], self.foam[i]
        local off = self.pos[i] + wobble * (sin(t * 2.3 + i * 0.6) + 0.5 * sin(t * 3.7 - i * 1.1))
        local right = min(w, edge + off)
        local rw = right - base
        local fw = min(foamW, reach - right)
        -- Where the liquid visibly ends in this slice: a slice dented past the body shows the body's end.
        local vis = edge >= 0.5 and (rw >= 0.5 and right or base >= 0.5 and base) or nil
        ends[i] = vis
        if vis and vis < back then back = vis end
        if edge < 0.5 or rw < 0.5 then
            row:Hide()
            tip:Hide()
            foam:Hide()
        else
            local y = -(i - 1) * rowH
            row:SetGradient("HORIZONTAL", self.gradB, self.gradC)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", base, y)
            row:SetWidth(rw)
            row:Show()
            if right < w - 1 then
                tip:SetPoint("TOPLEFT", parent, "TOPLEFT", right - 0.5 - CFG.edgeCore * CFG.edgeW, y + tip.dy)
                tip:SetAlpha(min(1, tipAlpha + abs(self.vel[i]) * 0.01))
                tip:Show()
            else
                tip:Hide()
            end
            if contact and fw >= 1 then
                foam:SetWidth(fw)
                foam:SetPoint("TOPLEFT", parent, "TOPLEFT", right - 0.5, y + tip.dy)
                foam:SetAlpha(foamA * (0.8 + 0.2 * sin(t * 9 + i * 1.7)))
                foam:Show()
            else
                foam:Hide()
            end
        end
    end

    self.back = max(0, back)

    -- Inside the liquid, back to front: dark cloud pockets, light wisps and the glowing core, then the
    -- magic veins. All drift with the theme's flow, faster and brighter with energy and fill speed.
    local sw, cl, co = self.swirl, self.clouds, self.coreStyle
    local swirlA, swirlB, cloudDark, cloudLight, core = self.swirlA, self.swirlB, self.cloudDark, self.cloudLight, self.core
    if self.back >= 1 and opts.swirl then
        local flow = 0.015 + 0.12 * energy + max(0, self.speed) / 2000
        local fu, fv = sw.flow[1], sw.flow[2]
        swirlA.u = (swirlA.u - flow * fu * dt) % 1
        swirlA.v = (swirlA.v - flow * fv * dt) % 1
        swirlB.u = (swirlB.u - flow * fu * 0.6 * dt) % 1
        swirlB.v = (swirlB.v + (0.03 - flow * fv * 0.6) * dt) % 1
        cloudDark.u = (cloudDark.u - (0.004 + flow * fu * 0.3) * dt) % 1
        cloudDark.v = (cloudDark.v + (0.008 - flow * fv * 0.3) * dt) % 1
        cloudLight.u = (cloudLight.u - (0.006 + flow * fu * 0.45) * dt) % 1
        cloudLight.v = (cloudLight.v - (0.012 + flow * fv * 0.45) * dt) % 1
        core.u = (core.u - (0.01 + flow * 0.3) * dt) % 1
        -- How fast the veins move on screen, px/s with y up, so bubbles can ride along with them.
        self.flowX, self.flowY = flow * fu * SWIRL_W, -flow * fv * SWIRL_H

        local cs = cl.scale
        self:DrawLayer(cloudDark, cs / SWIRL_W, cs / SWIRL_H, cl.dark)
        self:DrawLayer(cloudLight, cs * 1.4 / SWIRL_W, cs * 1.4 / SWIRL_H, cl.light * (1 + energy))
        local glow = 0.2 + 0.07 * sin(t * co.pulseRate * 2 * pi) + 0.3 * min(1, energy)
        self:DrawLayer(core, 0.5 / SWIRL_W, 1 / h, min(1, glow * co.alpha))

        local pulse = sw.pulse * (0.5 + 0.5 * sin(t * sw.pulseRate * 2 * pi))
        self:DrawLayer(swirlA, 1 / SWIRL_W, 1 / SWIRL_H, min(1, (0.12 + 0.3 * energy + pulse) * sw.alpha))
        self:DrawLayer(swirlB, 0.7 / SWIRL_W, 0.7 / SWIRL_H,
            min(1, (0.08 + 0.22 * energy + 0.05 * sin(t * 1.3) + pulse * 0.6) * sw.alpha))
    else
        self.flowX, self.flowY = 0, 0
        HideLayer(cloudDark)
        HideLayer(cloudLight)
        HideLayer(core)
        HideLayer(swirlA)
        HideLayer(swirlB)
    end

    if opts.restedGlow and self.rested and edge > 4 then
        self.restGlow:SetPoint("CENTER", parent, "LEFT", edge / 2, 0)
        self.restGlow:SetSize(edge * 1.1, h * 1.6)
        self.restGlow:SetAlpha(0.12 + 0.08 * sin(t * 2))
        self.restGlow:Show()
    else
        self.restGlow:Hide()
    end

    if edge > 1 and edge < w - 1 then
        self.glow:SetPoint("CENTER", parent, "LEFT", edge, 0)
        self.glow:SetAlpha(min(1, 0.12 + 0.55 * energy))
        self.glow:Show()
    else
        self.glow:Hide()
    end
end
