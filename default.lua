-- shady-shell's default UI, "Meridian": the shell as an instrument for
-- reading the day.
--
-- The bar stands on one hairline, the day from midnight to midnight, and a
-- small sun travels along it. Its colour is the colour of the hour (blue at
-- night, rose at dawn, the theme's accent by day, amber and violet at dusk)
-- and everything that is active is lit by it: the focused window, the
-- selected row, the edge of every card. Nothing has a box drawn around it.
--
-- To customise, copy this file to ~/.config/shady/shell.lua (or point
-- SHADY_SHELL_CONFIG at your own file). The shell reloads it whenever it
-- changes. The API is documented in docs/SHELL_LUA_API.md.

-- Options a config can set before dofile()-ing this file; see
-- examples/aurora.lua.
--   light          false: always the theme's accent, whatever the hour
--   hour           a fixed hour (0..24) for the light, e.g. 6.5 for dawn
--   bar_opacity, panel_opacity, bar_shader, bar_uniforms, focus_shader,
--   focus_uniforms, bar_extra
local options = shell.options or {}
local t = shell.theme
local WHITE, BLACK = "#ffffff", "#000000"
local BAR = 38
local a, mix = shell.alpha, shell.mix

shell.fonts(shell.data_dir .. "/fonts")
local function sans(weight, size) return "Manrope " .. weight .. " " .. size end
local function serif(size, italic) return "Instrument Serif " .. (italic and "Italic " or "") .. size end

-- Small capitals with air between them: labels, dates, hints.
local function caps(text, props)
    props = props or {}
    props.font = props.font or sans("Bold", 7.5)
    props.letter_spacing = props.letter_spacing or 1.5
    props.color = props.color or a(t.text_dim, 0.85)
    return shell.text(text:upper(), props)
end

-- ---- the light ---------------------------------------------------------

-- The hour of the day as a number, 23.5 at half past eleven at night.
-- Reading the clock here makes every view that asks repaint each minute.
local function hour()
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
local function light()
    if options.light == false then return t.accent end
    local h = hour()
    for i = 2, #SKY do
        local from, to = SKY[i - 1], SKY[i]
        if h <= to[1] then return mix(from[2], to[2], (h - from[1]) / (to[1] - from[1])) end
    end
    return NIGHT
end

-- Light rising from the line a widget stands on: a low dome, brightest
-- where it touches the line. It fades in and out with its `opacity`.
local function rise(color, strength)
    return shell.canvas {
        left = 0, right = 0, top = 0, bottom = 0, view = { 100, 50 },
        animate = "smooth", opacity = strength,
        { "circle", 50, 50, 50, fill = shell.gradient("radial", a(color, 0.42), a(color, 0.12), a(color, 0)) },
    }
end

-- The mark of the chosen row: a short line of light at its left edge.
local function edge(color, strength, inset)
    return shell.box { left = 0, top = inset, bottom = inset, width = 2, animate = "snappy",
        background = shell.gradient("vertical", a(color, 0), a(color, strength), a(color, strength), a(color, 0)) }
end

-- Light falling in from the left edge of a row.
local function wash(color, strength)
    return shell.gradient("horizontal", a(color, 0.2 * strength), a(color, 0.05 * strength), a(color, 0))
end

-- The mark: a disc, half of it in the light.
local function mark(L, size)
    return shell.canvas {
        width = size, height = size, view = { 20, 20 },
        { "arc", 10, 10, 7.5, 180, 360, fill = L },
        { "circle", 10, 10, 7.5, stroke = a(t.text, 0.85), width = 1.4 },
    }
end

-- ---- cards -------------------------------------------------------------

-- Popups grow out of a slightly smaller, lifted, transparent card and go
-- back into it when they close.
local POP = { opacity = 0, scale = 0.96, translate = { 0, -6 } }
-- Room around a card for its shadow; less towards a screen edge it hugs.
local SHADE = 40

-- The card every popup is: dark, borderless but for a hairline, lit along
-- its top edge and standing off the desktop on a soft shadow. `room` is the
-- space kept around it, {top, right, bottom, left}.
local function panel(radius, room, props)
    local L = props.light or light()
    props.light = nil
    local alpha = options.panel_opacity or 0.97
    local id = props.id or "card"
    props.id = nil
    props.align = props.align or "stretch"
    local card = shell.stack {
        id = id, radius = radius,
        animate = "snappy", enter = POP, exit = POP,
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
local function menu_row(ctx, id, height, label, opts)
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
            shell.text(label, {
                animate = "snappy",
                font = sans(strong and "Bold" or "Medium", 9.5),
                color = opts.danger and a(t.danger, hovered and 1 or 0.85)
                    or a(t.text, strong and 1 or 0.72),
            }),
            shell.spacer(),
            opts.pip and shell.pip { radius = 2.6, lit = true, color = L } or false,
            opts.hint and caps(opts.hint, { color = a(t.text_dim, 0.55) }) or false,
        },
    }
end

local function divider(inset)
    return shell.row { height = 1, padding = { 0, inset or 18 },
        shell.spacer { height = 1, background = a(t.text, 0.07) } }
end

-- ---- launcher ----------------------------------------------------------

local launcher = { search = "", selected = 1 }

local function matches()
    return shell.apps(launcher.search, 8)
end

local function launch(app)
    shell.close("launcher")
    shell.launch(app)
end

local function toggle_launcher()
    launcher.search, launcher.selected = "", 1
    shell.toggle("launcher")
end

shell.on("launcher", toggle_launcher)

-- What an application runs, without where it is installed or its flags.
local function command(exec)
    local first = exec:match("^%S+") or exec
    return first:match("([^/]+)$") or first
end

shell.popup {
    name = "launcher",
    width = 640 + 2 * SHADE, height = 528 + 2 * SHADE,
    keyboard = "exclusive",
    input = "widgets",
    text_input = true, -- input methods (e.g. Hangul) type into the search
    view = function(ctx)
        local L = light()
        local apps = matches()
        if launcher.selected > #apps then launcher.selected = math.max(#apps, 1) end
        local results = {}
        for i, app in ipairs(apps) do
            local id = "app:" .. i
            local selected = i == launcher.selected
            local hovered = ctx.hovered == id
            results[#results + 1] = shell.stack {
                id = id, height = 44,
                on_click = function() launch(app) end,
                shell.box { left = 0, right = 0, top = 1, bottom = 1, animate = "snappy",
                    background = selected and wash(L, 1) or wash(t.text, hovered and 0.35 or 0) },
                edge(L, selected and 1 or 0, 7),
                shell.row {
                    left = 0, right = 0, top = 0, bottom = 0, padding = { 0, 18, 0, 20 }, gap = 16,
                    shell.text(string.format("%02d", i), { animate = "snappy", width = 18,
                        font = sans("Bold", 7.5), letter_spacing = 1,
                        color = selected and L or a(t.text_dim, 0.5) }),
                    shell.text(app.name, { animate = "snappy", shrink = 1,
                        font = sans(selected and "Bold" or "Medium", 10.5),
                        color = a(t.text, selected and 1 or (hovered and 0.9 or 0.7)) }),
                    shell.spacer(),
                    shell.text(command(app.exec), { max_width = 220, font = sans("Medium", 8.5),
                        color = a(t.text_dim, selected and 0.9 or 0.5) }),
                    shell.text("↵", { animate = "snappy", width = 12, font = sans("Bold", 10),
                        color = a(L, selected and 1 or 0) }),
                },
            }
        end
        if #apps == 0 then
            results[1] = shell.column {
                align = "start", padding = { 18, 20 }, gap = 6,
                shell.text("Nothing by that name.", { font = serif(17, true), color = a(t.text, 0.9) }),
                shell.text("Try another name, or the command it runs.",
                    { font = sans("Medium", 9), color = t.text_dim }),
            }
        end

        -- The query is the headline. What an input method is still
        -- composing shows in the colour of the light.
        local preedit = ctx.preedit or ""
        local query = (launcher.search ~= "" or preedit ~= "") and shell.row {
            gap = 1,
            shell.text(launcher.search, { font = serif(25), letter_spacing = 0 }),
            preedit ~= "" and shell.text(preedit, { font = serif(25), letter_spacing = 0, color = L }) or false,
            shell.box { width = 1.5, height = 30, background = L, caret = true,
                shadow = { 0, 0, a(L, 0.55), 4 } },
        } or shell.row {
            shell.box { width = 1.5, height = 30, background = L, caret = true,
                shadow = { 0, 0, a(L, 0.55), 4 } },
            shell.box { width = 8 },
            shell.text("What next?", { font = serif(25, true), letter_spacing = 0,
                color = a(t.text_dim, 0.6) }),
        }

        return panel(20, SHADE, {
            id = "launcher-card", width = 640, height = 528, light = L,
            shell.row {
                height = 46, padding = { 14, 20, 0, 20 },
                caps("Applications"),
                shell.spacer(),
                caps("Esc", { color = a(t.text_dim, 0.5) }),
            },
            shell.row { height = 52, padding = { 0, 20 }, query },
            shell.box { height = 10 },
            shell.row { height = 1, padding = { 0, 20 },
                shell.spacer { height = 1, background = shell.gradient("horizontal",
                    a(L, 0.8), a(t.text, 0.1), a(t.text, 0.04)) } },
            shell.box { height = 10 },
            shell.column { align = "stretch", results },
            shell.spacer(),
            shell.row {
                height = 44, padding = { 0, 20 }, gap = 18,
                caps("↑ ↓  move", { color = a(t.text_dim, 0.55) }),
                caps("↵  open", { color = a(t.text_dim, 0.55) }),
                shell.spacer(),
                mark(L, 14),
            },
        })
    end,
    on_key = function(key, text)
        local apps = matches()
        if key == "Escape" then
            shell.close("launcher")
        elseif key == "Return" or key == "KP_Enter" then
            if apps[launcher.selected] then launch(apps[launcher.selected]) end
        elseif key == "Up" then
            launcher.selected = math.max(1, launcher.selected - 1)
        elseif key == "Down" then
            launcher.selected = math.min(math.max(#apps, 1), launcher.selected + 1)
        elseif key == "BackSpace" then
            local cut = utf8.offset(launcher.search, -1)
            if cut then launcher.search = launcher.search:sub(1, cut - 1) end
            launcher.selected = 1
        elseif text ~= "" and #launcher.search + #text < 128 then
            launcher.search = launcher.search .. text
            launcher.selected = 1
        end
        shell.redraw()
    end,
}

-- ---- the day sheet (quick settings) ------------------------------------

local quick_output
local QUICK = 280

local function toggle_quick(output)
    shell.close("menu")
    if shell.is_open("quick") then
        shell.close("quick")
    else
        quick_output = output
        shell.open("quick", { output = output })
    end
end

-- The day as a wave: midnight in the troughs at both ends, noon on the
-- crest, the horizon through the middle. What has passed is drawn in the
-- light; the sun (a ring, once it is under the horizon) rides the curve.
local function day_wave(L, width, height)
    local h = hour()
    local horizon, swing = height * 0.5, height * 0.5 - 9
    local inset = 6 -- room for the sun at midnight, at either end
    local function at(time)
        return inset + (width - 2 * inset) * time / 24,
            horizon + swing * math.cos(time / 24 * 2 * math.pi)
    end
    local function curve(from, to)
        local parts, steps = {}, math.max(2, math.ceil((to - from) * 3))
        for i = 0, steps do
            local x, y = at(from + (to - from) * i / steps)
            parts[#parts + 1] = string.format("%s %.2f %.2f", i == 0 and "M" or "L", x, y)
        end
        return table.concat(parts, " ")
    end
    local x, y = at(h)
    local up = y < horizon
    local x6, x18 = at(6), at(18)
    return shell.canvas {
        width = width, height = height,
        -- Daylight, between where the curve leaves the horizon and returns.
        { "path", curve(6, 18) .. " Z", fill = shell.gradient("vertical", a(L, 0.2), a(L, 0)) },
        { "line", inset, horizon, width - inset, horizon, stroke = a(t.text, 0.14) },
        { "line", x6, horizon - 3, x6, horizon + 3, stroke = a(t.text, 0.3) },
        { "line", x18, horizon - 3, x18, horizon + 3, stroke = a(t.text, 0.3) },
        { "path", curve(0, 24), stroke = a(t.text, 0.16), width = 1.2, dash = { 1.5, 3.5 }, cap = "round" },
        { "path", curve(0, h), stroke = shell.gradient("horizontal", a(L, 0.1), L), width = 1.6, cap = "round" },
        { "circle", x, y, 15, fill = shell.gradient("radial", a(L, up and 0.55 or 0.3), a(L, 0.1), a(L, 0)) },
        up and { "circle", x, y, 3.2, fill = mix(L, WHITE, 0.75) }
            or { "circle", x, y, 3.4, fill = t.surface, stroke = L, width = 1.5 },
    }
end

shell.popup {
    name = "quick",
    anchor = { "top", "right" },
    margin = { top = BAR - 22 },
    input = "widgets",
    view = function(ctx)
        local L = light()
        local row = function(id, label, opts)
            opts = opts or {}
            opts.light = L
            return menu_row(ctx, id, 36, label, opts)
        end
        local rows = {
            row("q:launcher", "Launcher", { on_click = function()
                shell.close("quick")
                toggle_launcher()
            end }),
            row("q:next", "Next window", { on_click = function()
                shell.cycle()
                shell.close("quick")
            end }),
        }
        local active = shell.active_workspace()
        for _, name in ipairs(shell.workspaces()) do
            rows[#rows + 1] = row("q:ws:" .. name, "Workspace  " .. name, {
                pip = name == active, strong = name == active,
                on_click = function()
                    shell.workspace(name)
                    shell.close("quick")
                end,
            })
        end
        rows[#rows + 1] = shell.box { height = 5 }
        rows[#rows + 1] = divider()
        rows[#rows + 1] = shell.box { height = 5 }
        rows[#rows + 1] = row("q:quit", "Quit Shady", { danger = true,
            on_click = function() shell.quit() end })
        rows[#rows + 1] = shell.box { height = 8 }
        return panel(18, { 28, 10, SHADE + 12, SHADE }, {
            id = "quick-card", width = QUICK, light = L,
            shell.column {
                align = "start", padding = { 18, 18, 0, 18 }, gap = 2,
                caps(shell.date("%A · %d %B")),
                shell.text(shell.date("%H:%M"), { font = serif(46), letter_spacing = 0 }),
            },
            shell.row { padding = { 2, 18, 0, 18 }, day_wave(L, QUICK - 36, 76) },
            shell.row {
                padding = { 3, 17, 10, 17 }, justify = "space-between",
                caps("00", { color = a(t.text_dim, 0.5) }), caps("06", { color = a(t.text_dim, 0.5) }),
                caps("12", { color = a(t.text_dim, 0.5) }), caps("18", { color = a(t.text_dim, 0.5) }),
                caps("24", { color = a(t.text_dim, 0.5) }),
            },
            divider(),
            shell.box { height = 5 },
            rows,
        })
    end,
}

-- ---- task context menu -------------------------------------------------

local function find_window(id)
    for _, w in ipairs(shell.windows()) do
        if w.id == id then return w end
    end
end

local menu_window

-- Close the menu once its window is gone.
shell.on("change", function()
    if shell.is_open("menu") and not find_window(menu_window) then shell.close("menu") end
end)

shell.popup {
    name = "menu",
    anchor = { "top", "left" },
    margin = { top = BAR - 22 },
    input = "widgets",
    view = function(ctx, args)
        local L = light()
        local w = find_window(args.window) or { id = args.window, workspace = "" }
        local function act(fn)
            return function()
                fn(w.id)
                shell.close("menu")
            end
        end
        local row = function(id, label, opts)
            opts.light = L
            return menu_row(ctx, id, 34, label, opts)
        end
        local rows = {
            shell.box { height = 7 },
            row("m:focus", "Focus", { on_click = act(shell.focus) }),
            row("m:max", w.maximized and "Restore" or "Maximize", { on_click = act(shell.maximize) }),
            row("m:full", w.fullscreen and "Exit fullscreen" or "Fullscreen",
                { on_click = act(shell.fullscreen) }),
        }
        for _, name in ipairs(shell.workspaces()) do
            rows[#rows + 1] = row("m:ws:" .. name, "Move to " .. name, {
                pip = w.workspace == name,
                on_click = act(function(id) shell.move(id, name) end),
            })
        end
        rows[#rows + 1] = row("m:close", "Close", { danger = true, on_click = act(shell.close_window) })
        rows[#rows + 1] = shell.box { height = 7 }
        return panel(14, { 28, SHADE, SHADE + 12, SHADE }, { id = "menu-card", width = 230, light = L, rows })
    end,
}

local function open_menu(window, info)
    shell.close("quick")
    menu_window = window.id
    shell.open("menu", { output = info.output,
        margin = { left = math.max(0, math.floor(info.x) - SHADE) }, window = window.id })
end

-- ---- notifications -----------------------------------------------------

-- Serve org.freedesktop.Notifications unless another daemon already does.
shell.notification_server()

local function active_notifications(limit)
    local list = {}
    for _, n in ipairs(shell.notifications()) do
        if n.active and #list < limit then list[#list + 1] = n end
    end
    return list
end

-- The toast popup is open exactly while something is on screen. The
-- history outlives config reloads, so sync once now as well.
local function sync_toasts()
    local any = #active_notifications(1) > 0
    if any and not shell.is_open("toasts") then
        shell.open("toasts")
    elseif not any and shell.is_open("toasts") then
        shell.close("toasts")
    end
end
shell.on("notifications", sync_toasts)

-- A click runs the "default" action if there is one, else dismisses.
local function activate(n)
    for _, action in ipairs(n.actions) do
        if action.key == "default" then
            shell.invoke_notification(n.id, "default")
            return
        end
    end
    shell.dismiss_notification(n.id)
end

-- A slip of paper with the light down its left edge (red when critical).
local function toast(ctx, n, L)
    local id = "toast:" .. n.id
    local lit = n.urgency == "critical" and t.danger or L
    local buttons = {}
    for _, action in ipairs(n.actions) do
        if action.key ~= "default" and action.label ~= "" then
            local bid = id .. ":" .. action.key
            local hovered = ctx.hovered == bid
            buttons[#buttons + 1] = shell.row {
                id = bid, height = 24, radius = 12, padding = { 0, 12 }, animate = "snappy",
                background = a(lit, hovered and 0.24 or 0.1),
                on_click = function() shell.invoke_notification(n.id, action.key) end,
                shell.text(action.label, { font = sans("Bold", 8.5),
                    color = hovered and t.text or mix(lit, t.text, 0.5) }),
            }
        end
    end
    local alpha = options.panel_opacity or 0.97
    return shell.stack {
        key = id, width = 340, radius = 14,
        animate = "snappy", enter = { opacity = 0, translate = { 28, 0 } },
        background = shell.gradient("vertical", a(mix(t.surface, WHITE, 0.055), alpha), a(t.surface, alpha)),
        border = a(t.text, 0.075),
        shadow = { 0, 12, a(BLACK, 0.45), 22 },
        shell.box { left = 0, top = 0, bottom = 0, width = 90, radius = 14, background = wash(lit, 0.7) },
        edge(lit, 1, 10),
        shell.column {
            left = 0, right = 0, align = "stretch", padding = { 0, 0, 13, 0 },
            shell.row {
                id = id, padding = { 12, 10, 0, 18 }, gap = 10, align = "start",
                on_click = function() activate(n) end,
                shell.column {
                    grow = 1, shrink = 1, align = "start", gap = 4,
                    caps(n.app ~= "" and n.app or "Notification", { color = mix(lit, t.text_dim, 0.45) }),
                    shell.text(n.summary, { font = sans("Bold", 10), max_width = 270 }),
                    n.body ~= "" and shell.text(n.body, { font = sans("Medium", 9), color = a(t.text, 0.72),
                        max_width = 270, wrap = true, max_lines = 3 }) or false,
                },
                shell.row {
                    id = id .. ":close", width = 20, height = 20, radius = 10, justify = "center",
                    animate = "snappy",
                    background = a(t.text, ctx.hovered == id .. ":close" and 0.12 or 0),
                    on_click = function() shell.dismiss_notification(n.id) end,
                    shell.text("×", { font = sans("Medium", 11), color = t.text_dim }),
                },
            },
            #buttons > 0 and shell.row { padding = { 10, 14, 0, 18 }, gap = 6, buttons } or false,
        },
    }
end

shell.popup {
    name = "toasts",
    anchor = { "top", "right" },
    margin = { top = BAR - 18 },
    input = "widgets",
    view = function(ctx)
        local L = light()
        local cards = {}
        for _, n in ipairs(active_notifications(4)) do cards[#cards + 1] = toast(ctx, n, L) end
        return shell.column {
            gap = 10, align = "stretch", padding = { 26, 10, SHADE + 8, SHADE },
            exit = { opacity = 0, translate = { 28, 0 } }, animate = "snappy",
            cards,
        }
    end,
}
sync_toasts()

-- ---- bar ---------------------------------------------------------------

-- The day line: a hairline along the bar's lower edge, an hour to each
-- tick, lit up to where the sun stands now.
local function day_line(L, width)
    local h = hour()
    local y = BAR - 0.5
    local x = width * h / 24
    local shapes = {
        { "line", 0, y, width, y, stroke = a(t.text, 0.1) },
    }
    for tick = 1, 23 do
        local tx = math.floor(width * tick / 24) + 0.5
        local tall = tick % 6 == 0
        shapes[#shapes + 1] = { "line", tx, BAR - 1, tx, BAR - (tall and 6 or 3.5),
            stroke = tick <= h and a(L, tall and 0.75 or 0.45) or a(t.text, tall and 0.26 or 0.13) }
    end
    shapes[#shapes + 1] = { "line", 0, y - 0.25, x, y - 0.25, width = 1.5,
        stroke = shell.gradient("horizontal", a(L, 0.08), a(L, 0.5), L) }
    -- The sun, half above the horizon, and the light it throws along it.
    shapes[#shapes + 1] = { "circle", x, BAR, 44,
        fill = shell.gradient("radial", a(L, 0.6), a(L, 0.16), a(L, 0.04), a(L, 0)) }
    shapes[#shapes + 1] = { "circle", x, BAR, 9, fill = shell.gradient("radial", a(L, 0.9), a(L, 0)) }
    shapes[#shapes + 1] = { "circle", x, BAR, 3.6, fill = mix(L, WHITE, 0.82) }
    return shell.canvas { left = 0, top = 0, right = 0, bottom = 0, shapes }
end

-- Something on the bar that can be lit: a tab standing on the day line.
local function tab(id, lit, hovered, L, props)
    local outer = {
        id = id, height = BAR, min_width = props.min_width, max_width = props.max_width,
        animate = props.animate, enter = props.enter,
        shader = props.shader, uniforms = props.uniforms,
        on_click = props.on_click,
    }
    for key in pairs(outer) do props[key] = nil end
    props.left, props.right, props.top, props.bottom = 0, 0, 0, 0
    outer[1] = lit and rise(L, 1) or rise(t.text, hovered and 0.45 or 0)
    outer[2] = shell.box { left = 6, right = 6, bottom = 0, height = 2, animate = "smooth",
        background = shell.gradient("horizontal", a(L, 0), a(L, lit and 1 or 0), a(L, 0)) }
    outer[3] = shell.row(props)
    return shell.stack(outer)
end

local function workspaces(ctx, L)
    local active = shell.active_workspace()
    local names = {}
    for _, name in ipairs(shell.workspaces()) do
        local id = "ws:" .. name
        local on = name == active
        local hovered = ctx.hovered == id
        names[#names + 1] = tab(id, on, hovered, L, {
            padding = { 0, 11 },
            on_click = function(button)
                if button == "left" then shell.workspace(name) end
            end,
            caps(name, { key = id .. ":name", animate = "snappy", font = sans("ExtraBold", 8),
                color = a(t.text, on and 1 or (hovered and 0.8 or 0.42)) }),
        })
    end
    if #names == 0 then return false end
    return shell.row { names }
end

local function tasks(ctx, L)
    local active = shell.active_workspace()
    local tabs = {}
    for _, w in ipairs(shell.windows()) do
        if w.workspace == "" or active == "" or w.workspace == active then
            local id = "task:" .. w.id
            local hovered = ctx.hovered == id
            local label = w.title ~= "" and w.title or (w.app_id ~= "" and w.app_id or "Window")
            tabs[#tabs + 1] = tab(id, w.focused, hovered, L, {
                min_width = 96, max_width = 210, padding = { 0, 14 }, gap = 8,
                animate = "smooth", enter = { opacity = 0, translate = { 0, 8 } },
                shader = w.focused and options.focus_shader or nil,
                uniforms = options.focus_uniforms,
                on_click = function(button, info)
                    if button == "left" then
                        shell.close("menu")
                        shell.focus(w.id)
                    elseif button == "right" then
                        open_menu(w, info)
                    end
                end,
                shell.pip { radius = 2.6, lit = w.focused, color = w.focused and L or nil },
                shell.text(label, { animate = "snappy", font = sans(w.focused and "Bold" or "Medium", 9.5),
                    color = a(t.text, w.focused and 1 or (hovered and 0.85 or 0.5)) }),
            })
        end
    end
    return shell.row { grow = 1, clip = true, tabs }
end

local function clock(ctx, L)
    local open = shell.is_open("quick") and quick_output == ctx.output
    return tab("clock", open, ctx.hovered == "clock", L, {
        padding = { 0, 14 }, gap = 11,
        on_click = function(button, info)
            if button == "left" then toggle_quick(info.output) end
        end,
        caps(shell.date("%a %d %b"), { color = a(t.text_dim, 0.9) }),
        shell.text(shell.date("%H:%M"), { font = serif(14.5), letter_spacing = 0.2,
            color = t.text, height = BAR - 4 }),
    })
end

shell.bar {
    name = "shady-shell",
    edge = "top",
    size = BAR,
    shader = options.bar_shader,
    uniforms = options.bar_uniforms,
    view = function(ctx)
        local L = light()
        local opacity = options.bar_opacity or 0.94
        return shell.stack {
            -- Slides down from above the screen when the bar appears.
            enter = { translate = { 0, -BAR }, opacity = 0 }, animate = "gentle",
            background = shell.gradient("vertical",
                a(mix(t.surface, BLACK, 0.3), opacity), a(mix(t.surface, WHITE, 0.02), opacity)),
            day_line(L, ctx.width),
            shell.row {
                left = 0, right = 0, top = 0, bottom = 0, padding = { 0, 6, 0, 0 },
                shell.row {
                    id = "mark", width = 46, height = BAR, justify = "center",
                    on_click = function(button)
                        if button == "left" then toggle_launcher() end
                    end,
                    mark(L, 19),
                },
                workspaces(ctx, L),
                shell.box { width = 10 },
                tasks(ctx, L),
                options.bar_extra and options.bar_extra(ctx) or false,
                options.bar_extra and shell.box { width = 8 } or false,
                clock(ctx, L),
            },
        }
    end,
}

-- ---- shortcut overlay (Super+Shift+/) ----------------------------------

require("shortcut_overlay").install {
    font = sans("Medium", 9.5), bold = sans("Bold", 9.5), title_font = serif(20),
    -- The theme, with the light of the hour for an accent.
    palette = setmetatable({}, { __index = function(_, key)
        if key == "accent" then return light() end
        return t[key]
    end }),
    frame = function(body)
        return panel(20, SHADE, { shell.column { padding = { 22, 28, 26, 28 }, align = "stretch", body } })
    end,
}
