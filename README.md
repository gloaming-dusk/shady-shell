# shady-shell

`shady-shell` is the desktop shell for the [Shady](https://github.com/gloaming-dusk/shady)
compositor: a layer-shell client whose bars, panels, launcher, notifications
and lock screen are one hot-reloaded Lua config. It draws with GLES2 (or
`wl_shm` without GL) and has GLSL effects, frosted glass, 3D-placed layer
surfaces, and native C plugins.

It is a separate program with its own release, and talks to the
compositor over the `shady-shell-v1` protocol, which this repository owns
([protocol/shady-shell-v1.xml](protocol/shady-shell-v1.xml)).

## Try it

From any Wayland desktop, with [Nix](https://nixos.org/download):

```sh
nix run github:gloaming-dusk/shady-shell
```

This runs Shady in a window with the shell's own `default.lua` and a terminal.
Most people get the shell through a desktop built on it, such as
[Gloam](https://github.com/gloaming-dusk/gloam) and its Tide desktop.

On NixOS, this flake's module installs it with the PAM services its lock
screen uses; Shady starts the `shady-shell` it finds on `PATH`:

```nix
imports = [ shady-shell.nixosModules.default ];
programs.shady-shell.enable = true;
programs.shady-shell.lock.fingerprint = true;   # optional, with fprintd
```

## Configuration

The shell loads the first of these it finds:

1. `$SHADY_SHELL_CONFIG`
2. `~/.config/shady/shell.lua`
3. the `shell.lua` of the rice in `$SHADY_RICE` (Tide unless set), looked
   up in `$SHADY_RICE_PATH`, `$XDG_DATA_HOME/shady/rices`, `$SHADY_ROOT/rices`
   and each `$XDG_DATA_DIRS/shady/rices`
4. [default.lua](default.lua) (also what `SHADY_RICE=none` means)

The file is reloaded as you edit it. `shell.base("tide", { ... })` at the top
of your own config starts from a rice and changes what you pass it.

- [Shell Lua API](docs/SHELL_LUA_API.md): views, widgets, windows, notifications,
  the lock screen, shader effects, 3D placement
- [Shell plugin API](docs/SHELL_PLUGIN_API.md): native widgets and data sources
  in C, against [include/shady/shell_plugin.h](include/shady/shell_plugin.h)
- [Design](docs/SHELL_DESIGN.md)
- [examples/](examples): small configs to start from

## Building

```sh
nix develop
meson setup build
ninja -C build
meson test -C build
```

Outside Nix it needs meson, wayland-scanner, wayland, wayland-protocols,
wlr-protocols, xkbcommon, cairo, pango, fontconfig and Lua 5.4; EGL/GLESv2,
libsystemd (notifications over D-Bus) and PAM (`shady-auth`, the lock
screen's password check) are optional.

The installed package also provides `shady-shell.pc`, the plugin header and
the protocol XML for shell plugins and compositors built elsewhere.

### Headless tests

`tests/run.sh` runs the shell against a real compositor on a headless
output. The dev shell puts Shady on `PATH`; `SHADY_BIN_DIR` points the
tests at another build of it.

```sh
nix develop -c tests/run.sh               # all of them
nix develop -c tests/run.sh shell-notify  # one
```

## Compatibility

The shell and Shady agree on `shady-shell-v1`. Changes to it are additive
(new requests and events behind a version bump), so a shell runs on an older
compositor with the features that compositor has, and the other way round.
Shady carries a copy of the XML; a change lands here first.

## Licence

Apache-2.0, see [LICENSE](LICENSE).
