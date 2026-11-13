-- The month, for the day sheet, and the almanac that stands on the desktop:
-- the date set large, the moon as it is tonight, and the year as a line
-- lit up to today. The dates and the sky come from shady-shell's almanac
-- module; this file only draws them.

local K = require("meridian.kit")
local almanac = require("almanac")
local a, mix = K.a, K.mix
local t = K.theme
local caps, sans, serif = K.caps, K.sans, K.serif

local C = {}

-- The month shown, as months from this one: 0 is now.
local offset = 0

function C.reset() offset = 0 end

local function turn(by)
    offset = offset + by
    shell.redraw()
end

-- A month grid `width` wide, weeks starting on Monday. Today stands in the
-- light, rising from under its figure.
function C.month(ctx, L, width)
    local now = os.date("*t")
    local year, month = almanac.shift(now.year, now.month, offset)
    local cell = math.floor(width / 7)

    local head = shell.row {
        height = 34, padding = { 0, 4 }, gap = 8,
        shell.text(almanac.month_name(month), { font = serif(19), letter_spacing = 0 }),
        caps(tostring(year), { color = a(t.text_dim, 0.6) }),
        shell.spacer(),
        offset ~= 0 and K.button(ctx, "cal:today", "Today", L, { on_click = function() turn(-offset) end }) or false,
        K.button(ctx, "cal:prev", "‹", L, { pad = 8, on_click = function() turn(-1) end }),
        K.button(ctx, "cal:next", "›", L, { pad = 8, on_click = function() turn(1) end }),
    }

    local names = {}
    for i, d in ipairs { "M", "T", "W", "T", "F", "S", "S" } do
        names[#names + 1] = shell.row { width = cell, justify = "center",
            caps(d, { color = a(t.text_dim, i >= 6 and 0.4 or 0.6) }) }
    end

    local weeks = {}
    for _, days in ipairs(almanac.month(year, month)) do
        local row = {}
        for _, d in ipairs(days) do
            row[#row + 1] = not d and shell.box { width = cell, height = 26 } or shell.stack {
                width = cell, height = 26,
                d.today and K.rise(L, 1) or false,
                d.today and shell.box { left = 9, right = 9, bottom = 0, height = 2,
                    background = shell.gradient("horizontal", a(L, 0), L, a(L, 0)) } or false,
                shell.row { left = 0, right = 0, top = 0, bottom = 0, justify = "center",
                    shell.text(tostring(d.day), {
                        font = d.today and sans("ExtraBold", 9) or sans("Medium", 9),
                        color = d.today and t.text or a(t.text, d.weekend and 0.4 or 0.72),
                    }) },
            }
        end
        weeks[#weeks + 1] = shell.row { row }
    end

    return shell.column {
        id = "cal", align = "stretch",
        on_scroll = function(dy)
            if math.abs(dy) >= 1 then turn(dy > 0 and 1 or -1) end
        end,
        head,
        shell.row { height = 20, names },
        weeks,
    }
end

-- ---- the almanac on the desktop -----------------------------------------

-- The year as a line: a tick for each month, lit up to today.
local function year_line(L, width)
    local now = os.date("*t")
    local today, length = almanac.year_day()
    local x = width * (today - 0.5) / length
    local shapes = { { "line", 0, 6.5, width, 6.5, stroke = a(t.text, 0.16) } }
    for m = 2, 12 do
        local day = almanac.year_day(os.time { year = now.year, month = m, day = 1, hour = 12 })
        local tx = math.floor(width * (day - 1) / length) + 0.5
        shapes[#shapes + 1] = { "line", tx, 6.5, tx, m == 7 and 1.5 or 3.5,
            stroke = day <= today and a(L, 0.7) or a(t.text, 0.22) }
    end
    shapes[#shapes + 1] = { "line", 0, 6.25, x, 6.25, width = 1.5,
        stroke = shell.gradient("horizontal", a(L, 0.1), L) }
    shapes[#shapes + 1] = { "circle", x, 6.5, 14, fill = shell.gradient("radial", a(L, 0.45), a(L, 0)) }
    shapes[#shapes + 1] = { "circle", x, 6.5, 2.8, fill = mix(L, K.WHITE, 0.8) }
    return shell.canvas { width = width, height = 12, shapes }
end

-- Install the almanac: a `bottom` layer surface in the lower left corner of
-- every output, over the wallpaper and under the windows. It takes no input.
function C.install_desk()
    shell.popup {
        name = "meridian-desk",
        outputs = "all",
        layer = "bottom",
        anchor = { "bottom", "left" },
        margin = { bottom = 28, left = 36 },
        input = "widgets",
        view = function()
            local L = K.light() -- reads the clock: repaints each minute
            local now = os.date("*t")
            local phase = almanac.moon_phase()
            local today, length = almanac.year_day()
            return shell.column {
                align = "start", gap = 0, padding = { 24, 24 },
                enter = { opacity = 0, translate = { 0, 12 } }, animate = "gentle",
                caps(os.date("%A") .. " · week " .. almanac.week(), {
                    color = a(t.text, 0.62), letter_spacing = 2.2 }),
                shell.text(string.format("%d %s", now.day, almanac.month_name(now.month)), {
                    font = serif(58), letter_spacing = -0.5, color = a(t.text, 0.94) }),
                shell.box { height = 4 },
                year_line(L, 300),
                shell.box { height = 10 },
                shell.row {
                    gap = 10,
                    K.moon(phase, mix(t.text, L, 0.25), 18),
                    caps(string.format("%s · %d%%", almanac.moon_name(phase),
                        math.floor(almanac.moon_lit(phase) * 100 + 0.5)), { color = a(t.text, 0.55) }),
                    shell.box { width = 6 },
                    caps(string.format("Day %d · %d to go", today, length - today),
                        { color = a(t.text, 0.4) }),
                },
            }
        end,
    }
end

return C
