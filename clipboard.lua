-- The clipboard's history, and a panel to copy from it again.
--
-- shady-shell serves what the shell copies itself and reads what other
-- clients copy (shell.set_clipboard, the "clipboard" event: no wl-copy).
-- This module keeps those copies, newest first, across restarts:
--
--     local clipboard = require("clipboard")
--     clipboard.copy("text")                 -- serve it, and remember it
--     clipboard.copy({ path = "shot.png" })  -- a picture
--     for _, e in ipairs(clipboard.history()) do ... end
--     clipboard.install { palette = ..., frame = function(body) ... end }
--     clipboard.toggle()                     -- open the panel
--
-- An entry is { id, kind = "text" | "image", value (the text, or the
-- picture's path), time, pinned }. Pinned entries stay at the top and are
-- never dropped; the others are kept up to `limit` (default 50). The same
-- text copied again moves to the top instead of repeating. Copies that a
-- password manager marks as secret never arrive here.
--
-- Kept in $XDG_STATE_HOME/shady/clipboard.lua; pictures in
-- $XDG_CACHE_HOME/shady/clipboard/, removed with their entry.
--
-- install(options), all optional:
--   name      the popup's name (default "clipboard")
--   limit     unpinned entries kept (else the statefile "clipboard"'s
--             `limit`, which the Settings app writes; else 50)
--   paste     true: after copying from the panel, press Ctrl+V in the
--             focused window
--   palette   accent, surface, text, text_dim, danger (default shell.theme;
--             a function is called on every repaint)
--   font, bold, title_font
--   frame     function(body) -> the panel around the body
-- The panel: type to search, Up/Down to choose, Enter copies, Tab pins,
-- Delete removes, Escape closes.

local M = {}

local entries -- newest first
local serial = 0
local limit = 50
local loaded = false

local function state_path()
    local base = os.getenv("XDG_STATE_HOME")
    if not base or base == "" then base = (os.getenv("HOME") or "/tmp") .. "/.local/state" end
    return base .. "/shady", base .. "/shady/clipboard.lua"
end

local function load()
    if loaded then return end
    loaded = true
    entries = {}
    local _, path = state_path()
    local chunk = loadfile(path, "t", {})
    local ok, list = false, nil
    if chunk then ok, list = pcall(chunk) end
    if ok and type(list) == "table" then
        for _, e in ipairs(list) do
            if type(e) == "table" and (e.kind == "text" or e.kind == "image") and type(e.value) == "string" then
                serial = serial + 1
                entries[#entries + 1] = { id = serial, kind = e.kind, value = e.value,
                    time = tonumber(e.time) or os.time(), pinned = e.pinned == true }
            end
        end
    end
end

-- Texts longer than this are kept while the shell runs but not written out.
local KEEP_BYTES = 64 * 1024

local saved_text -- what this process wrote last

local function save()
    local dir, path = state_path()
    local lines = { "-- The clipboard's history, written by shady-shell.", "return {" }
    for _, e in ipairs(entries) do
        if e.kind == "image" or #e.value <= KEEP_BYTES then
            lines[#lines + 1] = string.format("  { kind = %q, value = %q, time = %d, pinned = %s },",
                e.kind, e.value, e.time, tostring(e.pinned))
        end
    end
    lines[#lines + 1] = "}\n"
    local temporary = path .. ".new"
    local f = io.open(temporary, "w")
    if not f then
        os.execute(string.format("mkdir -p %q", dir))
        f = io.open(temporary, "w")
        if not f then return end
    end
    saved_text = table.concat(lines, "\n")
    f:write(saved_text)
    f:close()
    os.rename(temporary, path)
end

-- The history changed elsewhere (the Settings app cleared it): read it again.
local settings = require("statefile")("clipboard")
local function watch()
    if not shell.watch then return end
    local dir, path = state_path()
    os.execute(string.format("mkdir -p %q", dir))
    shell.watch(path, function()
        local f = io.open(path, "r")
        local now = f and f:read("a") or ""
        if f then f:close() end
        if now == saved_text then return end
        saved_text = now
        loaded = false
        load()
        shell.redraw()
    end)
    settings.watch(function()
        local n = tonumber(settings.get("limit"))
        if n then M.set_limit(n) end
    end)
end

local function forget(e)
    -- A picture the shell wrote to its cache goes with its entry.
    if e.kind == "image" and e.value:find("/shady/clipboard/", 1, true) then os.remove(e.value) end
end

local function trim()
    local kept, unpinned = {}, 0
    for _, e in ipairs(entries) do
        if e.pinned then kept[#kept + 1] = e
        else
            unpinned = unpinned + 1
            if unpinned <= limit then kept[#kept + 1] = e else forget(e) end
        end
    end
    entries = kept
end

local function remember(kind, value)
    load()
    for i, e in ipairs(entries) do
        if e.kind == kind and e.value == value then
            table.remove(entries, i)
            e.time = os.time()
            table.insert(entries, 1, e)
            save()
            shell.redraw()
            return e
        end
    end
    serial = serial + 1
    local e = { id = serial, kind = kind, value = value, time = os.time(), pinned = false }
    table.insert(entries, 1, e)
    trim()
    save()
    shell.redraw()
    return e
end

function M.history()
    load()
    -- Pinned first, each part newest first.
    local out = {}
    for _, e in ipairs(entries) do if e.pinned then out[#out + 1] = e end end
    for _, e in ipairs(entries) do if not e.pinned then out[#out + 1] = e end end
    return out
end

function M.available() return shell.clipboard_available and shell.clipboard_available() or false end

-- Copy text, { path = picture }, or an entry of the history.
function M.copy(what)
    local kind, value
    if type(what) == "string" then kind, value = "text", what
    elseif type(what) == "table" and what.path then kind, value = "image", what.path
    elseif type(what) == "table" and what.kind then kind, value = what.kind, what.value
    else return false end
    if not shell.set_clipboard then return false end
    local ok = kind == "text" and shell.set_clipboard(value) or shell.set_clipboard({ path = value })
    if ok then remember(kind, value) end
    return ok
end

function M.pin(id, on)
    load()
    for _, e in ipairs(entries) do
        if e.id == id then e.pinned = on == nil and not e.pinned or on end
    end
    trim()
    save()
    shell.redraw()
end

function M.remove(id)
    load()
    for i, e in ipairs(entries) do
        if e.id == id then
            table.remove(entries, i)
            forget(e)
            break
        end
    end
    save()
    shell.redraw()
end

-- Forget everything but the pinned entries.
function M.clear()
    load()
    local kept = {}
    for _, e in ipairs(entries) do
        if e.pinned then kept[#kept + 1] = e else forget(e) end
    end
    entries = kept
    save()
    shell.redraw()
end

function M.set_limit(n)
    limit = math.max(1, math.floor(tonumber(n) or 50))
    load()
    trim()
    save()
end

-- What other clients copy.
if shell.on then
    shell.on("clipboard", function(kind, value) remember(kind, value) end)
    limit = tonumber(settings.get("limit")) or limit
    watch()
end

-- ---- the panel ---------------------------------------------------------------

local function ago(t)
    local s = os.time() - t
    if s < 60 then return "now" end
    if s < 3600 then return (s // 60) .. " min" end
    if s < 86400 then return (s // 3600) .. " h" end
    return os.date("%b %d", t)
end

local function first_line(text)
    local line = text:gsub("^%s+", ""):match("^[^\n]*") or ""
    if #line > 200 then line = line:sub(1, 200) end
    return line
end

local ui = { query = "", selected = 1 }
local opts = {}

local function matches()
    local q = ui.query:lower()
    local out = {}
    for _, e in ipairs(M.history()) do
        if q == "" or (e.kind == "text" and e.value:lower():find(q, 1, true))
            or (e.kind == "image" and ("image picture"):find(q, 1, true)) then
            out[#out + 1] = e
        end
    end
    return out
end

local function choose(e)
    if not e then return end
    shell.close(opts.name)
    M.copy(e)
    if opts.paste then shell.after(120, function() shell.key("Ctrl+v") end) end
end

local function palette()
    local p = opts.palette
    if type(p) == "function" then p = p() end
    p = p or shell.theme or {}
    return {
        accent = p.accent or "#7AA2F7", surface = p.surface or "#1E1E2E", text = p.text or "#E6E6F0",
        text_dim = p.text_dim or "#9AA0B4", danger = p.danger or "#F7768E",
    }
end

local function row(e, i, p, ctx)
    local a = shell.alpha
    local id = "clip:" .. e.id
    local on = i == ui.selected
    local hot = on or ctx.hovered == id
    local body
    if e.kind == "image" then
        body = shell.row { gap = 10, shrink = 1,
            shell.image { path = e.value, width = 64, height = 40, fit = "cover", radius = 6 },
            shell.text("Picture", { font = opts.font, color = p.text }) }
    else
        local lines = select(2, e.value:gsub("\n", "")) + 1
        body = shell.column { align = "start", gap = 1, shrink = 1,
            shell.text(first_line(e.value), { font = opts.font, color = p.text, shrink = 1 }),
            lines > 1 and shell.text(lines .. " lines", { font = opts.small, color = p.text_dim }) or false }
    end
    return shell.row {
        id = id, key = id, height = e.kind == "image" and 54 or 44, radius = 10, padding = { 0, 12 }, gap = 10,
        background = on and a(p.accent, 0.18) or (hot and a(p.text, 0.06) or nil),
        on_click = function() choose(e) end,
        shell.row { grow = 1, shrink = 1, body },
        shell.text(ago(e.time), { font = opts.small, color = p.text_dim }),
        shell.row { id = id .. ":pin", width = 26, height = 26, radius = 13, justify = "center",
            background = e.pinned and a(p.accent, 0.25) or nil,
            hover = { background = a(p.text, 0.1) },
            on_click = function() M.pin(e.id) end,
            shell.icon("check", { size = 12, stroke = 2.4, color = e.pinned and p.accent or a(p.text_dim, hot and 1 or 0.4) }) },
        shell.row { id = id .. ":del", width = 26, height = 26, radius = 13, justify = "center",
            hover = { background = a(p.danger, 0.15) },
            on_click = function() M.remove(e.id) end,
            shell.icon("close", { size = 11, stroke = 2.4, color = a(p.text_dim, hot and 1 or 0.4) }) },
    }
end

function M.install(options)
    options = options or {}
    opts = options
    opts.name = options.name or "clipboard"
    opts.font = options.font or "Sans Medium 10"
    opts.small = options.small or "Sans 8.5"
    opts.bold = options.bold or "Sans Bold 10"
    opts.title_font = options.title_font or "Sans Bold 13"
    if options.limit then M.set_limit(options.limit) end
    shell.popup {
        name = opts.name,
        keyboard = "exclusive",
        close_on_blur = true,
        text_input = true,
        input = "widgets",
        view = function(ctx)
            local p = palette()
            local a = shell.alpha
            local list = matches()
            if ui.selected > #list then ui.selected = math.max(1, #list) end
            local rows = {}
            local first = math.max(1, math.min(ui.selected - 4, #list - 8))
            for i = first, math.min(#list, first + 8) do rows[#rows + 1] = row(list[i], i, p, ctx) end
            if #list == 0 then
                rows[1] = shell.column { align = "center", gap = 4, padding = { 24, 0 },
                    shell.text(ui.query == "" and "Nothing copied yet" or "Nothing matches",
                        { font = opts.bold, color = p.text }),
                    shell.text(M.available() and "What you copy shows up here."
                        or "This compositor has no clipboard access (wlr-data-control).",
                        { font = opts.small, color = p.text_dim }) }
            end
            local preedit = ctx.preedit or ""
            local body = shell.column { width = 520, align = "stretch", gap = 10,
                shell.row { gap = 10,
                    shell.text("Clipboard", { font = opts.title_font, color = p.text }),
                    shell.spacer(),
                    shell.row { id = "clip:clear", height = 26, radius = 13, padding = { 0, 10 },
                        hover = { background = a(p.text, 0.08) },
                        on_click = function() M.clear() end,
                        shell.text("Clear", { font = opts.small, color = p.text_dim }) } },
                shell.row { height = 36, radius = 10, padding = { 0, 12 }, gap = 8,
                    background = a(p.text, 0.06),
                    shell.icon("search", { size = 13, color = p.text_dim }),
                    shell.text(ui.query, { font = opts.font, color = p.text, shrink = 1 }),
                    preedit ~= "" and shell.text(preedit, { font = opts.font, color = p.accent }) or false,
                    shell.box { width = 1.5, height = 16, background = p.accent, caret = true },
                    ui.query == "" and preedit == "" and shell.text("Search", { font = opts.font,
                        color = a(p.text_dim, 0.7) }) or false },
                shell.column { align = "stretch", gap = 2, rows },
                shell.text("↵ copy   Tab pin   Del remove   Esc close", { font = opts.small, color = p.text_dim }),
            }
            if options.frame then return options.frame(body) end
            return shell.column { padding = 28, shell.column {
                padding = 16, radius = 16, background = p.surface, border = a(p.text, 0.08),
                shadow = { 0, 10, a("#000000", 0.25), 28 }, align = "stretch",
                enter = { opacity = 0, scale = 0.96 }, exit = { opacity = 0, scale = 0.98 }, animate = "snappy",
                body } }
        end,
        on_key = function(key, text)
            local list = matches()
            if key == "Escape" then
                if ui.query ~= "" then ui.query = "" else shell.close(opts.name) end
            elseif key == "Return" or key == "KP_Enter" then choose(list[ui.selected])
            elseif key == "Down" then ui.selected = math.min(#list, ui.selected + 1)
            elseif key == "Up" then ui.selected = math.max(1, ui.selected - 1)
            elseif key == "Tab" then if list[ui.selected] then M.pin(list[ui.selected].id) end
            elseif key == "Delete" then if list[ui.selected] then M.remove(list[ui.selected].id) end
            elseif key == "BackSpace" then
                local cut = utf8.offset(ui.query, -1)
                if cut then ui.query = ui.query:sub(1, cut - 1) end
                ui.selected = 1
            elseif text ~= "" and #ui.query + #text < 120 then
                ui.query = ui.query .. text
                ui.selected = 1
            end
            shell.redraw()
        end,
    }
    return M
end

function M.toggle()
    ui.query, ui.selected = "", 1
    if opts.name then shell.toggle(opts.name) end
end

return M
