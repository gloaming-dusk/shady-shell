-- A few values that outlive a restart of the shell: one file of
-- `key=value` lines in $XDG_STATE_HOME/shady/<name> (~/.local/state/shady).
--
--     local state = require("statefile")("my-rice")
--     state.get("dnd")            -- a string, or nil
--     state.set("dnd", "1")       -- nil removes the key; the file is rewritten
--
-- Values are strings (numbers are written with tostring). Each name is
-- read once, when it is first asked for, and the same table is returned
-- for the same name.

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

    function store.set(key, value)
        if not values then load() end
        values[key] = value ~= nil and tostring(value) or nil
        local f = io.open(path, "w")
        if not f then
            os.execute(string.format("mkdir -p %q", folder))
            f = io.open(path, "w")
            if not f then return false end
        end
        local keys = {}
        for k in pairs(values) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do f:write(k, "=", values[k], "\n") end
        f:close()
        return true
    end

    stores[name] = store
    return store
end
