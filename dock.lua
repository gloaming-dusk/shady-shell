-- A dock along the bottom of the screen: the applications you pin, in your
-- order, then whatever else has a window open. Click an application to
-- focus its window (the next one, if it has several) or start it; drag a
-- pinned one sideways to move it; right click for a menu: Pin or Unpin,
-- New window, Close, Move left/right. The pins outlive restarts (statefile
-- "dock") and another process (the Settings app) may change them.
--
--     local dock = require("dock")
--     dock.install {
--         art = function(app, size) ... end,  -- an application's picture
--         launcher = function() ... end,      -- the last tile opens it
--     }
--     dock.pin("Firefox"); dock.unpin("Firefox"); dock.move("Firefox", -1)
--
-- Before anything was pinned, the dock starts from the `seed` (default 5)
-- applications launched most (require("launches")), and those become pins.
--
-- install(options), all optional:
--   name        the popup's name (default "dock")
--   size        a tile's side (default 46)
--   exclusive   room the windows leave for it (default size + 26; 0: none)
--   seed        how many of the most launched to start from
--   everything  function() -> every application (default shell.apps, by name)
--   art         function(app, size) -> widget (default: its icon, or a letter)
--   launcher    function(): adds a last tile that opens the launcher
--   palette     accent, surface, text, text_dim, danger (default shell.theme;
--               a function is called on every repaint)
--   font        for the names and the menu
--   style       functions that draw it differently:
--       shelf(row, ctx)              the shelf around the row of tiles
--       tile(item, state)            a tile: state.size, hot, dragging
--       mark(item)                   under a tile: item.window, item.focused
--       menu(rows)                   the box around the menu's rows

local launches = require("launches")
local state = require("statefile")("dock")

local M = {}
local SEP = "\t"

-- ---- pins ------------------------------------------------------------------

function M.pins()
    local raw = state.get("pins")
    if not raw or raw == "" then return {} end
    local out = {}
    for name in (raw .. SEP):gmatch("(.-)" .. SEP) do
        if name ~= "" then out[#out + 1] = name end
    end
    return out
end

local function write(list)
    state.set("pins", table.concat(list, SEP))
    shell.redraw()
end

function M.pinned(name)
    for _, n in ipairs(M.pins()) do if n == name then return true end end
    return false
end

function M.pin(name, at)
    if not name or name == "" or M.pinned(name) then return end
    local list = M.pins()
    table.insert(list, math.max(1, math.min(#list + 1, at or #list + 1)), name)
    write(list)
end

function M.unpin(name)
    local list = {}
    for _, n in ipairs(M.pins()) do if n ~= name then list[#list + 1] = n end end
    write(list)
end

-- Move a pin by `by` places (negative: to the left).
function M.move(name, by)
    local list = M.pins()
    for i, n in ipairs(list) do
        if n == name then
            local to = math.max(1, math.min(#list, i + by))
            table.remove(list, i)
            table.insert(list, to, name)
            write(list)
            return
        end
    end
end

-- ---- what is on it -----------------------------------------------------------

local function command(exec)
    local first = (exec or ""):match("^%S+") or ""
    return (first:match("([^/]+)$") or first):lower()
end

-- Whether a window belongs to an application: its app_id names the
-- command, or the command is the last part of a reverse-DNS app_id.
function M.owns(app, window)
    local id = (window.app_id or ""):lower()
    if id == "" then return false end
    local cmd = command(app.exec)
    local tail = id:match("([^.]+)$") or id
    return id == cmd or tail == cmd or id == (app.name or ""):lower()
        or (#cmd > 2 and tail:find(cmd, 1, true) ~= nil)
end

local opts = {}

local function everything()
    if opts.everything then return opts.everything() end
    local seen, out = {}, {}
    for _, app in ipairs(shell.apps("", 512)) do
        if not seen[app.name] then seen[app.name] = true; out[#out + 1] = app end
    end
    return out
end

-- The tiles: { app, windows = {...}, focused, pinned }, pins first.
function M.items()
    local apps = everything()
    local by_name = {}
    for _, app in ipairs(apps) do by_name[app.name] = by_name[app.name] or app end
    if state.get("pins") == nil then
        -- Nothing was ever pinned: start from the usual ones.
        local seed = {}
        for _, app in ipairs(launches.top(apps, opts.seed or 5)) do seed[#seed + 1] = app.name end
        if #seed > 0 then write(seed) end
    end
    local windows = shell.windows()
    local out, claimed = {}, {}
    local function claim(item)
        for _, w in ipairs(windows) do
            if not claimed[w.id] and M.owns(item.app, w) then
                item.windows[#item.windows + 1] = w
                item.focused = item.focused or w.focused
                claimed[w.id] = true
            end
        end
    end
    for _, name in ipairs(M.pins()) do
        local app = by_name[name]
        if app then
            local item = { app = app, windows = {}, pinned = true }
            claim(item)
            out[#out + 1] = item
        end
    end
    for _, w in ipairs(windows) do
        if not claimed[w.id] then
            -- The best match: the same name, else the plainest command.
            local app
            local id = (w.app_id or ""):lower()
            for _, cand in ipairs(apps) do
                if M.owns(cand, w) then
                    if (cand.name or ""):lower() == id then app = cand break end
                    if not app or #(cand.exec or "") < #(app.exec or "") then app = cand end
                end
            end
            app = app or { name = w.title ~= "" and w.title or w.app_id, exec = w.app_id or "", loose = true }
            local item = { app = app, windows = {}, pinned = false }
            claim(item)
            if #item.windows == 0 then item.windows = { w }; item.focused = w.focused; claimed[w.id] = true end
            out[#out + 1] = item
        end
    end
    for _, item in ipairs(out) do item.window = item.windows[1] end
    return out
end

-- Focus the application's next window, or start it.
function M.activate(item)
    if #item.windows == 0 then
        if not item.app.loose then launches.launch(item.app) end
        return
    end
    local next = item.windows[1]
    for i, w in ipairs(item.windows) do
        if w.focused then next = item.windows[i % #item.windows + 1] end
    end
    shell.focus(next.id)
end

-- ---- the look ------------------------------------------------------------------

local function palette()
    local p = opts.palette
    if type(p) == "function" then p = p() end
    p = p or shell.theme or {}
    return {
        accent = p.accent or "#7AA2F7", surface = p.surface or "#1E1E2E", text = p.text or "#E6E6F0",
        text_dim = p.text_dim or "#9AA0B4", danger = p.danger or "#F7768E",
    }
end

local function default_art(app, size)
    if app.icon then return shell.image { path = app.icon, width = size, height = size, fit = "contain" } end
    local p = palette()
    return shell.row { width = size, height = size, radius = size / 2, justify = "center",
        background = shell.alpha(p.accent, 0.3),
        shell.text(((app.name or "?"):match("[%w]") or "?"):upper(), { font = "Sans Bold " .. size * 0.4, color = p.text }) }
end

local DEFAULT = {}
function DEFAULT.tile(item, s)
    local p = palette()
    local a = shell.alpha
    return shell.box { left = 0, top = 0, width = s.size, height = s.size, radius = s.size * 0.28,
        background = item.focused and a(p.accent, 0.28) or a(p.text, s.hot and 0.14 or 0.07),
        border = a(p.text, 0.08) }
end
function DEFAULT.mark(item)
    local p = palette()
    return shell.box { width = item.focused and 14 or (item.window and 5 or 0), height = 3, radius = 1.5,
        background = item.focused and p.accent or p.text_dim, animate = "snappy" }
end
function DEFAULT.shelf(row)
    local p = palette()
    return shell.row { height = (opts.size or 46) + 20, radius = 20, padding = { 0, 10 },
        background = shell.alpha(p.surface, 0.86), border = shell.alpha(p.text, 0.08),
        shadow = { 0, 8, shell.alpha("#000000", 0.25), 24 }, row }
end
function DEFAULT.menu(rows)
    local p = palette()
    local col = { width = 190, radius = 12, padding = 6, align = "stretch", gap = 1,
        background = p.surface, border = shell.alpha(p.text, 0.1), shadow = { 0, 8, shell.alpha("#000000", 0.3), 20 } }
    for i, r in ipairs(rows) do col[i] = r end
    return shell.column(col)
end

local function style(name) return (opts.style and opts.style[name]) or DEFAULT[name] end

-- ---- the popup ------------------------------------------------------------------

local menu -- { name, index } while the menu is open
local drag -- { name, index, dx } while a pin is dragged
local menu_timer

local function close_menu()
    menu = nil
    shell.redraw()
end

local function keep_menu()
    if menu_timer then shell.cancel(menu_timer) end
    menu_timer = shell.after(5000, function() menu_timer = nil; close_menu() end)
end

local function menu_rows(item, p)
    local a = shell.alpha
    local rows = {}
    local function entry(id, icon, label, fn, color)
        rows[#rows + 1] = shell.row { id = "dock:menu:" .. id, height = 30, radius = 8, padding = { 0, 10 }, gap = 9,
            hover = { background = a(p.text, 0.08) },
            on_click = function() close_menu(); fn() end,
            shell.icon(icon, { size = 13, stroke = 2.2, color = color or p.accent }),
            shell.text(label, { font = opts.font, color = color or p.text }) }
    end
    local name = item.app.name
    rows[#rows + 1] = shell.row { height = 28, padding = { 0, 10 },
        shell.text(name, { font = opts.bold, color = p.text_dim, max_width = 170 }) }
    if not item.app.loose then
        if item.pinned then entry("unpin", "close", "Unpin from the dock", function() M.unpin(name) end)
        else entry("pin", "plus", "Pin to the dock", function() M.pin(name) end) end
        entry("new", "plus", #item.windows > 0 and "New window" or "Open", function() launches.launch(item.app) end)
    end
    if item.pinned then
        entry("left", "previous", "Move left", function() M.move(name, -1) end)
        entry("right", "next", "Move right", function() M.move(name, 1) end)
    end
    if #item.windows > 0 then
        entry("close", "close", #item.windows > 1 and ("Close " .. #item.windows .. " windows") or "Close window",
            function() for _, w in ipairs(item.windows) do shell.close_window(w.id) end end, p.danger)
    end
    return rows
end

local function tile(ctx, item, i, pitch, p)
    local size = opts.size or 46
    local id = "dock:" .. i
    local hot = ctx.hovered == id
    local dragging = drag and drag.index == i
    local s = { size = size, hot = hot, dragging = dragging }
    return shell.column { key = "dock:item:" .. item.app.name, gap = 4, align = "center",
        enter = { scale = 0.6, opacity = 0, translate = { 0, 20 } }, animate = "snappy",
        translate = { dragging and drag.dx or 0, 0 },
        shell.stack {
            id = id, width = size, height = size,
            translate = { 0, 0 }, scale = 1,
            hover = not drag and { translate = { 0, -5 }, scale = 1.06 } or nil,
            press = { scale = 0.94 },
            animate = { stiffness = 420, damping = 21 },
            on_drag = function(info)
                if not drag then
                    drag = { name = item.app.name, index = i, start = info.px, dx = 0, pinned = item.pinned }
                    return
                end
                drag.dx = item.pinned and (info.px - drag.start) or 0
                if info.done then
                    local moved = math.abs(info.px - drag.start)
                    local d = drag
                    drag = nil
                    if moved < 5 then
                        close_menu()
                        M.activate(item)
                    elseif d.pinned then
                        M.move(d.name, math.floor(d.dx / pitch + (d.dx > 0 and 0.5 or -0.5)))
                    end
                end
                shell.redraw()
            end,
            on_click = function(button)
                if button == "right" then
                    menu = (menu and menu.index == i) and nil or { name = item.app.name, index = i }
                    if menu then keep_menu() end
                    shell.redraw()
                elseif button == "middle" and not item.app.loose then
                    launches.launch(item.app)
                end
            end,
            style("tile")(item, s),
            shell.row { left = 0, right = 0, top = 0, bottom = 0, justify = "center",
                (opts.art or default_art)(item.app, math.floor(size * 0.62)) },
            hot and not menu and not drag and shell.row { key = "dock:name", left = -70, right = -70, top = -30,
                justify = "center", enter = { opacity = 0, translate = { 0, 4 } }, animate = "snappy",
                shell.row { height = 22, radius = 11, padding = { 0, 10 }, background = shell.alpha("#000000", 0.7),
                    shell.text(item.app.name, { font = opts.font, color = "#FFFFFF", max_width = 160 }) } } or false,
        },
        style("mark")(item),
    }
end

function M.install(options)
    options = options or {}
    opts = options
    opts.name = options.name or "dock"
    opts.font = options.font or "Sans Medium 9"
    opts.bold = options.bold or "Sans Bold 9"
    local size = options.size or 46
    opts.size = size
    state.watch(function() shell.redraw() end)
    shell.popup {
        name = opts.name,
        outputs = "all",
        anchor = { "bottom" },
        exclusive = options.exclusive or (size + 26),
        layer = "top",
        input = "widgets",
        view = function(ctx)
            local p = palette()
            local list = M.items()
            local gap = 8
            local pitch = size + gap
            local tiles = {}
            local loose_started = false
            local x = 0
            local menu_x
            for i, item in ipairs(list) do
                if not item.pinned and not loose_started and i > 1 then
                    loose_started = true
                    tiles[#tiles + 1] = shell.box { width = 1, height = size * 0.6, background = shell.alpha(p.text, 0.15) }
                    x = x + 1 + gap
                end
                if menu and menu.index == i then menu_x = x end
                tiles[#tiles + 1] = tile(ctx, item, i, pitch, p)
                x = x + pitch
            end
            if opts.launcher then
                if #list > 0 then
                    tiles[#tiles + 1] = shell.box { width = 1, height = size * 0.6, background = shell.alpha(p.text, 0.15) }
                end
                tiles[#tiles + 1] = shell.column { gap = 4, align = "center",
                    shell.stack { id = "dock:launcher", width = size, height = size,
                        translate = { 0, 0 }, scale = 1, animate = "snappy",
                        hover = { translate = { 0, -5 }, scale = 1.06 }, press = { scale = 0.92 },
                        on_click = function() close_menu(); opts.launcher() end,
                        style("tile")({ app = { name = "Applications" }, launcher = true, windows = {} },
                            { size = size, hot = ctx.hovered == "dock:launcher" }),
                        shell.row { left = 0, right = 0, top = 0, bottom = 0, justify = "center",
                            shell.icon("grid", { size = size * 0.4, stroke = 2.2, color = p.text }) } },
                    shell.box { height = 3 } }
            end
            local row = shell.row { gap = gap, align = "end", padding = { 0, 0, 4, 0 }, tiles }
            local item = menu and list[menu.index]
            return shell.column { padding = { 40, 24, 8, 24 }, align = "center",
                enter = { translate = { 0, 80 } }, animate = { stiffness = 420, damping = 21 },
                shell.column { align = "start", gap = 8,
                    item and shell.row { key = "dock:menu", padding = { 0, 0, 0, math.max(0, math.min(menu_x - 60, x + 20 - 190)) },
                        enter = { opacity = 0, translate = { 0, 6 }, scale = 0.96 }, animate = "snappy",
                        style("menu")(menu_rows(item, p)) } or false,
                    style("shelf")(row, ctx),
                },
            }
        end,
    }
    return M
end

return M
