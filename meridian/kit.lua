-- Meridian's vocabulary: the light of the hour, small capitals, cards, rows
-- and the instruments every part of the default UI is drawn with. Required
-- by default.lua and the modules next to this file; it reads
-- `shell.options` when it is first required.

local K = {}

local options = shell.options or {}
local t = shell.theme
local a, mix = shell.alpha, shell.mix

K.options, K.theme = options, t
K.a, K.mix = a, mix
K.WHITE, K.BLACK = "#ffffff", "#000000"
local WHITE, BLACK = K.WHITE, K.BLACK
K.BAR = 38

function K.sans(weight, size) return "Manrope " .. weight .. " " .. size end
function K.serif(size, italic) return "Instrument Serif " .. (italic and "Italic " or "") .. size end
local sans = K.sans

-- Small capitals with air between them: labels, dates, hints.
function K.caps(text, props)
    props = props or {}
    props.font = props.font or sans("Bold", 7.5)
    props.letter_spacing = props.letter_spacing or 1.5
    props.color = props.color or a(t.text_dim, 0.85)
    return shell.text(text:upper(), props)
end
local caps = K.caps

-- ---- the light ---------------------------------------------------------

-- The hour of the day as a number, 23.5 at half past eleven at night.
-- Reading the clock here makes every view that asks repaint each minute.
function K.hour()
    if options.hour then return options.hour % 24 end
    return tonumber(shell.date("%H")) + tonumber(shell.date("%M")) / 60
end

local NIGHT = mix(t.accent_2, WHITE, 0.38)
local SKY = {
    { 0, NIGHT }, { 4.5, NIGHT }, { 6.5, "#FF9A7B" }, { 8, "#FFD49A" },
    { 10, t.accent }, { 15.5, t.accent }, { 17.5, "#FFC46B" }, { 19, "#FF7F6E" },
    { 20.5, "#B892FF" }, { 22.5, NIGHT }, { 24, NIGHT },
}

-- The colour of the light at this hour.
function K.light()
    if options.light == false then return t.accent end
    local h = K.hour()
    for i = 2, #SKY do
        local from, to = SKY[i - 1], SKY[i]
        if h <= to[1] then return mix(from[2], to[2], (h - from[1]) / (to[1] - from[1])) end
    end
    return NIGHT
end

-- Light rising from the line a widget stands on: a low dome, brightest
-- where it touches the line. It fades in and out with its `opacity`.
function K.rise(color, strength)
    return shell.canvas {
        left = 0, right = 0, top = 0, bottom = 0, view = { 100, 50 },
        animate = "smooth", opacity = strength,
        { "circle", 50, 50, 50, fill = shell.gradient("radial", a(color, 0.42), a(color, 0.12), a(color, 0)) },
    }
end

-- The mark of the chosen row: a short line of light at its left edge.
function K.edge(color, strength, inset)
    return shell.box { left = 0, top = inset, bottom = inset, width = 2, animate = "snappy",
        background = shell.gradient("vertical", a(color, 0), a(color, strength), a(color, strength), a(color, 0)) }
end

-- Light falling in from the left edge of a row.
function K.wash(color, strength)
    return shell.gradient("horizontal", a(color, 0.2 * strength), a(color, 0.05 * strength), a(color, 0))
end
local wash, edge = K.wash, K.edge

-- The mark: a disc, half of it in the light.
function K.mark(L, size)
    return shell.canvas {
        width = size, height = size, view = { 20, 20 },
        { "arc", 10, 10, 7.5, 180, 360, fill = L },
        { "circle", 10, 10, 7.5, stroke = a(t.text, 0.85), width = 1.4 },
    }
end

-- ---- cards -------------------------------------------------------------

-- Popups grow out of a slightly smaller, lifted, transparent card and go
-- back into it when they close.
K.POP = { opacity = 0, scale = 0.96, translate = { 0, -6 } }
-- Room around a card for its shadow; less towards a screen edge it hugs.
K.SHADE = 40

-- The card every popup is: dark, borderless but for a hairline, lit along
-- its top edge and standing off the desktop on a soft shadow. `room` is the
-- space kept around it, {top, right, bottom, left}.
function K.panel(radius, room, props)
    local L = props.light or K.light()
    props.light = nil
    local alpha = options.panel_opacity or 0.97
    local id = props.id or "card"
    props.id = nil
    props.align = props.align or "stretch"
    local card = shell.stack {
        id = id, radius = radius,
        animate = "snappy", enter = K.POP, exit = K.POP,
        background = shell.gradient("vertical", a(mix(t.surface, WHITE, 0.055), alpha), a(t.surface, alpha)),
        border = a(t.text, 0.075),
        shadow = { 0, 18, a(BLACK, 0.6), 26 },
        -- The light of the hour, falling over the top edge.
        shell.box { top = 0, left = 0, right = 0, height = 120, radius = radius,
            background = shell.gradient("vertical", a(L, 0.085), a(L, 0.015), a(L, 0)) },
        shell.row { top = 0, left = radius, right = radius, height = 1,
            shell.spacer { height = 1, background = shell.gradient("horizontal",
                a(L, 0), a(L, 0.75), a(L, 0)) } },
        shell.column(props),
    }
    return shell.column { padding = room, align = "stretch", card }
end

-- A menu row: lit from the left when hovered, optional pip, danger colouring.
function K.menu_row(ctx, id, height, label, opts)
    opts = opts or {}
    local L = opts.danger and t.danger or opts.light
    local hovered = ctx.hovered == id
    local strong = hovered or opts.strong
    return shell.stack {
        id = id, height = height, on_click = opts.on_click,
        shell.box { left = 0, right = 0, top = 2, bottom = 2, animate = "snappy",
            background = hovered and wash(L, 1) or wash(L, 0) },
        edge(L, hovered and 1 or 0, 6),
        shell.row {
            left = 0, right = 0, top = 0, bottom = 0, padding = { 0, 18 }, gap = 9,
            opts.icon and shell.icon(opts.icon, { size = 14, stroke = 1.8, animate = "snappy",
                color = opts.lit and L or a(t.text, strong and 0.9 or 0.5) }) or false,
            shell.text(label, {
                animate = "snappy", shrink = 1,
                font = sans(strong and "Bold" or "Medium", 9.5),
                color = opts.danger and a(t.danger, hovered and 1 or 0.85)
                    or a(t.text, strong and 1 or 0.72),
            }),
            shell.spacer(),
            opts.hint and caps(opts.hint, { color = a(t.text_dim, 0.55), max_width = 150, shrink = 1 }) or false,
            opts.pip ~= nil and shell.pip { key = id .. ":pip", radius = 2.6, lit = opts.pip,
                color = opts.pip and L or nil } or false,
            opts.extra or false,
        },
    }
end

function K.divider(inset)
    return shell.row { height = 1, padding = { 0, inset or 18 },
        shell.spacer { height = 1, background = a(t.text, 0.07) } }
end

-- A heading inside a card: small capitals, and something on the right.
function K.heading(label, right)
    return shell.row { height = 30, padding = { 10, 18, 0, 18 },
        caps(label), shell.spacer(), right or false }
end

-- Small capitals that light up under the pointer: the card's buttons.
function K.button(ctx, id, label, L, opts)
    opts = opts or {}
    local hovered = ctx.hovered == id
    local color = opts.danger and t.danger or L
    return shell.row {
        id = id, height = opts.height or 24, padding = { 0, opts.pad or 6 }, gap = 6,
        on_click = opts.on_click,
        opts.icon and shell.icon(opts.icon, { size = 13, stroke = 1.8, animate = "snappy",
            color = (hovered or opts.lit) and color or a(t.text, 0.55) }) or false,
        label ~= "" and caps(label, { animate = "snappy",
            color = (hovered or opts.lit) and color or a(t.text_dim, opts.dim or 0.7) }) or false,
    }
end

-- ---- instruments -------------------------------------------------------

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
K.clamp = clamp

-- A level as a line of light: a hairline, lit up to the value, with a sun
-- standing where the value is. Drag along it, click on it or scroll over
-- it; `set` gets 0..100.
function K.level(id, value, L, width, set, opts)
    opts = opts or {}
    local v = clamp(value or 0, 0, 100)
    local y, inset = 13, 7
    local x = inset + (width - 2 * inset) * v / 100
    local lit = opts.muted and a(t.text, 0.35) or L
    local shapes = {
        { "line", inset, y, width - inset, y, stroke = a(t.text, 0.12) },
    }
    for tick = 1, 9 do
        local tx = math.floor(inset + (width - 2 * inset) * tick / 10) + 0.5
        shapes[#shapes + 1] = { "line", tx, y + 1, tx, y + (tick == 5 and 5 or 3),
            stroke = tick * 10 <= v and a(lit, 0.6) or a(t.text, 0.14) }
    end
    shapes[#shapes + 1] = { "line", inset, y, x, y, width = 1.6, cap = "round",
        stroke = shell.gradient("horizontal", a(lit, 0.12), lit) }
    shapes[#shapes + 1] = { "circle", x, y, 13, fill = shell.gradient("radial", a(lit, 0.5), a(lit, 0.1), a(lit, 0)) }
    shapes[#shapes + 1] = { "circle", x, y, 3.4, fill = opts.muted and t.surface or mix(lit, WHITE, 0.8),
        stroke = opts.muted and a(t.text, 0.5) or nil, width = 1.4 }
    local function at(info) return clamp((info.px - inset) / (width - 2 * inset) * 100, 0, 100) end
    return shell.stack {
        id = id, width = width, height = 26,
        on_drag = function(info) set(at(info)); shell.redraw() end,
        on_scroll = function(dy) set(clamp(v - dy / 4, 0, 100)); shell.redraw() end,
        shell.canvas { left = 0, top = 0, right = 0, bottom = 0, shapes },
    }
end

-- A small dial: a faint ring and an arc of light for a fraction, 0..1.
function K.dial(fraction, color, size)
    local f = clamp(fraction or 0, 0, 1)
    return shell.canvas {
        width = size, height = size, view = { 20, 20 },
        { "circle", 10, 10, 8, stroke = a(t.text, 0.12), width = 2 },
        f > 0.005 and { "arc", 10, 10, 8, 0, 360 * f, stroke = color, width = 2, cap = "round" } or false,
    }
end

-- ---- the sky ---------------------------------------------------------

-- The moon as it stands tonight (as seen from the north): its lit part
-- filled with `color`, the rest a faint disc.
function K.moon(phase, color, size)
    local almanac = require("almanac")
    return shell.canvas {
        width = size, height = size, view = { 20, 20 },
        { "circle", 10, 10, 8, fill = a(t.text, 0.06), stroke = a(t.text, 0.22), width = 0.8 },
        almanac.moon_lit(phase) > 0.01 and { "path", almanac.moon_path(phase, 10, 10, 8), fill = color } or false,
    }
end

return K
