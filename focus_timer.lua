-- A focus timer without a look: a span of time from now, kept in a state
-- file so it survives a reload or a restart, and a notification when it
-- is over.
--
--     local focus = require("focus_timer")
--     focus.start(25)            -- minutes
--     focus.running(), focus.left()      -- whole minutes left, rounded up
--     focus.span()               -- start and end, os.time() seconds, or nil
--     focus.stop()
--
-- Views that read it should also read the clock (shell.date) to repaint
-- each minute. on_done(fn) replaces the notification sent at the end with
-- fn(start, stop).

local M = {}
local state = require("statefile")("focus")
local timer
local done

local function span()
    local from, to = tonumber(state.get("from") or ""), tonumber(state.get("until") or "")
    if from and to then return from, to end
end
M.span = function()
    local from, to = span()
    if to and to > os.time() then return from, to end
end

local function clear()
    if timer then shell.cancel(timer) end
    timer = nil
    state.set("from", nil)
    state.set("until", nil)
end

local function finish()
    local from, to = span()
    timer = nil
    clear()
    if from and to then
        if done then
            done(from, to)
        else
            shell.notify("Time to look up",
                string.format("%d minutes of focus, %s to %s.", math.floor((to - from) / 60 + 0.5),
                    os.date("%H:%M", from), os.date("%H:%M", to)), "Focus")
        end
    end
    shell.redraw()
end

local function arm()
    if timer then shell.cancel(timer) end
    timer = nil
    local _, to = span()
    if not to then return end
    local left = to - os.time()
    if left <= -600 then
        clear() -- ended long ago, while no shell was running
    elseif left <= 0 then
        finish()
    else
        timer = shell.after(left * 1000, finish)
    end
end

function M.running() return M.span() ~= nil end

function M.left()
    local _, to = M.span()
    return to and math.max(0, math.ceil((to - os.time()) / 60)) or 0
end

function M.start(minutes)
    local now = os.time()
    state.set("from", now)
    state.set("until", now + math.floor(minutes * 60))
    arm()
    shell.redraw()
end

function M.stop()
    clear()
    shell.redraw()
end

function M.on_done(fn) done = fn end

arm()

return M
