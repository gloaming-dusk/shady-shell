-- Screenshots without grim or wl-copy: the compositor captures the frame
-- (shell.screenshot), the shell cuts out a region (shell.image_crop) and
-- puts the picture on the clipboard itself (shell.set_clipboard).
--
--     local screenshot = require("screenshot")
--     screenshot.install { palette = ..., font = ... }
--     screenshot.open()                    -- the picker: region, window, screen
--     screenshot.take { mode = "screen" }  -- at once, no picker
--     screenshot.take { mode = "window" }  -- the focused window
--
-- The picker covers the output: drag a region (drag inside it to move
-- it), or choose a window of this workspace, or take the whole screen.
-- Tab or R, W, S change the mode; Enter takes; Escape cancels. Pictures go
-- to ~/Pictures/Screenshots ($XDG_PICTURES_DIR/Screenshots), are copied to
-- the clipboard and kept in its history, and a notification says where.
--
-- install(options), all optional:
--   name      the popup's name (default "screenshot")
--   dir       where pictures go
--   copy      false: do not put them on the clipboard
--   notify    false: no notification
--   palette   accent, surface, text, text_dim (default shell.theme; a
--             function is called on every repaint)
--   margin    the toolbar's distance from the bottom (default 36), to
--             clear a dock
--   font, bold

local M = {}
local opts = {}
local pick = { mode = "region" }
local pending -- { path, final, crop, output_width }
local MODES = { "region", "window", "screen" }
local LABELS = { region = "Region", window = "Window", screen = "Screen" }

local function palette()
    local p = opts.palette
    if type(p) == "function" then p = p() end
    p = p or shell.theme or {}
    return { accent = p.accent or "#7AA2F7", surface = p.surface or "#1E1E2E", text = p.text or "#E6E6F0",
        text_dim = p.text_dim or "#9AA0B4" }
end

local function folder()
    if opts.dir then return opts.dir end
    local pictures = os.getenv("XDG_PICTURES_DIR")
    if not pictures or pictures == "" then pictures = (os.getenv("HOME") or "/tmp") .. "/Pictures" end
    return pictures .. "/Screenshots"
end

local function finish(ok, path)
    local p = pending
    pending = nil
    if not ok then
        shell.log("screenshot failed")
        if opts.notify ~= false then shell.notify("Screenshot failed", "The compositor could not save it.", "Screenshot") end
        return
    end
    local final = p.final
    if p.crop then
        local w = shell.image_size(path)
        local scale = (w and p.output_width and p.output_width > 0) and (w / p.output_width) or 1
        local c = p.crop
        local done, why = shell.image_crop(path, final, c.x * scale, c.y * scale, c.w * scale, c.h * scale)
        os.remove(path)
        if not done then
            shell.log("screenshot: crop failed: " .. tostring(why))
            if opts.notify ~= false then shell.notify("Screenshot failed", tostring(why), "Screenshot") end
            return
        end
    end
    local copied = false
    if opts.copy ~= false then
        local ok_mod, clipboard = pcall(require, "clipboard")
        copied = ok_mod and clipboard.copy({ path = final }) or false
    end
    shell.log("screenshot saved: " .. final)
    if opts.notify ~= false then
        local home = os.getenv("HOME") or ""
        local where = final:sub(1, #home) == home and ("~" .. final:sub(#home + 1)) or final
        shell.notify("Screenshot saved", where .. (copied and "\nCopied to the clipboard" or ""), "Screenshot")
    end
    if opts.on_saved then opts.on_saved(final) end
end

-- target: { mode = "screen" | "window" | "region", output = name,
-- window = id, rect = { x, y, w, h } (in the output's logical pixels),
-- output_width = its logical width }.
function M.take(target)
    target = target or { mode = "screen" }
    if pending then return false end
    local dir = folder()
    os.execute(string.format("mkdir -p %q", dir))
    local final = string.format("%s/Screenshot from %s.png", dir, os.date("%Y-%m-%d %H-%M-%S"))
    local window = target.window
    if target.mode == "window" and not window then
        local f = shell.focused()
        window = f and f.id
        if not window then return false end
    end
    local crop = target.mode == "region" and target.rect or nil
    local path = crop and (dir .. "/.screenshot-part.png") or final
    pending = { path = path, final = final, crop = crop, output_width = target.output_width }
    local was_open = opts.name and shell.is_open(opts.name)
    if was_open then shell.close(opts.name) end
    -- Once the picker has left the screen.
    shell.after(was_open and 200 or 0, function()
        local sent = shell.screenshot { path = path, output = target.output,
            window = target.mode == "window" and window or nil }
        if not sent then
            pending = nil
            if opts.notify ~= false then shell.notify("Screenshot failed", "No connection to the compositor.", "Screenshot") end
        end
    end)
    -- If the compositor never answers.
    local mine = pending
    shell.after(8000, function() if pending == mine then finish(false) end end)
    return true
end

if shell.on then
    shell.on("value", function(key, value)
        if not pending or not value then return end
        if key == "screenshot.saved" and value == pending.path then finish(true, value)
        elseif key == "screenshot.failed" then finish(false) end
    end)
end

-- ---- the picker ----------------------------------------------------------------

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function target(ctx)
    if pick.mode == "screen" then return { mode = "screen", output = ctx.output } end
    if pick.mode == "window" then
        local id = pick.window
        if not id then
            local f = shell.focused()
            id = f and f.id
        end
        return id and { mode = "window", window = id, output = ctx.output } or nil
    end
    local r = pick.rect
    if not r or r.w < 4 or r.h < 4 then return nil end
    return { mode = "region", rect = r, output = ctx.output, output_width = ctx.width }
end

local function drag(ctx, info)
    local px = clamp(math.floor(info.px + 0.5), 0, ctx.width)
    local py = clamp(math.floor(info.py + 0.5), 0, ctx.height)
    if info.done then
        pick.drag = nil
        if pick.rect and (pick.rect.w < 4 or pick.rect.h < 4) then pick.rect = nil end
    elseif not pick.drag then
        local r = pick.rect
        if r and px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h then
            pick.drag = { move = true, dx = px - r.x, dy = py - r.y }
        else
            pick.drag = { x = px, y = py }
            pick.rect = { x = px, y = py, w = 0, h = 0 }
        end
    elseif pick.drag.move then
        local r = pick.rect
        r.x = clamp(px - pick.drag.dx, 0, ctx.width - r.w)
        r.y = clamp(py - pick.drag.dy, 0, ctx.height - r.h)
    else
        local d = pick.drag
        pick.rect = { x = math.min(d.x, px), y = math.min(d.y, py), w = math.abs(px - d.x), h = math.abs(py - d.y) }
    end
    shell.redraw()
end

local function veil(ctx, hole)
    local shade = shell.alpha("#000000", 0.45)
    local function piece(x, y, w, h)
        if w <= 0 or h <= 0 then return false end
        return shell.box { left = x, top = y, width = w, height = h, background = shade }
    end
    if not hole then return { piece(0, 0, ctx.width, ctx.height) } end
    local x2, y2 = hole.x + hole.w, hole.y + hole.h
    return { piece(0, 0, ctx.width, hole.y), piece(0, y2, ctx.width, ctx.height - y2),
        piece(0, hole.y, hole.x, hole.h), piece(x2, hole.y, ctx.width - x2, hole.h) }
end

local function toolbar(ctx, p)
    local a = shell.alpha
    local segs = {}
    for _, mode in ipairs(MODES) do
        local on = mode == pick.mode
        segs[#segs + 1] = shell.row { id = "shot:mode:" .. mode, height = 32, radius = 10, padding = { 0, 14 },
            background = on and a(p.accent, 0.3) or nil, hover = { background = a(p.text, 0.08) },
            on_click = function() pick.mode = mode; pick.window = nil; shell.redraw() end,
            shell.text(LABELS[mode], { font = on and opts.bold or opts.font, color = p.text }) }
    end
    local windows = false
    if pick.mode == "window" then
        local active = shell.active_workspace()
        local chips = {}
        local chosen = pick.window or (shell.focused() and shell.focused().id)
        for _, w in ipairs(shell.windows()) do
            if w.workspace == "" or active == "" or w.workspace == active then
                local on = w.id == chosen
                chips[#chips + 1] = shell.row { id = "shot:win:" .. w.id, height = 30, radius = 9, padding = { 0, 12 },
                    background = on and a(p.accent, 0.3) or a(p.text, 0.06), hover = { background = a(p.text, 0.12) },
                    on_click = function() pick.window = w.id; shell.redraw() end,
                    shell.text(w.title ~= "" and w.title or w.app_id, { font = opts.font, color = p.text, max_width = 180 }) }
            end
        end
        windows = #chips > 0 and shell.row { gap = 6, chips }
            or shell.text("No window on this workspace", { font = opts.font, color = p.text_dim })
    end
    local ready = target(ctx) ~= nil
    local hints = { region = "Drag to select · drag inside to move", window = "Choose a window",
        screen = "The whole screen" }
    return shell.column { bottom = opts.margin or 36, left = 0, right = 0, align = "center", gap = 8,
        windows and shell.row { padding = 8, radius = 14, background = a(p.surface, 0.92), windows } or false,
        shell.row { padding = 6, gap = 6, radius = 16, background = a(p.surface, 0.94),
            shadow = { 0, 8, a("#000000", 0.3), 20 },
            shell.row { gap = 2, segs },
            shell.box { width = 1, height = 22, background = a(p.text, 0.15) },
            shell.row { id = "shot:take", height = 32, radius = 10, padding = { 0, 16 }, gap = 6,
                background = ready and p.accent or a(p.text, 0.08), opacity = ready and 1 or 0.6,
                on_click = function() local t = target(ctx); if t then M.take(t) end end,
                shell.icon("capture", { size = 14, color = ready and p.surface or p.text_dim }),
                shell.text("Take", { font = opts.bold, color = ready and p.surface or p.text_dim }) },
            shell.row { id = "shot:close", width = 32, height = 32, radius = 10, justify = "center",
                hover = { background = a(p.text, 0.08) },
                on_click = function() shell.close(opts.name) end,
                shell.icon("close", { size = 13, color = p.text_dim }) },
        },
        shell.row { height = 24, radius = 12, padding = { 0, 12 }, background = a("#000000", 0.55),
            shell.text(hints[pick.mode] .. "   ·   Tab mode   ↵ take   Esc cancel",
                { font = opts.small, color = "#FFFFFF" }) },
    }
end

function M.install(options)
    options = options or {}
    opts = options
    opts.name = options.name or "screenshot"
    opts.font = options.font or "Sans Medium 9.5"
    opts.bold = options.bold or "Sans Bold 9.5"
    opts.small = options.small or "Sans Medium 8.5"
    shell.popup {
        name = opts.name,
        fill = true,
        keyboard = "exclusive",
        view = function(ctx)
            local p = palette()
            local layers = {}
            local function add(w) layers[#layers + 1] = w end
            if pick.mode == "region" then
                add(shell.box { left = 0, top = 0, right = 0, bottom = 0, id = "shot:area",
                    on_drag = function(info) drag(ctx, info) end })
                local hole = pick.rect and pick.rect.w > 0 and pick.rect.h > 0 and pick.rect or nil
                add(veil(ctx, hole))
                if hole then
                    add(shell.box { left = hole.x - 1, top = hole.y - 1, width = hole.w + 2, height = hole.h + 2,
                        border = p.accent, border_width = 2 })
                    add(shell.row { left = hole.x, top = hole.y >= 34 and hole.y - 28 or hole.y + 8, height = 22,
                        radius = 7, padding = { 0, 8 }, background = p.accent,
                        shell.text(string.format("%d × %d", hole.w, hole.h), { font = opts.small, color = p.surface }) })
                end
            elseif pick.mode == "window" then
                add(veil(ctx, nil))
            else
                add(shell.box { left = 0, top = 0, right = 0, bottom = 0, id = "shot:whole",
                    on_click = function() M.take(target(ctx)) end })
                add(shell.box { left = 0, top = 0, width = ctx.width, height = ctx.height,
                    border = p.accent, border_width = 4 })
            end
            add(toolbar(ctx, p))
            pick.last_ctx = ctx
            return shell.stack { width = ctx.width, height = ctx.height, layers }
        end,
        on_key = function(key)
            local k = key:lower()
            if k == "escape" then shell.close(opts.name)
            elseif k == "return" or k == "kp_enter" or k == "space" then
                local t = pick.last_ctx and target(pick.last_ctx)
                if t then M.take(t) end
            elseif k == "tab" or k == "iso_left_tab" then
                for i, mode in ipairs(MODES) do
                    if mode == pick.mode then
                        pick.mode = MODES[(i - 1 + (k == "tab" and 1 or -1)) % #MODES + 1]
                        break
                    end
                end
                pick.window = nil
            elseif k == "r" then pick.mode = "region"
            elseif k == "w" then pick.mode = "window"; pick.window = nil
            elseif k == "s" then pick.mode = "screen" end
            shell.redraw()
        end,
    }
    return M
end

-- The picker, on `output` (default: the compositor's choice).
function M.open(mode, output)
    if pending then return end
    pick.mode = mode or pick.mode or "region"
    pick.window, pick.drag = nil, nil
    if opts.name then shell.open(opts.name, { output = output }) end
end

return M
