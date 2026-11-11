-- The wallpaper, for any config: a picture, a folder of pictures, a colour,
-- or whatever a rice draws itself (a shader, a view, a plugin's widget).
-- See docs/SHELL_LUA_API.md, "Wallpaper".
--
-- A rice says what its own wallpaper is, and people replace it without
-- touching the rice by putting a picture in ~/.config/shady:
--
--   require("wallpaper").install { default = { shader = shell.shader("sea.frag") } }
--
-- What each output shows is the first of these that can be drawn:
--
--   1. a choice made while running: wallpaper.set(), `shady-wallpaper set`
--      (kept in $XDG_STATE_HOME/shady/wallpaper across sessions)
--   2. the config's own `outputs[name]`, then `source`
--   3. a picture dropped in $XDG_CONFIG_HOME/shady: wallpaper-<output>.<ext>,
--      then wallpaper.<ext>, then a folder `wallpapers/` (a slideshow)
--   4. the rice's `default`
--   5. `color`, or nothing (the compositor's background shows)
--
-- A source that cannot be drawn (a missing file, a folder without
-- pictures) is logged once and skipped, so a bad path never leaves the
-- desktop black.

local M = {}

local HOME = os.getenv("HOME") or ""
local function env_dir(var, fallback)
    local v = os.getenv(var)
    return (v and v ~= "") and v or fallback
end
local CONFIG_DIR = env_dir("XDG_CONFIG_HOME", HOME .. "/.config") .. "/shady"
local STATE_DIR = env_dir("XDG_STATE_HOME", HOME .. "/.local/state") .. "/shady"
local STATE_FILE = STATE_DIR .. "/wallpaper"
-- Relative paths in a config are relative to the config file.
local CONFIG_BASE = (shell.config_path or ""):match("^(.*)/[^/]*$") or "."

M.config_dir, M.state_file = CONFIG_DIR, STATE_FILE

local FORMAT_OF = { png = "png", jpg = "jpeg", jpeg = "jpeg", jpe = "jpeg", jfif = "jpeg", webp = "webp" }
local READABLE = {}
for _, f in ipairs(shell.image_formats or { "png" }) do READABLE[f] = true end

-- Whether a file name looks like a picture this shell can read.
function M.is_picture(name)
    local ext = tostring(name):match("%.(%w+)$")
    return ext ~= nil and READABLE[FORMAT_OF[ext:lower()] or ""] == true
end

-- ---- state -----------------------------------------------------------------

local opts = {
    name = "wallpaper",   -- the layer's namespace, for shady.layer_effect
    fit = "cover",        -- fill | cover | contain | center | tile
    color = nil,          -- under the picture (and the bars of `contain`)
    interval = 600,       -- seconds per picture in a folder; 0 to stay
    order = "name",       -- or "random"
    transition = true,    -- cross-fade; false, or a spring {stiffness, damping}
    drop_in = true,       -- look for pictures in ~/.config/shady
    remember = true,      -- honour wallpaper.set() and the state file
    outputs = {},
}
local installed = false
local chosen = {}          -- [output or "*"] = source, from set() or the state file
local chosen_advance = nil -- the state file's "@next" counter, last seen
local resolved = {}        -- [output] = { what, origin }, until something changes
local warned = {}
local plugins = {}
local folders = {}         -- [dir] = slideshow state
local watching = {}        -- [dir] = watch id

-- A spring of about a second, for the cross-fade.
local FADE = { stiffness = 30, damping = 11 }
local function spring()
    local t = opts.transition
    if t == false then return nil end
    return type(t) == "table" and t or FADE
end

local function warn(key, message)
    if warned[key] then return end
    warned[key] = true
    shell.log("wallpaper: " .. message)
end

local function changed()
    resolved = {}
    shell.redraw()
end

local function watch(dir)
    if watching[dir] ~= nil or not shell.watch then return end
    watching[dir] = shell.watch(dir, changed) or false
end

local function expand(path)
    path = path:gsub("^~/", HOME .. "/"):gsub("^~$", HOME)
    if path:sub(1, 1) ~= "/" then path = CONFIG_BASE .. "/" .. path end
    return path
end

local function dir_of(path) return path:match("^(.*)/[^/]*$") or "/" end

-- ---- folders ---------------------------------------------------------------

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

local function list_pictures(dir, order)
    local out = {}
    for _, f in ipairs(shell.files(dir) or {}) do
        if not f.dir and M.is_picture(f.name) then out[#out + 1] = f.path end
    end
    if order == "random" then shuffle(out) end
    return out
end

local function folder_state(dir, o)
    local f = folders[dir]
    if f then return f end
    local order = o.order or opts.order
    f = { dir = dir, order = order, interval = o.interval or opts.interval, index = 1 }
    f.files = list_pictures(dir, order)
    folders[dir] = f
    watch(dir)
    return f
end

local function fade_out_previous(f)
    if f.fade then shell.cancel(f.fade) end
    f.fade = shell.after(spring() and 1500 or 0, function()
        f.fade, f.previous = nil, nil
        changed()
    end)
end

-- Move a folder `by` pictures on, re-reading it on the way (pictures may
-- have come and gone).
local function advance(f, by)
    local current = f.files[f.index]
    local files = list_pictures(f.dir, f.order)
    if f.order == "random" and #files == #f.files then files = f.files end
    f.files = files
    if #files == 0 then return end
    local at = 1
    for i, p in ipairs(files) do if p == current then at = i end end
    f.index = (at - 1 + by) % #files + 1
    if files[f.index] ~= current then
        f.previous = current
        fade_out_previous(f)
    end
    changed()
end

local function schedule(f)
    if f.timer or not f.interval or f.interval <= 0 then return end
    f.timer = shell.after(math.floor(f.interval * 1000), function()
        f.timer = nil
        advance(f, 1)
        schedule(f)
    end)
end

-- ---- sources ---------------------------------------------------------------

local function picture(path, fit)
    local w, err = shell.image_size(path)
    if not w then return nil, path .. ": " .. tostring(err) end
    watch(dir_of(path))
    return { kind = "picture", path = path, fit = fit or opts.fit }
end

local function folder(dir, o)
    local f = folder_state(dir, o)
    -- Skip what cannot be read, once round the folder at most.
    for _ = 1, #f.files do
        local what = picture(f.files[f.index], o.fit)
        if what then
            what.folder, what.previous = f, f.previous
            schedule(f)
            return what
        end
        f.index = f.index % #f.files + 1
    end
    return nil, dir .. ": no pictures this shell can read"
end

-- What a source draws, or nil and why it cannot be drawn now.
local function describe(src)
    local t = type(src)
    if src == nil or src == false then return nil end
    if t == "function" then return { kind = "view", view = src } end
    if t == "string" then
        if src:match("^#%x+$") then return { kind = "color", color = src } end
        local path = expand(src)
        local st = shell.stat(path)
        if not st then
            watch(dir_of(path))
            return nil, path .. ": no such file"
        end
        if st.dir then return folder(path, {}) end
        return picture(path)
    end
    if t ~= "table" then return nil, "not a wallpaper: " .. tostring(src) end
    if src.type == "shader" then return { kind = "shader", shader = src } end
    if src.gradient then return { kind = "color", color = src } end
    if src.shader then
        return { kind = "shader", shader = src.shader, uniforms = src.uniforms, color = src.color }
    end
    if src.view then return { kind = "view", view = src.view } end
    if src.widget then
        if src.plugin and plugins[src.plugin] == nil then
            local ok, err = shell.plugin(src.plugin, src.options)
            plugins[src.plugin] = ok and true or false
            if not ok then warn("plugin:" .. src.plugin, "plugin " .. src.plugin .. ": " .. tostring(err)) end
        end
        if src.plugin and not plugins[src.plugin] then return nil, "plugin " .. src.plugin .. " did not load" end
        return { kind = "widget", widget = src.widget, props = src.props or {} }
    end
    if src.path then
        local path = expand(src.path)
        local st = shell.stat(path)
        if not st then return nil, path .. ": no such file" end
        if st.dir then return folder(path, src) end
        return picture(path, src.fit)
    end
    if src.dir then return folder(expand(src.dir), src) end
    if src.color then return { kind = "color", color = src.color } end
    return nil, "not a wallpaper (no path, dir, shader, view, widget or color)"
end

-- Pictures dropped in ~/.config/shady.
local function dropped(output)
    local single, per_output, folder_path
    for _, f in ipairs(shell.files(CONFIG_DIR) or {}) do
        local stem = f.name:match("^(.-)%.%w+$")
        if f.dir and f.name == "wallpapers" then
            folder_path = f.path
        elseif not f.dir and M.is_picture(f.name) then
            if stem == "wallpaper" then single = single or f.path
            elseif output and stem == "wallpaper-" .. output then per_output = per_output or f.path end
        end
    end
    return per_output, single, folder_path
end

local function read_state()
    chosen = {}
    local f = io.open(STATE_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local key, value = line:match("^(%S+)%s+(.-)%s*$")
        if key == "@next" then
            local n = tonumber(value)
            if chosen_advance and n and n ~= chosen_advance then
                for _, folder_state in pairs(folders) do advance(folder_state, n - chosen_advance) end
            end
            chosen_advance = n
        elseif key and value ~= "" then
            chosen[key] = value
        end
    end
    f:close()
end

local function write_state()
    os.execute("mkdir -p '" .. STATE_DIR:gsub("'", "'\\''") .. "'")
    local tmp = STATE_FILE .. ".new"
    local f = io.open(tmp, "w")
    if not f then return false end
    local keys = {}
    for k, v in pairs(chosen) do if type(v) == "string" then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do f:write(k, " ", chosen[k], "\n") end
    if chosen_advance then f:write("@next ", chosen_advance, "\n") end
    f:close()
    return os.rename(tmp, STATE_FILE)
end

-- The first source that can be drawn on this output, and where it came from.
local function resolve(output)
    local key = output or "*"
    local hit = resolved[key]
    if hit then return hit[1], hit[2] end
    local candidates = {}
    local function add(src, origin)
        if src ~= nil and src ~= false then candidates[#candidates + 1] = { src, origin } end
    end
    if opts.remember then
        if output then add(chosen[output], "set") end
        add(chosen["*"], "set")
    end
    if output then add(opts.outputs[output], "config") end
    add(opts.source, "config")
    if opts.drop_in then
        local per_output, single, folder_path = dropped(output)
        add(per_output, "file")
        add(single, "file")
        add(folder_path, "file")
    end
    add(opts.default, "rice")
    for _, c in ipairs(candidates) do
        local what, err = describe(c[1])
        if what then
            resolved[key] = { what, c[2] }
            return what, c[2]
        end
        if err then warn(c[2] .. ":" .. err, err) end
    end
    resolved[key] = { false, "none" }
    return false, "none"
end

-- ---- drawing ---------------------------------------------------------------

local function layer(props, w, h)
    props.left, props.top, props.width, props.height = 0, 0, w, h
    return props
end

local function draw(what, ctx)
    local w, h = ctx.width, ctx.height
    if what.kind == "picture" then
        local layers = {}
        if what.previous and what.previous ~= what.path then
            layers[#layers + 1] = shell.image(layer({ key = "wallpaper:" .. what.previous,
                path = what.previous, fit = what.fit }, w, h))
        end
        local s = spring()
        layers[#layers + 1] = shell.image(layer({ key = "wallpaper:" .. what.path,
            path = what.path, fit = what.fit,
            enter = s and { opacity = 0 } or nil, animate = s }, w, h))
        return layers
    elseif what.kind == "shader" then
        local uniforms = what.uniforms
        if type(uniforms) == "function" then uniforms = uniforms(ctx) end
        -- The colour is for a shell that draws no shaders: a shader that
        -- keeps what is drawn under it (u_tex, as a lock screen's needs)
        -- would take an opaque colour there for the picture.
        return shell.box(layer({ shader = what.shader, uniforms = uniforms,
            background = shell.renderer ~= "gl" and what.color or nil }, w, h))
    elseif what.kind == "view" then
        return what.view(ctx)
    elseif what.kind == "widget" then
        local props = {}
        for k, v in pairs(what.props) do props[k] = v end
        return shell.widget(what.widget, layer(props, w, h))
    elseif what.kind == "color" then
        return shell.box(layer({ background = what.color }, w, h))
    end
    return false
end

-- The wallpaper of ctx.output as a widget the size of ctx: what the
-- wallpaper layer shows, and what a lock screen can put under its clock.
function M.widget(ctx, output)
    local what = resolve(output or ctx.output)
    return shell.stack {
        width = ctx.width, height = ctx.height, background = opts.color,
        what and draw(what, ctx) or false,
    }
end

-- ---- the API ---------------------------------------------------------------

-- Declare the wallpaper layer (the first call) and set its options. Later
-- calls change only what they pass, so a config built on a rice with
-- shell.base can call it again with its own `source`.
function M.install(o)
    o = o or {}
    for k, v in pairs(o) do
        if k == "outputs" then
            for name, src in pairs(v) do opts.outputs[name] = src end
        elseif k ~= "name" or not installed then
            opts[k] = v
        end
    end
    for _, f in pairs(folders) do
        if f.timer then shell.cancel(f.timer) end
    end
    folders = {}
    changed()
    if installed then return M end
    installed = true
    if opts.remember then
        read_state()
        -- Steps written from now on move the slideshows.
        chosen_advance = chosen_advance or 0
        -- The state file is read again when it changes (shady-wallpaper),
        -- so its directory has to be there to be watched.
        if not shell.stat(STATE_DIR) then
            os.execute("mkdir -p '" .. STATE_DIR:gsub("'", "'\\''") .. "'")
        end
        local seen
        shell.watch(STATE_FILE, function()
            local f = io.open(STATE_FILE, "r")
            local text = f and f:read("a") or ""
            if f then f:close() end
            if text == seen then return end
            seen = text
            read_state()
            changed()
        end)
    end
    if opts.drop_in then
        watch(CONFIG_DIR)
        watch(CONFIG_DIR .. "/wallpapers")
    end
    shell.popup {
        name = opts.name, layer = "background", fill = true, outputs = "all",
        input = "widgets",
        view = function(ctx) return M.widget(ctx) end,
    }
    return M
end

-- Show `source` (a path, a folder, "#rrggbb", or any source table) on
-- `output`, or everywhere. Paths and colours are remembered across
-- sessions; nil goes back to what the config and the files say.
function M.set(source, output)
    if type(source) == "string" and not source:match("^#") then source = expand(source) end
    if output == nil then
        -- Everywhere means everywhere: drop the outputs' own choices.
        chosen = {}
    end
    chosen[output or "*"] = source
    write_state()
    changed()
end

function M.clear(output) M.set(nil, output) end

-- Move the slideshow on the output (or every one) by `by` pictures (1, or -1 back).
function M.next(output, by)
    if output then
        local what = resolve(output)
        if what and what.folder then advance(what.folder, by or 1) end
        return
    end
    for _, f in pairs(folders) do advance(f, by or 1) end
end

function M.previous(output) M.next(output, -1) end

-- What the output shows: {kind, path, fit, origin}; kind is "picture",
-- "shader", "view", "widget", "color" or "none", origin "set", "config",
-- "file", "rice" or "none".
function M.current(output)
    local what, origin = resolve(output)
    if not what then return { kind = "none", origin = origin } end
    return { kind = what.kind, path = what.path, fit = what.fit, origin = origin,
        folder = what.folder and what.folder.dir or nil }
end

return M
