-- tests/headless-shell-canvas.sh: canvases, a radial gradient and a soft
-- shadow on a grey bar 60 high. Widgets are 40x40 at y = 10, at x = 10, 60,
-- 110, 190 and 240.
shell.bar {
    name = "canvas-bar",
    size = 60,
    view = function()
        return shell.row {
            padding = { 0, 10 }, gap = 10, background = "#202020",
            -- Shapes in pixels, drawn in order.
            shell.canvas {
                width = 40, height = 40,
                { "rect", 0, 0, 40, 40, fill = "#ff0000" },
                { "circle", 20, 20, 8, fill = "#0000ff" },
            },
            -- A view box of 10x10 scaled to the widget; the widget's colour.
            shell.canvas {
                width = 40, height = 40, view = { 10, 10 }, color = "#00ff00",
                { "path", "M 0 10 h 10 V 0 Z", fill = true },
            },
            shell.box { width = 40, height = 40,
                background = shell.gradient("radial", "#ffffff", "#000000") },
            shell.box { width = 20 },
            shell.box { width = 40, height = 40, background = "#000000",
                shadow = { 0, 0, "#ffffff", 8 } },
            -- A list of shapes is spliced in; an arc runs clockwise from 12.
            shell.canvas {
                width = 40, height = 40,
                { { "line", 0, 20, 40, 20, stroke = "#ffff00", width = 4 } },
                { "arc", 20, 20, 15, 0, 180, stroke = "#ff00ff", width = 4 },
                false,
            },
            shell.spacer(),
        }
    end,
}
