# Changelog

## Unreleased

- `shell.popup{close_on_blur = true}` closes the popup when it loses the
  keyboard: a click on a window, or another popup opening.
- `tests/run.sh` no longer reaches the session it is run from: the
  outputs test's `shadyctl quit` followed `$SHADY_SOCKET` and ended it.
- shady-shell has its own repository, moved out of
  [Shady](https://github.com/gloaming-dusk/shady) with its history. It builds
  without the compositor: the `shady-shell-v1` protocol and the shell plugin
  header are owned here, and installed (with `shady-shell.pc`) for plugins
  and compositors built elsewhere.
- Rices are found in `$SHADY_RICE_PATH`, `$XDG_DATA_HOME/shady/rices`,
  `$SHADY_ROOT/rices` and `$XDG_DATA_DIRS/shady/rices`, file by file, so a
  rice's `shell.lua` can be installed by a different package than its
  compositor config.
- NixOS: `programs.shady-shell` (`enable`, `package`, `plugins`,
  `lock.fingerprint`), which installs the shell and its `shady-lock` PAM
  services; `programs.shady.lock.fingerprint` moved here.
- `tests/run.sh` runs the headless tests against any Shady on `PATH`.
- `shell.canvas`: a widget of vector shapes (lines, rectangles, circles,
  arcs, SVG-style paths), filled or stroked with colours and gradients, in
  pixels or scaled from a `view` box. Shapes are data in the widget tree, so
  a canvas is damaged, animated and left alone like any other widget.
- Soft shadows: `shadow = {x, y, colour, blur}` blurs the shadow (a glow,
  with no offset), and the blur animates. `shell.gradient("radial", ...)`
  runs from the centre of a box to its edges.
- The default UI is redrawn as Meridian: a bar standing on the line of the
  day, with a sun on it whose colour, the colour of the hour, lights
  whatever is active; a launcher whose query is its headline; a clock sheet
  with the day as a wave; cards on soft shadows. It is set in Manrope and
  Instrument Serif, installed in the data directory's `fonts`.
  `shell.options.light = false` keeps the theme's accent at every hour. The
  `Sans`-set pills, the brand tile and the "Shady" wordmark are gone, and
  popups keep a transparent margin for their shadows, so their surfaces are
  larger than their cards.
- A wallpaper manager, `require("wallpaper")`: a rice installs its own
  wallpaper (a shader, a view, a plugin's widget, a picture, a folder or a
  colour) as the default, and a picture saved as
  `~/.config/shady/wallpaper.jpg`, a folder `~/.config/shady/wallpapers`,
  or a choice made with the new `shady-wallpaper` command replaces it,
  per output if wanted. Changes show at once, with a cross-fade; choices
  last across sessions. The default UI uses it, with no wallpaper of its
  own.
- `shell.image` reads JPEG and WebP besides PNG (libjpeg and libwebp,
  optional at build time), reduces pictures over 8192 pixels, reads a file
  again when it changes on disk, and takes `fit` (`fill`, `cover`,
  `contain`, `center`, `tile`). A picture drawn at another size is scaled
  once, not on every repaint.
- `shell.files`, `shell.stat`, `shell.watch`, `shell.image_size` and
  `shell.image_formats`, for configs that look at files; `shell.renderer`
  (`"gl"` or `"shm"`).

Earlier changes are in Shady's changelog, up to its 0.2.0.
