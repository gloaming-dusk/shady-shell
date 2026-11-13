-- Meridian's lock screen: night over every output, the day line run
-- across it as a horizon with the sun standing on it at this hour, the
-- time set large above, and below it a line the password is typed onto, a
-- point of light for each character. Checking it, the fingerprint reader
-- and taking a lock over are shady-shell's lockscreen module; this file
-- only draws.

local K = require("meridian.kit")
local S = require("machine")
local a, mix = K.a, K.mix
local t = K.theme
local caps, serif = K.caps, K.serif

local M = {}

-- The horizon: the day line across the screen, the sun on it.
local function horizon(L, width, y)
    local h = K.hour()
    local x = width * h / 24
    local shapes = {
        { "rect", 0, y, width, 400, fill = shell.gradient("vertical", a(K.BLACK, 0.25), a(K.BLACK, 0)) },
        { "line", 0, y + 0.5, width, y + 0.5, stroke = a(t.text, 0.12) },
    }
    for tick = 1, 23 do
        local tx = math.floor(width * tick / 24) + 0.5
        local tall = tick % 6 == 0
        shapes[#shapes + 1] = { "line", tx, y, tx, y - (tall and 9 or 5),
            stroke = tick <= h and a(L, tall and 0.7 or 0.4) or a(t.text, tall and 0.24 or 0.12) }
    end
    shapes[#shapes + 1] = { "line", 0, y + 0.25, x, y + 0.25, width = 1.6,
        stroke = shell.gradient("horizontal", a(L, 0.05), a(L, 0.5), L) }
    shapes[#shapes + 1] = { "circle", x, y, 260, fill = shell.gradient("radial", a(L, 0.22), a(L, 0.06), a(L, 0)) }
    shapes[#shapes + 1] = { "circle", x, y, 26, fill = shell.gradient("radial", a(L, 0.9), a(L, 0)) }
    shapes[#shapes + 1] = { "circle", x, y, 6, fill = mix(L, K.WHITE, 0.85) }
    return shell.canvas { left = 0, top = 0, right = 0, bottom = 0, shapes }
end

-- The password line: a hairline, a point of light for each character.
local function field(L, LK)
    local n = LK.length
    local width = 280
    local lit = LK.error and t.danger or L
    local shapes = {
        { "line", 0, 20.5, width, 20.5, stroke = shell.gradient("horizontal",
            a(lit, 0), a(lit, n > 0 and 0.9 or 0.4), a(lit, 0)) },
    }
    local shown = math.min(n, 24)
    local gap = 11
    local x0 = width / 2 - (shown - 1) * gap / 2
    for i = 1, shown do
        local x = x0 + (i - 1) * gap
        shapes[#shapes + 1] = { "circle", x, 11, 6, fill = shell.gradient("radial", a(L, 0.5), a(L, 0)) }
        shapes[#shapes + 1] = { "circle", x, 11, 2.4, fill = mix(L, K.WHITE, 0.8) }
    end
    return shell.stack {
        key = "lock:field:" .. LK.attempts, width = width, height = 24,
        enter = LK.attempts > 0 and { translate = { 16, 0 } } or nil, animate = "bouncy",
        shell.canvas { left = 0, top = 0, right = 0, bottom = 0, shapes },
        n == 0 and shell.row { left = 0, right = 0, top = 0, height = 18, justify = "center",
            shell.text(LK.busy and "Checking…" or "Type to unlock", {
                font = serif(15, true), letter_spacing = 0, color = a(t.text_dim, 0.6) }) } or false,
    }
end

-- Install it; returns the lockscreen handle (lock(), available()).
function M.install()
    return require("lockscreen").install {
        name = "lock",
        before_lock = function()
            for _, name in ipairs { "launcher", "quick", "controls", "menu" } do shell.close(name) end
        end,
        view = function(ctx, LK)
            local L = K.light()
            local w, h = ctx.width or 1280, ctx.height or 800
            local y = math.floor(h * 0.6)
            local level, status = S.battery()
            local user = os.getenv("USER") or ""
            return shell.stack {
                width = w, height = h,
                background = shell.gradient("vertical", mix(t.surface, K.BLACK, 0.6), mix(t.surface, K.BLACK, 0.3)),
                horizon(L, w, y),
                shell.column {
                    left = 0, right = 0, bottom = h - y + 46, align = "center", gap = 0,
                    enter = { opacity = 0, translate = { 0, -16 } }, animate = "gentle",
                    caps(shell.date("%A · %d %B"), { color = a(t.text, 0.62), letter_spacing = 2.4 }),
                    shell.text(shell.date("%H:%M"), { font = serif(150), letter_spacing = -2 }),
                },
                shell.column {
                    left = 0, right = 0, top = y + 54, align = "center", gap = 14,
                    enter = { opacity = 0, translate = { 0, 16 } }, animate = "gentle",
                    caps(user, { color = a(t.text_dim, 0.7), letter_spacing = 2.4 }),
                    field(L, LK),
                    shell.text(LK.message ~= "" and LK.message or " ", {
                        font = serif(15, true), letter_spacing = 0,
                        color = LK.error and t.danger or a(t.text_dim, 0.7) }),
                },
                level and shell.row { right = 32, bottom = 26, gap = 6,
                    K.dial(level / 100, (status == "Charging" or status == "Full") and L or a(t.text, 0.7), 14),
                    caps(level .. "%", { color = a(t.text_dim, 0.7) }) } or false,
                shell.row { left = 32, bottom = 26, gap = 8,
                    K.mark(L, 14), caps("Locked", { color = a(t.text_dim, 0.5) }) },
            }
        end,
    }
end

return M
