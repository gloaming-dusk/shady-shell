# Changelog

## Unreleased

- shady-shell has its own repository, moved out of
  [Shady](https://github.com/gloaming-dusk/shady) with its history. It builds
  without the compositor: the `shady-shell-v1` protocol and the shell plugin
  header are owned here, and installed (with `shady-shell.pc`) for plugins
  and compositors built elsewhere.
- Rices are found in `$SHADY_RICE_PATH`, `$XDG_DATA_HOME/shady/rices`,
  `$SHADY_ROOT/rices` and `$XDG_DATA_DIRS/shady/rices`, file by file, so a
  rice's `shell.lua` can be installed by a different package than its
  compositor config.
- `tests/run.sh` runs the headless tests against any Shady on `PATH`.

Earlier changes are in Shady's changelog, up to its 0.2.0.
