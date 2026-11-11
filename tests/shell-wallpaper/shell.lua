-- tests/headless-shell-wallpaper.sh: a rice's own wallpaper (a colour), which
-- dropped files and shady-wallpaper replace. No cross-fade, so every change
-- shows at once.
local wallpaper = require("wallpaper")
wallpaper.install { name = "test-wallpaper", default = "#102030", transition = false }
-- SOURCE: a later install call from a config built on the rice.
