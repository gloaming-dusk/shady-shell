-- The default UI with a CPU dial and graph on the bar, from the bundled
-- `sysinfo` plugin: a native plugin publishes the numbers and draws the
-- graph, and a canvas draws the dial around the current load.
--
--   SHADY_SHELL_CONFIG=examples/sysinfo.lua ./build/shady-shell

local t = shell.theme
local a = shell.alpha
local ok, err = shell.plugin("sysinfo", { interval = 1000 })

shell.options = {
    bar_extra = function()
        if not ok then return false end
        local cpu = tonumber(shell.value("sysinfo.cpu", "0")) or 0
        return shell.row {
            padding = { 0, 10 }, gap = 9,
            shell.widget("sysinfo.graph", { width = 56, height = 16, color = t.accent }),
            -- A ring, and an arc around it from 12 o'clock for the load.
            shell.canvas {
                width = 18, height = 18, view = { 20, 20 },
                { "circle", 10, 10, 7.5, stroke = a(t.text, 0.14), width = 2.4 },
                { "arc", 10, 10, 7.5, 0, 3.6 * math.max(cpu, 1), stroke = t.accent, width = 2.4,
                    cap = "round" },
            },
            shell.text(string.format("%d%%", cpu), {
                font = "Manrope Bold 9", color = a(t.text, 0.9), width = 30,
            }),
        }
    end,
}

if not ok then shell.log("sysinfo unavailable: " .. tostring(err)) end
dofile(shell.data_dir .. "/default.lua")
