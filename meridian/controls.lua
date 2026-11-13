-- The machine sheet: what the bar's instruments open. The charge set as a
-- figure and the processor, memory and disk as dials; sound and screen
-- light as lines of light to drag; the radios and do-not-disturb; the
-- music that is playing; a focus span; and the session.

local K = require("meridian.kit")
local S = require("machine")
local F = require("focus_timer")
local toasts = require("toasts")
local a, mix = K.a, K.mix
local t = K.theme
local caps, sans, serif = K.caps, K.sans, K.serif
local act = S.act

local M = {}
local WIDTH = 324

-- A session command that asks first: the first click arms it for a few
-- seconds, the second runs it.
local armed

local function arm_or_run(id, run)
    if armed and armed.id == id and os.time() - armed.at < 4 then
        armed = nil
        shell.close("controls")
        run()
    else
        armed = { id = id, at = os.time() }
        shell.after(4000, function()
            if armed and armed.id == id then armed = nil; shell.redraw() end
        end)
    end
    shell.redraw()
end

local function is_armed(id)
    return armed and armed.id == id and os.time() - armed.at < 4
end

-- The charge, or the mains, as a figure; the time it has left under it.
local function power(L)
    local level, status = S.battery()
    if not level then
        return shell.column { align = "start", gap = 2,
            caps("Power"),
            shell.text("Plugged in", { font = serif(24, true), letter_spacing = 0, shrink = 1 }) }
    end
    local charging = status == "Charging" or status == "Full"
    local low = level <= 15 and not charging
    local minutes, toward = S.battery_time()
    local note = status == "Full" and "full" or status:lower()
    if minutes then
        local h, m = minutes // 60, minutes % 60
        note = (h > 0 and string.format("%d h %02d", h, m) or string.format("%d min", m))
            .. (toward == "empty" and " left" or " to full")
    end
    return shell.column { align = "start", gap = 0,
        caps(charging and "Charging" or "Battery", { color = low and t.danger or nil }),
        shell.row { align = "end", gap = 1,
            shell.text(tostring(level), { font = serif(44), letter_spacing = 0,
                color = low and t.danger or t.text }),
            shell.text("%", { font = serif(20), color = a(t.text, 0.6), height = 34 }) },
        caps(note, { color = a(charging and L or t.text_dim, 0.75) }),
    }
end

-- "up 3 h 12"
local function uptime()
    local s = S.uptime()
    if not s then return "" end
    local d, h, m = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
    if d > 0 then return string.format("up %d d %d h", d, h) end
    if h > 0 then return string.format("up %d h %02d", h, m) end
    return string.format("up %d min", m)
end

local function meter(label, fraction, detail, L)
    return shell.column { align = "center", gap = 4, width = 58,
        shell.stack { width = 30, height = 30,
            shell.row { left = 0, right = 0, top = 0, bottom = 0, justify = "center",
                K.dial(fraction, fraction and fraction > 0.9 and t.danger or L, 30) },
            shell.row { left = 0, right = 0, top = 0, bottom = 0, justify = "center",
                shell.text(fraction and tostring(math.floor(fraction * 100 + 0.5)) or "–",
                    { font = sans("Bold", 7.5), color = a(t.text, 0.85) }) },
        },
        caps(label, { color = a(t.text_dim, 0.6), font = sans("Bold", 6.5), letter_spacing = 1.2 }),
        detail and caps(detail, { color = a(t.text_dim, 0.4), font = sans("Bold", 6), letter_spacing = 1 }) or false,
    }
end

local function machine(L)
    local mem, total = S.memory()
    local disk, free = S.disk()
    return shell.row { gap = 0, align = "start",
        meter("CPU", S.cpu(), nil, L),
        meter("Memory", mem, total and string.format("%.0f GB", total) or nil, L),
        meter("Disk", disk, free and string.format("%.0f GB left", free) or nil, L),
    }
end

-- A labelled line of light: the icon (a button too, for mute), the name,
-- the figure, and the line under them.
local function level_block(ctx, id, icon, label, value, L, set, opts)
    opts = opts or {}
    local hovered = ctx.hovered == id .. ":icon"
    return shell.column { align = "stretch", padding = { 4, 18, 2, 18 },
        shell.row { height = 22, gap = 9,
            shell.row { id = id .. ":icon", width = 18, height = 22, justify = "center",
                on_click = opts.on_icon,
                shell.icon(icon, { size = 14, stroke = 1.8, animate = "snappy",
                    color = hovered and L or a(t.text, opts.muted and 0.4 or 0.75) }) },
            caps(label, { color = a(t.text_dim, 0.75) }),
            shell.spacer(),
            shell.text(opts.muted and "muted" or tostring(math.floor(value + 0.5)), {
                font = serif(opts.muted and 14 or 17, opts.muted), letter_spacing = 0,
                color = a(t.text, opts.muted and 0.5 or 0.9) }),
        },
        shell.row { padding = { 0, 0, 0, 20 },
            K.level(id, math.min(value, 100), L, WIDTH - 36 - 20, set, { muted = opts.muted }) },
    }
end

local function media(ctx, L)
    local m = S.media()
    if not m then return false end
    local width = WIDTH - 36
    local f = m.length > 0 and K.clamp(m.position / m.length, 0, 1) or 0
    local function clock(s)
        s = math.floor(s)
        return string.format("%d:%02d", s // 60, s % 60)
    end
    local function control(id, icon, what, size)
        local hovered = ctx.hovered == id
        return shell.row { id = id, width = 30, height = 30, justify = "center",
            on_click = function() act.media(what); shell.redraw() end,
            shell.icon(icon, { size = size or 14, stroke = 1.8, animate = "snappy",
                color = hovered and L or a(t.text, 0.75) }) }
    end
    return shell.column { align = "stretch", padding = { 12, 18, 8, 18 }, gap = 2,
        caps(m.artist ~= "" and m.artist or "Now playing", { color = a(L, 0.85), max_width = width }),
        shell.text(m.title ~= "" and m.title or "Untitled", { font = serif(21, true), letter_spacing = 0,
            max_width = width }),
        shell.box { height = 6 },
        m.length > 0 and shell.canvas { width = width, height = 6,
            { "line", 0, 3, width, 3, stroke = a(t.text, 0.12) },
            { "line", 0, 3, width * f, 3, width = 1.6, cap = "round",
                stroke = shell.gradient("horizontal", a(L, 0.15), L) },
            { "circle", width * f, 3, 2.4, fill = mix(L, K.WHITE, 0.7) },
        } or false,
        shell.row { height = 30, gap = 2,
            m.length > 0 and caps(clock(m.position) .. " / " .. clock(m.length),
                { color = a(t.text_dim, 0.5) }) or false,
            shell.spacer(),
            control("mc:prev", "previous", "previous"),
            control("mc:play", m.playing and "pause" or "play", "play-pause", 16),
            control("mc:next", "next", "next"),
        },
    }
end

local function focus(ctx, L)
    if F.running() then
        return shell.row { height = 40, padding = { 0, 18 }, gap = 10,
            K.edge(L, 1, 10),
            caps("Focus", { color = L }),
            shell.text(F.left() .. " min", { font = serif(17), letter_spacing = 0 }),
            caps("until " .. os.date("%H:%M", select(2, F.span())), { color = a(t.text_dim, 0.6) }),
            shell.spacer(),
            K.button(ctx, "fc:stop", "Stop", L, { on_click = F.stop }),
        }
    end
    local buttons = {}
    for _, minutes in ipairs { 15, 25, 50 } do
        buttons[#buttons + 1] = K.button(ctx, "fc:" .. minutes, minutes .. " min", L,
            { on_click = function() F.start(minutes) end })
    end
    return shell.row { height = 40, padding = { 0, 12, 0, 18 }, gap = 2,
        caps("Focus for", { color = a(t.text_dim, 0.75) }),
        shell.spacer(),
        buttons,
    }
end

-- A restart arrow, which the built-in icons do not have.
local function restart_icon(color)
    return shell.canvas { width = 14, height = 14, view = { 24, 24 },
        { "arc", 12, 12, 8, 30, 320, stroke = color, width = 2, cap = "round" },
        { "path", "M 13 1.5 L 17.5 4.5 L 13.5 8", stroke = color, width = 2, cap = "round" },
    }
end

local function session(ctx, L, deps)
    local items = {
        deps.can_lock and { id = "s:lock", icon = "lock", label = "Lock", run = deps.lock } or false,
        { id = "s:sleep", icon = "moon", label = "Sleep", run = function()
            if deps.can_lock then deps.lock() end
            act.suspend()
        end },
        { id = "s:quit", icon = "close", label = "Log out", ask = true, run = shell.quit },
        { id = "s:reboot", label = "Restart", ask = true, run = act.reboot },
        { id = "s:off", icon = "power", label = "Power off", ask = true, run = act.poweroff },
    }
    local cells = {}
    for _, item in ipairs(items) do
        if item then
            local hovered = ctx.hovered == item.id
            local sure = is_armed(item.id)
            local color = sure and t.danger or (hovered and (item.ask and t.danger or L) or a(t.text, 0.6))
            cells[#cells + 1] = shell.stack {
                id = item.id, width = 58, height = 52,
                on_click = function()
                    if item.ask then
                        arm_or_run(item.id, item.run)
                    else
                        shell.close("controls")
                        item.run()
                    end
                end,
                K.rise(sure and t.danger or (item.ask and t.danger or L), (sure or hovered) and 0.7 or 0),
                shell.column { left = 0, right = 0, top = 8, bottom = 0, align = "center", gap = 7,
                    item.icon and shell.icon(item.icon, { size = 15, stroke = 1.8, color = color, animate = "snappy" })
                        or restart_icon(color),
                    caps(sure and "Sure?" or item.label, { font = sans("Bold", 6.5), letter_spacing = 1, color = color,
                        animate = "snappy" }),
                },
            }
        end
    end
    return shell.row { padding = { 4, 10, 10, 10 }, justify = "space-between", cells }
end

-- Install the sheet. `deps` gives what the rest of the UI owns:
--   lock()            lock the session
--   can_lock          whether locking is possible
function M.install(deps)
    shell.popup {
        name = "controls",
        anchor = { "top", "right" },
        margin = { top = K.BAR - 22 },
        input = "widgets",
        view = function(ctx)
            local L = K.light()
            local volume, muted = S.volume()
            local brightness = S.brightness()
            local wifi, ssid, wired = S.wifi()
            local bt, device = S.bluetooth()
            local row = function(id, label, opts)
                opts.light = L
                return K.menu_row(ctx, id, 34, label, opts)
            end
            local dnd = toasts.dnd()
            local playing = media(ctx, L)
            return K.panel(18, { 28, 10, K.SHADE + 12, K.SHADE }, {
                id = "controls-card", width = WIDTH, light = L,
                shell.row { padding = { 18, 18, 10, 18 }, align = "start",
                    power(L), shell.spacer(), machine(L) },
                shell.row { padding = { 0, 18, 6, 18 },
                    caps(uptime(), { color = a(t.text_dim, 0.45) }),
                    shell.spacer(),
                    caps(os.getenv("USER") or "", { color = a(t.text_dim, 0.45) }) },
                K.divider(),
                shell.box { height = 4 },
                volume and level_block(ctx, "lv:volume", muted and "mute" or "volume", "Sound", volume, L,
                    act.volume, { muted = muted, on_icon = function() act.mute(); shell.redraw() end }) or false,
                brightness and level_block(ctx, "lv:light", "sun", "Screen", brightness, L, act.brightness) or false,
                shell.box { height = 6 },
                K.divider(),
                shell.box { height = 4 },
                wifi ~= nil and row("t:wifi", "Wi-Fi", { icon = "wifi", lit = wifi, pip = wifi,
                    hint = wired and "cable" or (wifi and (ssid ~= "" and ssid or "not connected") or "off"),
                    on_click = function() act.wifi(); shell.redraw() end }) or false,
                bt ~= nil and row("t:bt", "Bluetooth", { icon = "bluetooth", lit = bt, pip = bt,
                    hint = bt and (device ~= "" and device or "on") or "off",
                    on_click = function() act.bluetooth(); shell.redraw() end }) or false,
                row("t:dnd", "Do not disturb", { icon = "bell", lit = dnd, pip = dnd,
                    hint = dnd and "only urgent" or nil,
                    on_click = function() toasts.set_dnd(not dnd) end }),
                shell.box { height = 4 },
                K.divider(),
                playing,
                playing and K.divider() or false,
                focus(ctx, L),
                K.divider(),
                session(ctx, L, deps),
            })
        end,
    }
end

-- The bar's instruments: the radios, the sound and the charge, side by
-- side on one tab.
function M.instruments(ctx, L)
    local parts = {}
    local wifi, _, wired = S.wifi()
    if wired then
        parts[#parts + 1] = caps("lan", { color = a(t.text, 0.7) })
    elseif wifi ~= nil then
        parts[#parts + 1] = shell.icon("wifi", { size = 14, stroke = 1.9, color = a(t.text, wifi and 0.75 or 0.25) })
    end
    local bt, device = S.bluetooth()
    if bt then
        parts[#parts + 1] = shell.icon("bluetooth", { size = 14, stroke = 1.9,
            color = device ~= "" and a(t.text, 0.75) or a(t.text, 0.35) })
    end
    local volume, muted = S.volume()
    if volume then
        parts[#parts + 1] = shell.icon(muted and "mute" or "volume", { size = 14, stroke = 1.9,
            color = a(t.text, muted and 0.35 or 0.75) })
    end
    local level, status = S.battery()
    if level then
        local charging = status == "Charging" or status == "Full"
        local low = level <= 15 and not charging
        parts[#parts + 1] = shell.row { gap = 5,
            K.dial(level / 100, low and t.danger or (charging and L or a(t.text, 0.7)), 15),
            shell.text(tostring(level), { font = serif(14.5), letter_spacing = 0,
                color = low and t.danger or a(t.text, 0.9), height = K.BAR - 4 }) }
    end
    if #parts == 0 then parts[1] = shell.icon("sliders", { size = 14, stroke = 1.9, color = a(t.text, 0.7) }) end
    return parts
end

return M
