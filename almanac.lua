-- Dates and the sky, for calendars, clocks and desktop widgets. Pure
-- arithmetic on os.time; nothing is drawn.
--
--   month(year, month[, monday_first])  weeks of the month: a list of 7-day
--       rows, each day {day=, today=, weekend=} or false for blanks
--   month_name(m)                    "January" .. "December"
--   shift(year, month, by)           the month `by` months away
--   moon_phase([time])               0 new .. 0.5 full .. 1 (fraction of the cycle)
--   moon_lit(phase)                  how much of the disc is lit, 0..1
--   moon_name(phase)                 "Waxing crescent", ...
--   moon_path(phase, cx, cy, r)      an SVG-style path of the lit part, as
--                                    seen from the north, for shell.canvas
--   year_day([time])                 day of the year, and days in the year
--   week([time])                     ISO week number

local M = {}

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December" }

function M.month_name(m) return MONTHS[m] end

local function noon(year, month, day)
    return os.date("*t", os.time { year = year, month = month, day = day, hour = 12 })
end

function M.shift(year, month, by)
    local m = month - 1 + by
    return year + m // 12, m % 12 + 1
end

function M.month(year, month, monday_first)
    if monday_first == nil then monday_first = true end
    local now = os.date("*t")
    local first = noon(year, month, 1)
    local count = noon(year, month + 1, 0).day
    local lead = monday_first and (first.wday + 5) % 7 or first.wday - 1
    local weeks, week = {}, {}
    for _ = 1, lead do week[#week + 1] = false end
    for day = 1, count do
        local column = #week + 1
        week[column] = {
            day = day,
            today = year == now.year and month == now.month and day == now.day,
            weekend = monday_first and column >= 6 or (column == 1 or column == 7),
        }
        if #week == 7 then weeks[#weeks + 1] = week; week = {} end
    end
    if #week > 0 then
        while #week < 7 do week[#week + 1] = false end
        weeks[#weeks + 1] = week
    end
    return weeks
end

-- ---- the moon -------------------------------------------------------------

local SYNODIC = 29.530588853
local NEW_MOON = 947182440 -- 6 January 2000, 18:14 UTC

function M.moon_phase(when)
    return (((when or os.time()) - NEW_MOON) / 86400 / SYNODIC) % 1
end

function M.moon_lit(phase) return (1 - math.cos(phase * 2 * math.pi)) / 2 end

local PHASES = { "New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
    "Full moon", "Waning gibbous", "Last quarter", "Waning crescent" }

function M.moon_name(phase) return PHASES[math.floor(phase * 8 + 0.5) % 8 + 1] end

-- The lit side's limb, then the terminator back across the disc, in cubic
-- quarter-ellipses.
function M.moon_path(phase, cx, cy, r)
    local k = 0.5523
    local waxing = phase < 0.5
    local q = waxing and phase or 1 - phase
    local s = waxing and 1 or -1
    local tx = r * math.cos(q * 2 * math.pi)
    local function X(dx) return string.format("%.2f", cx + s * dx) end
    local function Y(dy) return string.format("%.2f", cy + dy) end
    return table.concat({
        "M", X(0), Y(-r),
        "C", X(k * r), Y(-r), X(r), Y(-k * r), X(r), Y(0),
        "C", X(r), Y(k * r), X(k * r), Y(r), X(0), Y(r),
        "C", X(k * tx), Y(r), X(tx), Y(k * r), X(tx), Y(0),
        "C", X(tx), Y(-k * r), X(k * tx), Y(-r), X(0), Y(-r), "Z",
    }, " ")
end

-- ---- the year ---------------------------------------------------------------

function M.year_day(when)
    local d = os.date("*t", when)
    return d.yday, noon(d.year, 12, 31).yday
end

function M.week(when) return tonumber(os.date("%V", when)) end

return M
