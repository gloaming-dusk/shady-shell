-- Shady Settings: the desktop's appearance, windows, input, dock,
-- clipboard and notifications, in one window drawn the way the shell is
-- (`shady-shell --app apps/settings.lua`, or `shady-settings`).
--
-- Where things go, so the running desktop follows at once:
--   accent, corners, gaps, keyboard, touchpad  ~/.config/shady/settings.lua,
--       which Tide's config (and every rice built on it) reads at start;
--       the change is also applied live with shady.set, and announced as
--       the compositor value "shady.settings" for shells that redraw
--   wallpaper      $XDG_STATE_HOME/shady/wallpaper (shady-wallpaper), which
--                  the wallpaper module watches
--   dock pins      the statefile "dock", which the dock module watches
--   clipboard      the statefile "clipboard" (limit) and its history file
--   quiet hours    the statefile "notifications", which toasts watches
--
-- The look follows shell.theme (SHADY_SHELL_* colours); the type is the
-- data directory's Manrope.

shell.fonts(shell.data_dir .. "/fonts")
package.path = shell.data_dir .. "/?.lua;" .. package.path

local a, mix = shell.alpha, shell.mix
local T = shell.theme or {}
local P = {
    accent = T.accent or "#7AA2F7",
    base = mix(T.surface or "#1E1E2E", "#000000", 0.25),
    surface = T.surface or "#1E1E2E",
    text = T.text or "#E6E6F0",
    dim = T.text_dim or "#9AA0B4",
    danger = T.danger or "#F7768E",
}
local function font(weight, size) return "Manrope " .. weight .. " " .. size end
local function text(s, props)
    props = props or {}
    props.font = props.font or font("Medium", 10)
    props.color = props.color or P.text
    return shell.text(s, props)
end

local home = os.getenv("HOME") or ""
local config_base = os.getenv("XDG_CONFIG_HOME")
if not config_base or config_base == "" then config_base = home .. "/.config" end
local DIR = config_base .. "/shady"
local PATH = DIR .. "/settings.lua"

-- ---- the settings file ---------------------------------------------------------

local saved = {}
do
    local ok, value = pcall(dofile, PATH)
    if ok and type(value) == "table" then saved = value end
end

local DEFAULTS = {
    accent = "", layout_gap = 10, window_corner_radius = 12,
    xkb_layout = "", xkb_options = "", repeat_delay = 300, repeat_rate = 30,
    touchpad_tap = true, touchpad_natural_scroll = true, gesture_fingers = 3,
}
local function get(key)
    if saved[key] ~= nil then return saved[key] end
    return DEFAULTS[key]
end

local function literal(value)
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

local function save()
    local keys = {}
    for key in pairs(saved) do keys[#keys + 1] = key end
    table.sort(keys)
    local lines = { "-- Written by Shady Settings.", "return {" }
    for _, key in ipairs(keys) do
        lines[#lines + 1] = string.format("    %s = %s,", key, literal(saved[key]))
    end
    lines[#lines + 1] = "}\n"
    os.execute(string.format("mkdir -p %q", DIR))
    local temporary = PATH .. ".new"
    local file = io.open(temporary, "w")
    if not file then
        shell.log("settings: cannot write " .. PATH)
        return false
    end
    file:write(table.concat(lines, "\n"))
    file:close()
    return os.rename(temporary, PATH) ~= nil
end

local serial = 0
local function announce()
    serial = serial + 1
    shell.compositor_lua(string.format('shady.publish("shady.settings", "%d.%d")', os.time(), serial))
end

local function apply(key, value)
    shell.compositor_lua(string.format("pcall(shady.set, %q, %s)", key, literal(value)))
end

local function set(key, value)
    saved[key] = value
    save()
    apply(key, value)
    announce()
    shell.redraw()
end

-- ---- controls --------------------------------------------------------------------

local editing -- { key =, text =, validate =, on_commit = }
local problem = {}

local function commit()
    if not editing then return end
    local e = editing
    editing = nil
    local complaint = e.validate and e.validate(e.text)
    problem[e.key] = complaint
    if not complaint then
        if e.on_commit then e.on_commit(e.text)
        elseif e.text ~= get(e.key) then set(e.key, e.text) end
    end
    shell.redraw()
end

local function field(key, placeholder, opts)
    opts = opts or {}
    local active = editing and editing.key == key
    local value = active and editing.text or (opts.value or get(key) or "")
    return shell.row {
        id = "field:" .. key, width = opts.width or 230, height = 34, radius = 10, padding = { 0, 12 }, gap = 1,
        background = a(P.base, 0.8),
        border = problem[key] and a(P.danger, 0.7) or a(active and P.accent or P.text, active and 0.6 or 0.12),
        on_click = function()
            if active then return end
            commit()
            editing = { key = key, text = value, validate = opts.validate, on_commit = opts.on_commit }
            shell.redraw()
        end,
        value ~= "" and text(value, { font = font("Medium", 9.5), max_width = (opts.width or 230) - 26, shrink = 1 })
            or (not active and text(placeholder, { font = font("Medium", 9.5), color = a(P.dim, 0.75) }) or false),
        active and shell.box { width = 2, height = 18, radius = 1, background = P.accent, caret = true } or false,
    }
end

local function toggle(id, on, fn)
    return shell.stack {
        id = "toggle:" .. id, width = 44, height = 24, radius = 12, animate = "snappy",
        background = on and P.accent or a(P.text, 0.14),
        on_click = fn,
        shell.box { key = "knob", left = on and 22 or 2, top = 2, width = 20, height = 20, radius = 10,
            animate = "snappy", background = on and P.base or P.text },
    }
end

local function choice(ctx, id, current, options, fn)
    local parts = {}
    for i, option in ipairs(options) do
        local pid = "choice:" .. id .. ":" .. i
        local on = current == option[2]
        parts[#parts + 1] = shell.row {
            id = pid, height = 28, radius = 8, padding = { 0, 11 }, justify = "center", animate = "snappy",
            background = on and a(P.accent, 0.26) or a(P.text, ctx.hovered == pid and 0.08 or 0),
            on_click = function() fn(option[2]) end,
            text(option[1], { font = font(on and "Bold" or "Medium", 9), color = on and P.text or a(P.text, 0.72) }),
        }
    end
    return shell.row { padding = 2, radius = 10, gap = 1, background = a(P.base, 0.8), parts }
end

local function button(id, label, fn, opts)
    opts = opts or {}
    return shell.row { id = id, height = 30, radius = 9, padding = { 0, 12 }, gap = 6,
        background = opts.strong and a(P.accent, 0.3) or a(P.text, 0.08),
        hover = { background = opts.danger and a(P.danger, 0.2) or a(P.text, 0.14) },
        on_click = fn,
        opts.icon and shell.icon(opts.icon, { size = 12, stroke = 2.2, color = opts.danger and P.danger or P.text }) or false,
        text(label, { font = font("SemiBold", 9), color = opts.danger and P.danger or P.text }) }
end

local function setting(label, control, hint, complaint)
    return shell.row {
        align = "center", gap = 16, padding = { 11, 16 },
        shell.column { grow = 1, shrink = 1, align = "start", gap = 2,
            text(label, { font = font("SemiBold", 10) }),
            (complaint or hint) and text(complaint or hint, { font = font("Medium", 8.5),
                color = complaint and P.danger or P.dim, wrap = true, max_lines = 2, max_width = 300 }) or false,
        },
        control,
    }
end

local function group(title, rows, extra)
    return shell.column { align = "stretch", gap = 8,
        shell.row { text(title, { font = font("Bold", 8.5), color = P.dim }), shell.spacer(), extra or false },
        shell.column { align = "stretch", radius = 14, background = a(P.surface, 0.9),
            border = a(P.text, 0.07), rows },
    }
end

-- ---- appearance ----------------------------------------------------------------

local ACCENTS = {
    { "#B4A0FF", "#7CB7FF" }, { "#7CB7FF", "#8BE0E0" }, { "#8BD5A8", "#7CB7FF" },
    { "#F2C27B", "#FF9E64" }, { "#FF7A93", "#B4A0FF" }, { "#8DCBF5", "#F49BBF" },
}

local function accents(ctx)
    local parts = {}
    for i, pair in ipairs(ACCENTS) do
        local on = get("accent") == pair[1]
        local id = "accent:" .. i
        parts[#parts + 1] = shell.row {
            id = id, width = 30, height = 30, radius = 15, animate = "snappy",
            background = shell.gradient("diagonal", pair[1], pair[2]),
            border = on and P.text or a(P.text, ctx.hovered == id and 0.4 or 0), border_width = 2,
            on_click = function()
                saved.accent, saved.accent_2 = pair[1], pair[2]
                save()
                apply("window_border_focus_color", pair[1])
                announce()
                shell.redraw()
            end,
        }
    end
    return shell.row { gap = 8, parts }
end

-- Wallpapers: pictures in the usual folders, chosen with shady-wallpaper.
local WALL_STATE = (function()
    local base = os.getenv("XDG_STATE_HOME")
    if not base or base == "" then base = home .. "/.local/state" end
    return base .. "/shady/wallpaper"
end)()

local function wallpaper_tool()
    local local_tool = shell.data_dir .. "/bin/shady-wallpaper"
    if shell.stat and shell.stat(local_tool) then return local_tool end
    return "shady-wallpaper"
end

local function current_wallpaper()
    local f = io.open(WALL_STATE, "r")
    if not f then return nil end
    local chosen
    for line in f:lines() do
        local who, source = line:match("^(%S+) (.+)$")
        if who == "*" then chosen = source end
    end
    f:close()
    return chosen
end

local walls_cache, walls_at
local function wallpapers()
    if walls_cache and os.time() - walls_at < 10 then return walls_cache end
    local out, seen = {}, {}
    local folders = { home .. "/Pictures/Wallpapers", home .. "/Pictures/wallpapers", DIR .. "/wallpapers",
        home .. "/Pictures" }
    for _, folder in ipairs(folders) do
        local entries = shell.files and shell.files(folder)
        for _, e in ipairs(entries or {}) do
            if not e.dir and e.name:lower():match("%.(%a+)$") then
                local ext = e.name:lower():match("%.(%a+)$")
                if (ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp") and not seen[e.path] then
                    seen[e.path] = true
                    out[#out + 1] = e.path
                end
            end
            if #out >= 24 then break end
        end
    end
    walls_cache, walls_at = out, os.time()
    return out
end

local function choose_wallpaper(path)
    if path then
        shell.spawn(string.format("%q set %q", wallpaper_tool(), path))
    else
        shell.spawn(string.format("%q clear", wallpaper_tool()))
    end
    shell.after(300, shell.redraw)
end

local function valid_wallpaper(path)
    if path == "" then return nil end
    local full = path:gsub("^~/", home .. "/")
    local st = shell.stat and shell.stat(full)
    if not st then return "There is no such file or folder" end
    if st.dir then return nil end
    if not shell.image_size(full) then return "Not a picture this shell can read" end
    return nil
end

local function wallpaper_grid(ctx)
    local current = current_wallpaper()
    local tiles = {
        shell.column { id = "wall:default", width = 132, height = 84, radius = 10, justify = "center", align = "center",
            gap = 4, background = a(P.text, 0.06),
            border = not current and P.accent or a(P.text, ctx.hovered == "wall:default" and 0.4 or 0.1), border_width = 2,
            on_click = function() choose_wallpaper(nil) end,
            shell.icon("sun", { size = 18, color = P.dim }),
            text("The rice's own", { font = font("SemiBold", 8.5), color = P.dim }) },
    }
    for i, path in ipairs(wallpapers()) do
        local id = "wall:" .. i
        local on = current == path
        tiles[#tiles + 1] = shell.stack { id = id, width = 132, height = 84, radius = 10,
            border = on and P.accent or a(P.text, ctx.hovered == id and 0.4 or 0.1), border_width = 2,
            on_click = function() choose_wallpaper(path) end,
            shell.image { left = 2, top = 2, width = 128, height = 80, path = path, fit = "cover" } }
    end
    -- As many to a row as the window has room for (sidebar 190, padding),
    -- three rows at most: the page does not scroll.
    local cols = math.max(1, math.floor(((ctx.width or 900) - 190 - 44 - 32 + 10) / 142))
    while #tiles > cols * 3 do table.remove(tiles) end
    local rows = {}
    for i = 1, #tiles, cols do
        local row = {}
        for j = i, math.min(#tiles, i + cols - 1) do row[#row + 1] = tiles[j] end
        rows[#rows + 1] = shell.row { gap = 10, row }
    end
    return shell.column { gap = 10, padding = { 12, 16 }, align = "start", rows }
end

-- ---- dock -----------------------------------------------------------------------

local dock_state = require("statefile")("dock")
local function pins()
    local raw = dock_state.get("pins") or ""
    local out = {}
    for name in (raw .. "\t"):gmatch("(.-)\t") do if name ~= "" then out[#out + 1] = name end end
    return out
end
local function write_pins(list)
    dock_state.set("pins", table.concat(list, "\t"))
    shell.redraw()
end
local dock_query = ""

local function dock_page(ctx)
    local list = pins()
    local rows = {}
    for i, name in ipairs(list) do
        rows[#rows + 1] = shell.row { padding = { 8, 16 }, gap = 10, align = "center",
            text(tostring(i), { font = font("Bold", 9), color = P.dim, width = 18 }),
            text(name, { font = font("SemiBold", 10), grow = 1, shrink = 1 }),
            button("pin:up:" .. i, "Up", function()
                if i > 1 then list[i], list[i - 1] = list[i - 1], list[i]; write_pins(list) end end, { icon = "previous" }),
            button("pin:down:" .. i, "Down", function()
                if i < #list then list[i], list[i + 1] = list[i + 1], list[i]; write_pins(list) end end, { icon = "next" }),
            button("pin:del:" .. i, "Remove", function() table.remove(list, i); write_pins(list) end,
                { icon = "close", danger = true }),
        }
    end
    if #list == 0 then
        rows[1] = shell.row { padding = { 14, 16 },
            text("Nothing is pinned. Pin applications here, or from the dock (right click).",
                { font = font("Medium", 9.5), color = P.dim }) }
    end
    local found = {}
    do
        local pinned = {}
        for _, n in ipairs(list) do pinned[n] = true end
        local seen = {}
        for _, app in ipairs(shell.apps(dock_query, dock_query == "" and 40 or 12)) do
            if not pinned[app.name] and not seen[app.name] then
                seen[app.name] = true
                found[#found + 1] = shell.row { padding = { 6, 16 }, gap = 10, align = "center",
                    app.icon and shell.image { path = app.icon, width = 22, height = 22, fit = "contain" }
                        or shell.box { width = 22 },
                    text(app.name, { font = font("Medium", 10), grow = 1, shrink = 1 }),
                    button("pin:add:" .. app.name, "Pin", function()
                        list[#list + 1] = app.name
                        write_pins(list)
                    end, { icon = "plus", strong = true }) }
            end
            if #found >= 6 then break end
        end
    end
    return {
        group("Pinned, in order", rows, #list > 0 and button("pin:clear", "Unpin all", function() write_pins({}) end,
            { danger = true }) or false),
        group("Add", {
            setting("Find an application", field("dock_query", "Name", {
                value = dock_query, on_commit = function(v) dock_query = v end })),
            #found > 0 and shell.column { align = "stretch", padding = { 0, 0, 8, 0 }, found } or false,
        }),
    }
end

-- ---- clipboard ------------------------------------------------------------------

local clip_state = require("statefile")("clipboard")
local function clip_history_path()
    local base = os.getenv("XDG_STATE_HOME")
    if not base or base == "" then base = home .. "/.local/state" end
    return base .. "/shady/clipboard.lua"
end
local function clip_count()
    local chunk = loadfile(clip_history_path(), "t", {})
    local ok, list = false, nil
    if chunk then ok, list = pcall(chunk) end
    if not ok or type(list) ~= "table" then return 0, 0 end
    local pinned = 0
    for _, e in ipairs(list) do if type(e) == "table" and e.pinned then pinned = pinned + 1 end end
    return #list, pinned
end
local function clip_clear()
    local chunk = loadfile(clip_history_path(), "t", {})
    local ok, list = false, nil
    if chunk then ok, list = pcall(chunk) end
    local lines = { "-- The clipboard's history, written by shady-shell.", "return {" }
    if ok and type(list) == "table" then
        for _, e in ipairs(list) do
            if type(e) == "table" and e.pinned and type(e.value) == "string" then
                lines[#lines + 1] = string.format("  { kind = %q, value = %q, time = %d, pinned = true },",
                    e.kind or "text", e.value, tonumber(e.time) or os.time())
            elseif type(e) == "table" and e.kind == "image" and type(e.value) == "string"
                and e.value:find("/shady/clipboard/", 1, true) then
                os.remove(e.value)
            end
        end
    end
    lines[#lines + 1] = "}\n"
    local f = io.open(clip_history_path(), "w")
    if f then f:write(table.concat(lines, "\n")); f:close() end
    shell.redraw()
end

local function clipboard_page(ctx)
    local count, pinned = clip_count()
    local limit = tonumber(clip_state.get("limit")) or 50
    return {
        group("History", {
            setting("Keep", choice(ctx, "clip_limit", limit,
                { { "25", 25 }, { "50", 50 }, { "100", 100 }, { "200", 200 } },
                function(v) clip_state.set("limit", v); shell.redraw() end),
                "Copies kept besides the pinned ones"),
            setting("Saved now", button("clip:clear", "Clear all but pinned", clip_clear, { danger = true }),
                string.format("%d copies, %d pinned", count, pinned)),
        }),
        group("About", {
            shell.row { padding = { 12, 16 },
                text(shell.clipboard_available and "Copies are read and served by the shell itself, through "
                    .. "wlr-data-control; no wl-copy is needed. Copies a password manager marks as secret are "
                    .. "never kept." or "This shell has no clipboard support.",
                    { font = font("Medium", 9), color = P.dim, wrap = true, max_width = 560 }) },
        }),
    }
end

-- ---- notifications -----------------------------------------------------------

local notify_state = require("statefile")("notifications")
local function notifications_page(ctx)
    local dnd = notify_state.get("dnd") == "1"
    return {
        group("Notifications", {
            setting("Quiet hours", toggle("dnd", dnd, function()
                notify_state.set("dnd", dnd and "0" or "1"); shell.redraw() end),
                "Only urgent notifications are shown"),
        }),
    }
end

-- ---- pages ------------------------------------------------------------------------

local PAGES = {
    { title = "Appearance", icon = "sun", view = function(ctx) return {
        group("Colour", { setting("Accent", accents(ctx), "The focused window's border, and rices that follow it") }),
        group("Wallpaper", {
            wallpaper_grid(ctx),
            setting("Or a path", field("wallpaper_path", "~/Pictures/…", {
                validate = valid_wallpaper,
                on_commit = function(v) if v ~= "" then choose_wallpaper((v:gsub("^~/", home .. "/"))) end end }),
                "A picture (PNG, JPEG, WebP) or a folder of them, a slideshow", problem.wallpaper_path),
        }),
    } end },
    { title = "Windows", icon = "grid", view = function(ctx) return {
        group("Windows", {
            setting("Corners", choice(ctx, "corners", get("window_corner_radius"),
                { { "Square", 0 }, { "Small", 6 }, { "Medium", 12 }, { "Large", 18 } },
                function(v) set("window_corner_radius", v) end)),
            setting("Gaps", choice(ctx, "gaps", get("layout_gap"),
                { { "None", 0 }, { "Small", 5 }, { "Medium", 10 }, { "Large", 20 } },
                function(v) set("layout_gap", v) end)),
        }),
    } end },
    { title = "Input", icon = "sliders", view = function(ctx) return {
        group("Keyboard", {
            setting("Layout", field("xkb_layout", "us"), "us, kr, de,fr…"),
            setting("Options", field("xkb_options", "None"), "caps:escape, korean:ralt_hangul…"),
            setting("Repeat after", choice(ctx, "delay", get("repeat_delay"),
                { { "Short", 200 }, { "Medium", 300 }, { "Long", 600 } }, function(v) set("repeat_delay", v) end)),
            setting("Repeat speed", choice(ctx, "rate", get("repeat_rate"),
                { { "Slow", 15 }, { "Medium", 30 }, { "Fast", 50 } }, function(v) set("repeat_rate", v) end)),
        }),
        group("Touchpad", {
            setting("Tap to click", toggle("tap", get("touchpad_tap"),
                function() set("touchpad_tap", not get("touchpad_tap")) end)),
            setting("Natural scrolling", toggle("natural", get("touchpad_natural_scroll"),
                function() set("touchpad_natural_scroll", not get("touchpad_natural_scroll")) end)),
            setting("Swipe fingers", choice(ctx, "fingers", get("gesture_fingers"),
                { { "3 fingers", 3 }, { "4 fingers", 4 }, { "Off", 0 } }, function(v) set("gesture_fingers", v) end)),
        }),
    } end },
    { title = "Dock", icon = "grid", view = dock_page },
    { title = "Clipboard", icon = "check", view = clipboard_page },
    { title = "Notifications", icon = "bell", view = notifications_page },
}

local page = 1
local requested = os.getenv("SHADY_SETTINGS_PAGE")
for i, entry in ipairs(PAGES) do
    if requested and entry.title:lower() == requested:lower() then page = i end
end

local function sidebar(ctx)
    local items = {
        shell.box { height = 6 },
        text("Settings", { font = font("ExtraBold", 14) }),
        text(os.getenv("SHADY_RICE") and ("Rice: " .. os.getenv("SHADY_RICE")) or "Shady",
            { font = font("Medium", 8.5), color = P.dim }),
        shell.box { height = 12 },
    }
    for i, entry in ipairs(PAGES) do
        local id = "page:" .. i
        local on = i == page
        items[#items + 1] = shell.row {
            id = id, height = 36, radius = 10, padding = { 0, 10 }, gap = 10, animate = "snappy",
            background = on and a(P.accent, 0.22) or a(P.text, ctx.hovered == id and 0.07 or 0),
            on_click = function() commit(); page = i; shell.redraw() end,
            shell.icon(entry.icon, { size = 14, color = on and P.accent or P.dim }),
            text(entry.title, { font = font(on and "Bold" or "Medium", 10) }),
        }
    end
    return shell.column { width = 190, align = "stretch", gap = 3, padding = 14,
        background = a(P.surface, 0.75), items }
end

shell.window {
    name = "settings",
    title = "Settings",
    app_id = "shady-settings",
    width = 900,
    height = 660,
    text_input = true,
    view = function(ctx)
        local body = PAGES[page].view(ctx)
        return shell.row {
            width = ctx.width, height = ctx.height, align = "stretch", background = P.base,
            sidebar(ctx),
            shell.column { key = "page:" .. page, grow = 1, shrink = 1, align = "stretch", gap = 18, padding = 22,
                text(PAGES[page].title, { font = font("Bold", 16) }),
                body,
            },
        }
    end,
    on_key = function(key, typed)
        if not editing then
            if key == "Escape" then shell.quit() end
            return
        end
        if key == "Return" or key == "KP_Enter" then
            commit()
        elseif key == "Escape" then
            editing = nil
        elseif key == "BackSpace" then
            local cut = utf8.offset(editing.text, -1)
            if cut then editing.text = editing.text:sub(1, cut - 1) end
        elseif typed ~= "" and #editing.text + #typed <= 200 then
            editing.text = editing.text .. typed
        end
        -- The dock page searches as you type.
        if editing and editing.key == "dock_query" then dock_query = editing.text end
        shell.redraw()
    end,
}

shell.after(0, function() shell.open("settings") end)
