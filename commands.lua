-- Words from the compositor: a rice's keys, bound in its init.lua, reach
-- the shell as a published value, and this turns them back into calls.
--
-- In the compositor (a serial makes the same word twice still a change):
--
--     local n = 0
--     shady.bind("Super+l", function() n = n + 1; shady.publish("my.do", "lock " .. n) end)
--
-- In the shell:
--
--     require("commands").listen("my.do", {
--         lock = function() ... end,
--         volume = function(arg) ... end,   -- "volume +5" gives "+5"
--     })
--
-- `handlers` may also be one function(verb, arg). Values replayed when the
-- shell connects (the last word sent before it started) are not presses
-- and are ignored, as is anything in the first two seconds.

local M = {}

function M.listen(key, handlers)
    local started = os.time()
    shell.on("value", function(k, value)
        if k ~= key or not value or os.time() - started < 2 then return end
        local verb, arg = (value:gsub("%s+%d+$", "")):match("^(%S+)%s*(.-)%s*$")
        if not verb then return end
        if type(handlers) == "function" then
            handlers(verb, arg)
        elseif handlers[verb] then
            handlers[verb](arg)
        else
            shell.log(string.format("commands: %s: no handler for %q", key, verb))
        end
    end)
end

return M
