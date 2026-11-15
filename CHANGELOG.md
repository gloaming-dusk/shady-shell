# Changelog

## Unreleased

- `close_on_blur` closes a popup whenever focus leaves it: a click on any
  window (the focused one too), on the desktop, or another window taking the
  focus, not only the keyboard moving away, so panels without the keyboard
  close too. Bars and docks keep their clicks.
- `require("settings_app").open([page])`: start the Settings app of the
  shady-shell that is running, also from a checkout where it is not on PATH.
- The screenshot picker's hint sits on a dark pill, and `margin` lifts its
  toolbar above a dock.
- The clipboard without wl-copy: through wlr-data-control the shell serves
  what it copies (`shell.set_clipboard(text or {path=})`) and reads what
  other clients copy (the `clipboard` event, `shell.clipboard()`), text
  and pictures, never a password manager's secrets.
- `require("clipboard")`: a history of copies kept across restarts, with
  pins, and a panel to copy from it again.
- `require("dock")`: a dock you arrange: pin, unpin and drag applications
  into your order (kept in the statefile `dock`), with a menu for New
  window, Close and Move; a rice can restyle it.
- `require("screenshot")`: a region, window or screen picker that needs
  neither grim nor wl-copy; pictures go to `~/Pictures/Screenshots` and
  the clipboard. `shell.screenshot{path=, output=, window=}` and
  `shell.image_crop` for it.
- The Settings app (`shady-settings`), from Gloam's, for any rice: a
  wallpaper picker with thumbnails, and pages for the dock's pins, the
  clipboard's history and quiet hours besides the appearance, windows and
  input.
- `statefile`: `watch(fn)` for changes made by another process, `reload()`,
  and writes that replace the file at once. `toasts` follows quiet hours
  turned on elsewhere.
- `skew = degrees`: a horizontal shear about the widget's centre, so a box
  becomes a parallelogram (a slanted tab, a leaning button). It animates
  like `rotate`, and a child with the opposite skew stands upright.
- A drag ends when the pointer leaves the surface. Let go outside it, the
  release went elsewhere and the drag stayed on: a slider followed the
  pointer when it came back.
- `press = {...}`: a style a widget wears while the left button holds it
  down, over `hover`. With a spring it is a key that sinks and springs back.
- Spring presets `"pop"` (jumps past its target and settles), `"jelly"`
  (wobbles) and `"clack"` (a key going down and back).
- Text takes `outline = {width, colour}` and `text_shadow = {x, y,
  colour}`: a stroke around the glyphs, and a hard shadow shaped like them.
- `shell.apps` gives each application's `icon`: the PNG its `Icon=` names
  in the hicolor theme or `pixmaps`.
- `require("launches")`: which applications are launched, how often and how
  lately, for launchers and docks to put the usual ones first.
- Damage tracking counts widgets that ride on an animated parent without
  being animated themselves (tape on a card that springs in), so what
  sticks out of the parent is repainted too.
- The lockscreen module leaves the fingerprint reader alone with
  `SHADY_SHELL_OFFLINE=1`, so headless runs no longer reach the machine's
  real reader.

- Modules without a look, for rices to build their parts on (see
  [Modules without a look](docs/SHELL_LUA_API.md#modules-without-a-look)):
  `machine` (sound, light, power, radios, music, load, the session),
  `lockscreen` (typing, PAM, fingerprint, taking a lock over), `toasts`
  (which to show, do-not-disturb, the popup), `commands` (words published
  by the compositor), `focus_timer`, `almanac` (calendar, moon, year) and
  `statefile`. With `SHADY_SHELL_OFFLINE=1`, as in the headless tests,
  `machine` reads and runs nothing.
- Meridian is built on them and grows the rest of a desktop in its own
  terms, its look in `meridian/`: instruments on the bar opening a machine
  sheet (charge, CPU/memory/disk dials, sound and screen light as lines of
  light, Wi-Fi, Bluetooth, do-not-disturb, the playing music, a focus
  timer, and Lock, Sleep, Log out, Restart, Power off, the last three
  asking first); now playing on the bar; the focus span drawn on the day
  line; a month and today's notifications (pinned on the day wave) in the
  day sheet, which no longer lists the launcher, Next window and
  workspaces; a lock screen with the day as its horizon; an almanac on the
  desktop (`shell.options.desk = false` removes it). Keys reach it as the
  published value `meridian.do`.
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
