-- tests/headless-shell-dismiss.sh: a popup with close_on_blur and no
-- keyboard, a bar, and a wallpaper on the background layer that takes the
-- pointer only over widgets (it has none), as the wallpaper module's does.
shell.popup {
    name = "dismiss-wall", layer = "background", fill = true, outputs = "all", input = "widgets",
    view = function(ctx)
        return shell.box { width = ctx.width, height = ctx.height, background = "#203040" }
    end,
}
shell.bar { name = "dismiss-bar", size = 30,
    view = function() return shell.row { id = "bar:thing", background = "#404040", on_click = function() end } end }
shell.popup {
    name = "panel", anchor = { "top", "right" }, close_on_blur = true,
    view = function() return shell.box { width = 200, height = 120, background = "#ff8800" } end,
}
local function report() shell.log("PANEL " .. (shell.is_open("panel") and "open" or "closed")) end
shell.on("value", function(key, value)
    if key ~= "test" or not value then return end
    local cmd = value:gsub("^%d+ ", "")
    if cmd == "open" then shell.open("panel")
    elseif cmd == "check" then report()
    elseif cmd:match("^focus ") then
        local want = cmd:sub(7)
        for _, w in ipairs(shell.windows()) do
            if w.app_id == want then shell.focus(w.id) end
        end
    end
end)
