-- Toasts without a look: which notifications to show, a popup that is open
-- exactly while there are any, do-not-disturb, and what a click does.
--
--     local toasts = require("toasts").follow {
--         popup = "toasts",                  -- the rice's popup that draws them
--         hold = function() return shell.is_open("control") end, -- shown elsewhere now
--     }
--     -- in that popup's view:
--     for _, n in ipairs(toasts.shown(4)) do ... end
--
-- follow() registers for the `notifications` and `change` events and syncs
-- once. The module's functions work without it too:
--   shown(limit)   active notifications to show as toasts: with
--                  do-not-disturb on only critical ones; newest first
--   dnd()          whether do-not-disturb is on; kept across restarts
--                  (statefile "notifications"), and shared by every rice
--   set_dnd(on)    turn it on or off; syncs the popup and repaints
--   activate(n)    a click on n: its "default" action if it has one, else dismiss
--   today()        the history since midnight, newest first
--   sync()         open or close the popup now

local M = {}
local state = require("statefile")("notifications")
local followed

function M.dnd() return state.get("dnd") == "1" end

function M.shown(limit)
    local list, quiet = {}, M.dnd()
    for _, n in ipairs(shell.notifications()) do
        if #list >= (limit or math.huge) then break end
        if n.active and (not quiet or n.urgency == "critical") then list[#list + 1] = n end
    end
    return list
end

function M.sync()
    if not followed then return end
    local want = #M.shown(1) > 0 and not (followed.hold and followed.hold())
    if want ~= shell.is_open(followed.popup) then
        if want then shell.open(followed.popup) else shell.close(followed.popup) end
    end
end

function M.set_dnd(on)
    state.set("dnd", on and "1" or nil)
    M.sync()
    shell.redraw()
end

function M.activate(n)
    for _, action in ipairs(n.actions or {}) do
        if action.key == "default" then
            shell.invoke_notification(n.id, "default")
            return
        end
    end
    shell.dismiss_notification(n.id)
end

function M.today()
    local now = os.date("*t")
    local midnight = os.time { year = now.year, month = now.month, day = now.day, hour = 0 }
    local list = {}
    for _, n in ipairs(shell.notifications()) do
        if (n.time or 0) >= midnight then list[#list + 1] = n end
    end
    return list
end

function M.follow(opts)
    followed = { popup = assert(opts.popup, "toasts.follow: popup"), hold = opts.hold }
    shell.on("notifications", M.sync)
    if opts.hold then shell.on("change", M.sync) end
    M.sync()
    return M
end

return M
