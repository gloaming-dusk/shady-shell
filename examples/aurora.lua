-- The default UI with a shader effect: aurora light drifting through the
-- dark of the bar, behind the day line.
--
--   SHADY_SHELL_CONFIG=examples/aurora.lua ./build/shady-shell
--
-- Or copy this file to ~/.config/shady/shell.lua; the shader is found in
-- the shell's data directory either way. Edit it and save to see the change
-- live. `focus_shader` puts a widget shader on the focused window's tab the
-- same way (shaders/glow.frag is one, made for rounded widgets).

local t = shell.theme

shell.options = {
    bar_shader = shell.shader("shaders/aurora.frag"),
    bar_uniforms = { strength = 0.55, accent = t.accent, accent_2 = t.accent_2 },
}

dofile(shell.data_dir .. "/default.lua")
