-- A few values that outlive a restart of the shell: one file of
-- `key=value` lines in $XDG_STATE_HOME/shady/<name> (~/.local/state/shady).
--
--     local state = require("statefile")("my-rice")
--     state.get("dnd")            -- a string, or nil
--     state.set("dnd", "1")       -- nil removes the key; the file is rewritten
--     state.watch(function() ... end) -- another process changed the file
--
-- Values are strings (numbers are written with tostring). Each name is
-- read when it is first asked for, and again by reload() or when a watch
-- sees the file change; the same table is returned for the same name.
-- Writes replace the file at once, so a reader never sees half of one.

local stores = {}

local function dir()
    local base = os.getenv("XDG_STATE_HOME")
    if not base or base == "" then base = (os.getenv("HOME") or "/tmp") .. "/.local/state" end
    return base .. "/shady"
end

return function(name)
    assert(type(name) == "string" and name:match("^[%w_.-]+$"), "statefile: a plain file name")
    if stores[name] then return stores[name] end
    local folder = dir()
    local path = folder .. "/" .. name
    local values

    local function load()
        values = {}
        local f = io.open(path, "r")
        if not f then return end
        for line in f:lines() do
            local key, value = line:match("^([%w_.-]+)=(.*)$")
            if key then values[key] = value end
        end
        f:close()
    end

    local store = { path = path }

    function store.get(key)
        if not values then load() end
        return values[key]
    end

    local written -- what this process wrote last, so its own write is not news
    function store.set(key, value)
        if not values then load() end
        values[key] = value ~= nil and tostring(value):gsub("\n", " ") or nil
        local temporary = path .. ".new"
        local f = io.open(temporary, "w")
        if not f then
            os.execute(string.format("mkdir -p %q", folder))
            f = io.open(temporary, "w")
            if not f then return false end
        end
        local keys = {}
        for k in pairs(values) do keys[#keys + 1] = k end
        table.sort(keys)
        local lines = {}
        for _, k in ipairs(keys) do lines[#lines + 1] = k .. "=" .. values[k] .. "\n" end
        written = table.concat(lines)
        f:write(written)
        f:close()
        return os.rename(temporary, path) ~= nil
    end

    function store.reload() load() end

    -- fn() runs after another process changed the file (and it was read
    -- again). Needs a shell with shell.watch.
    local watchers
    function store.watch(fn)
        if not shell or not shell.watch then return false end
        if not watchers then
            watchers = {}
            os.execute(string.format("mkdir -p %q", folder))
            shell.watch(path, function()
                local f = io.open(path, "r")
                local now = f and f:read("a") or ""
                if f then f:close() end
                if now == written then return end
                written = now
                load()
                for _, w in ipairs(watchers) do w() end
            end)
        end
        watchers[#watchers + 1] = fn
        return true
    end

    stores[name] = store
    return store
end
