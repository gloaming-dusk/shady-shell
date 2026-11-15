-- Which applications are launched, how often and how lately, kept across
-- restarts, for launchers and docks to put the usual ones first. No look.
--
--     local launches = require("launches")
--     launches.launch(app)              -- record it and run it
--     local apps = launches.sort(shell.apps(query, 40))   -- most used first
--     local usual = launches.top(shell.apps("", 512), 6)  -- the six most used
--
--   record(app)    count a launch of app ({name, exec}, as shell.apps gives)
--   launch(app)    record(app), then shell.launch(app)
--   score(app)     how often, weighted by how lately: 0 for never
--   sort(apps)     the list ordered by score, ties kept in their order
--   top(apps, n)   at most n apps with a score above 0, best first
--
-- Kept in the statefile "launches" as `name=count:last-time`.

local M = {}
local state = require("statefile")("launches")

local function key(app)
    return ((app.name or app.exec or "?"):gsub("[^%w_.-]", "_"))
end

local function read(app)
    local v = state.get(key(app))
    if not v then return 0, 0 end
    local count, last = v:match("^(%d+):(%d+)$")
    return tonumber(count) or 0, tonumber(last) or 0
end

function M.record(app)
    local count = read(app)
    state.set(key(app), string.format("%d:%d", count + 1, os.time()))
end

function M.launch(app)
    M.record(app)
    shell.launch(app)
end

function M.score(app)
    local count, last = read(app)
    if count == 0 then return 0 end
    local age = os.time() - last
    local weight = age < 86400 and 1 or age < 7 * 86400 and 0.7 or age < 30 * 86400 and 0.4 or 0.2
    return count * weight
end

function M.sort(apps)
    local scored = {}
    for i, app in ipairs(apps) do scored[i] = { app = app, score = M.score(app), i = i } end
    table.sort(scored, function(x, y)
        if x.score ~= y.score then return x.score > y.score end
        return x.i < y.i
    end)
    local out = {}
    for i, s in ipairs(scored) do out[i] = s.app end
    return out
end

function M.top(apps, n)
    local out = {}
    for _, app in ipairs(M.sort(apps)) do
        if #out >= n or M.score(app) <= 0 then break end
        out[#out + 1] = app
    end
    return out
end

return M
