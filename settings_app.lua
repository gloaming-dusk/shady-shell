-- Open the Settings app (apps/settings.lua) from a rice, from the
-- shady-shell that is running: a checkout's bin/shady-settings, an
-- installed one next to shady-shell, or the one on PATH.
--
--     require("settings_app").open()          -- or .open("dock")
--
-- Pages: appearance, windows, input, dock, clipboard, notifications.

local M = {}

local function exists(path)
    if shell.stat then return shell.stat(path) ~= nil end
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

-- The command that starts it, without the page.
function M.command()
    for _, candidate in ipairs {
        shell.data_dir .. "/bin/shady-settings",        -- a checkout
        shell.data_dir .. "/../../../bin/shady-settings", -- installed: <prefix>/share/shady/shell
    } do
        if exists(candidate) then return string.format("%q", candidate) end
    end
    return "shady-settings"
end

function M.open(page)
    local cmd = M.command()
    if page and page ~= "" then cmd = cmd .. " " .. string.format("%q", page) end
    shell.spawn(cmd)
end

return M
