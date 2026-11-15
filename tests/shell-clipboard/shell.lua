-- tests/headless-shell-clipboard.sh: the clipboard both ways, its history,
-- shell.image_crop, and a statefile another process changes.
local clipboard = require("clipboard")
local dock_state = require("statefile")("dock")
local pic = os.getenv("CLIP_TEST_PNG")

shell.on("clipboard", function(kind, value)
    if kind == "image" then
        local w, h = shell.image_size(value)
        shell.log(string.format("CLIP image %dx%d", w or 0, h or 0))
    else
        shell.log("CLIP text " .. value)
    end
end)

dock_state.watch(function() shell.log("PINS " .. (dock_state.get("pins") or "")) end)

shell.on("value", function(key, value)
    if key ~= "test" or not value then return end
    local cmd = value:gsub("^%d+ ", "")
    if cmd == "copy-text" then
        shell.log("SET " .. tostring(clipboard.copy("from the shell 한글")))
    elseif cmd == "copy-image" then
        shell.log("SETIMG " .. tostring(clipboard.copy({ path = pic })))
    elseif cmd == "crop" then
        local out = os.getenv("XDG_RUNTIME_DIR") .. "/crop.png"
        local ok, why = shell.image_crop(pic, out, 2, 3, 10, 7)
        local w, h = shell.image_size(out)
        shell.log(string.format("CROP %s %dx%d", tostring(ok or why), w or 0, h or 0))
    elseif cmd == "history" then
        local h = clipboard.history()
        shell.log(string.format("HISTORY %d %s", #h, h[1] and h[1].kind or "-"))
    end
end)

shell.bar { name = "clipboard-bar", size = 20, view = function() return shell.row { background = "#202020" } end }
