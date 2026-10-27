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
    bubbles     = 20,      -- pool sizes
    motes       = 64,
    edgeW       = 6,       -- width of the bright line texture along the front, px
    edgeCore    = 0.7,     -- where the line sits across Edge.tga (EDGE_CORE in make_media.py)
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

local BUBBLES = {
    texture = "Bubble",
    blend   = "BLEND",
    rate    = 0.5,          -- per second when calm
    energyRate = 14,        -- extra per second at full energy
    rise    = { 12, 26 },   -- px/s
    size    = { 3, 6 },
    alpha   = 0.6,
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

    self.rows, self.tips, self.pos, self.vel = {}, {}, {}, {}
    for i = 1, CFG.rows do
        local row = Tex("ARTWORK", 3)
        row:SetHeight(self.rowH)
        self.rows[i] = row

        self.tips[i] = Tex("ARTWORK", 6, MEDIA .. "Edge", "ADD")
        self.pos[i], self.vel[i] = 0, 0
    end
    self:LayoutTips()

    self.swirlA = Tex("ARTWORK", 5, MEDIA .. "Swirl", "ADD", "REPEAT")
    self.swirlA:SetPoint("TOPLEFT")
    self.swirlA:SetPoint("BOTTOMLEFT")

    self.swirlB = Tex("ARTWORK", 5, MEDIA .. "Swirl", "ADD", "REPEAT")
    self.swirlB:SetPoint("TOPLEFT")
    self.swirlB:SetPoint("BOTTOMLEFT")

    self.restGlow = Tex("ARTWORK", 4, MEDIA .. "Glow", "ADD")

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
    self.t, self.acc, self.energy, self.fizzAcc = 0, 0, 0, 0
    self.edge, self.speed, self.back = 0, 0, 0
    self.uA, self.vA, self.uB, self.vB = 0, 0, 0.37, 0
    self.ambientAcc = {}
    self.rested = false
    self:SetTheme(theme)
    return self
end

function Liquid:SetTheme(theme)
    self.theme = theme
    self.phys = Merge(PHYSICS, theme.physics)
    self.swirl = Merge(SWIRL, theme.swirl)
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

    for _, tip in ipairs(self.tips) do
        tip:SetVertexColor(unpack(theme.tip))
    end
    local swirlFile = MEDIA .. self.swirl.texture
    self.swirlA:SetTexture(swirlFile, "REPEAT", "REPEAT")
    self.swirlB:SetTexture(swirlFile, "REPEAT", "REPEAT")
    self.swirlA:SetVertexColor(unpack(theme.swirlA))
    self.swirlB:SetVertexColor(unpack(theme.swirlB))
    self.glow:SetVertexColor(unpack(theme.glow))
    self.restGlow:SetVertexColor(theme.rested[1], theme.rested[2], theme.rested[3])

    local bs = self.bubbleStyle
    for _, b in ipairs(self.bubbles) do
        b.tex:SetTexture(MEDIA .. bs.texture)
        b.tex:SetBlendMode(bs.blend)
        b.tex:SetVertexColor(unpack(theme.bubble))
    end
    -- Particles from the previous theme would look out of place.
    for _, m in ipairs(self.motes) do
        m.active = false
        m.tex:Hide()
    end
end

-- Each slice's line is 1.5 slices tall so it overlaps its neighbours on Edge.tga's ramps.
-- The first and last drop their outer ramp so the line stays inside the bar.
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

function Liquid:EmitBubble(x)
    if not self.opts.bubbles then return end
    local bs = self.bubbleStyle
    for _, b in ipairs(self.bubbles) do
        if not b.active then
            b.x, b.y = x, Rand(2, 6)
            b.vx, b.vy = Rand(4, 14), Rand(bs.rise[1], bs.rise[2])
            b.size = Rand(bs.size[1], bs.size[2])
            b.phase, b.freq = Rand(0, 6.28), Rand(4, 8)
            b.pop = nil
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
                b.x = b.x + (b.vx + self.speed * 0.3) * dt
                b.y = b.y + b.vy * dt
                if b.y >= h - b.size * 0.5 or b.x > edge - 2 then
                    b.pop = 0
                end
                b.tex:SetSize(b.size, b.size)
                b.tex:SetAlpha(bubbleAlpha)
            end
            b.tex:SetPoint("CENTER", parent, "BOTTOMLEFT", b.x + sin(b.phase + t * b.freq) * 1.5, b.y)
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
    local base = max(0, edge - amp)
    local opts, theme = self.opts, self.theme

    local fa, fb = theme.fillA, theme.fillB
    if theme.Colors then
        -- Animated themes pick their colours each frame from time and progress.
        local accent
        fa, fb, accent = theme:Colors(t, w > 0 and edge / w or 0)
        self.accent = accent
        if accent then
            self.glow:SetVertexColor(accent[1], accent[2], accent[3])
            self.swirlA:SetVertexColor(accent[1], accent[2], accent[3])
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

    local wobble = opts.waves and self.phys.ambient * (0.6 + energy) or 0
    local tipAlpha = 0.25 + 0.5 * min(1, energy)
    local rowH, back = self.rowH, edge
    for i = 1, CFG.rows do
        local row, tip = self.rows[i], self.tips[i]
        local off = self.pos[i] + wobble * (sin(t * 2.3 + i * 0.6) + 0.5 * sin(t * 3.7 - i * 1.1))
        local right = min(w, edge + off)
        if right < back then back = right end
        local rw = right - base
        if edge < 0.5 or rw < 0.5 then
            row:Hide()
            tip:Hide()
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
        end
    end

    self.back = max(0, back)

    -- Magic veins drift with the theme's flow; faster and brighter with energy and fill speed.
    local sw = self.swirl
    local swirlW = self.back
    if swirlW >= 1 and opts.swirl then
        local flow = 0.015 + 0.12 * energy + max(0, self.speed) / 2000
        local fu, fv = sw.flow[1], sw.flow[2]
        self.uA = (self.uA - flow * fu * dt) % 1
        self.vA = (self.vA - flow * fv * dt) % 1
        self.uB = (self.uB - flow * fu * 0.6 * dt) % 1
        self.vB = (self.vB + (0.03 - flow * fv * 0.6) * dt) % 1
        local spanU, spanV = swirlW / SWIRL_W, h / SWIRL_H
        self.swirlA:SetTexCoord(self.uA, self.uA + spanU, self.vA, self.vA + spanV)
        self.swirlB:SetTexCoord(self.uB, self.uB + spanU * 0.7, self.vB, self.vB + spanV * 0.7)
        self.swirlA:SetWidth(swirlW)
        self.swirlB:SetWidth(swirlW)
        local pulse = sw.pulse * (0.5 + 0.5 * sin(t * sw.pulseRate * 2 * pi))
        self.swirlA:SetAlpha(min(1, (0.12 + 0.3 * energy + pulse) * sw.alpha))
        self.swirlB:SetAlpha(min(1, (0.08 + 0.22 * energy + 0.05 * sin(t * 1.3) + pulse * 0.6) * sw.alpha))
        self.swirlA:Show()
        self.swirlB:Show()
    else
        self.swirlA:Hide()
        self.swirlB:Hide()
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
