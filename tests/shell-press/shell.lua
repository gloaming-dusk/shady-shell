-- A bar for headless-shell-press: a key with a `press` style, sticker
-- lettering, and the icon shell.apps finds for an application.
shell.bar {
    name = "press-bar",
    edge = "top",
    size = 60,
    view = function()
        local apps = shell.apps("Press Probe", 1)
        shell.log("icon=" .. tostring(apps[1] and apps[1].icon))
        return shell.row {
            background = "#202020", padding = { 0, 10 }, gap = 20,
            shell.box { id = "key", width = 40, height = 40, background = "#ff0000", animate = false,
                press = { background = "#00ff00" }, on_click = function() end },
            shell.text("O", { font = "Sans Bold 30", color = "#ffffff", outline = { 4, "#0000ff" },
                text_shadow = { 0, 8, "#ffff00" } }),
        }
    end,
}
