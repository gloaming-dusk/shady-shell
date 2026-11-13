# Shell design

Status: phases 1 to 7 implemented (IPC, shell core and render, Lua UI,
shader effects and native plugins in the shell; layer backdrop effects, 3D
placement and standard protocols in the compositor). This document describes where `shady-shell` is
going and why. API references for finished pieces live in their own
documents ([IPC API](https://github.com/gloaming-dusk/shady/blob/main/docs/IPC_API.md), [Shell Lua API](SHELL_LUA_API.md),
[Shell plugin API](SHELL_PLUGIN_API.md)).

## Problem

The compositor is easy to rice: Lua configures and scripts it, native C
plugins extend it, and GLSL shaders restyle windows and the scene. The shell
is not. `shell/src/main.c` is one ~2000-line C file with a fixed bar
(workspaces, tasks, clock), a fixed launcher, a context menu and a short
Quick Settings panel. Its only customisation is seven `SHADY_SHELL_*`
colour variables. It ignores `wl_output`, so it has no multi-monitor or
HiDPI support, and its compositor state comes from the private
`shady-shell-v1` protocol, which no other program can use.

Rices are limited by the shell, not by the compositor.

## Goal

Give the shell the same extension model as the compositor:

| | Compositor | Shell |
|---|---|---|
| Configuration and scripting | Lua | Lua |
| Native extensions | C plugin ABI (`SHADY_API_HAS`) | C plugin ABI, same conventions |
| Visual effects | GLSL, host-managed programs | GLSL, host-managed programs, same uniform names |
| Hot reload | `shady.plugins.reload` | config and plugin reload without restarting the session |

A rice author learns one model and uses it for both halves of the desktop.

## Architecture

The shell stays a separate process. A shell bug, a slow Lua loop or a
crashing shell plugin must never take the compositor down, and the shell
must be restartable on its own.

```
compositor ──IPC socket──▶ shady-shell
  │                         ├─ core     Wayland, one layer surface per output, EGL, poll loop
  │                         ├─ render   per-node cairo textures, GL composite, shader effects
  │                         ├─ ui       widget tree, flex layout, input, animation, signals
  │                         ├─ lua      config, widget definitions, hot reload
  │                         ├─ plugin   C ABI: services, custom widgets, shaders
  │                         └─ ipc      client of the compositor socket
  └─ layer-surface effects  backdrop shaders and 3D placement for any layer client
```

### Content in cairo, composition in GL

Text and icons are drawn with cairo and pango into one texture per widget;
only widgets whose content changed are redrawn. Composition, animation and
effects run in GLES2 through EGL. A widget shader receives its own content
as `u_tex`, exactly like a compositor window shader, so effects can bend,
tint or animate any widget.

### No raw GL for plugins

As in the compositor, shell plugins and Lua never see GL handles. They
create programs, set uniforms, provide textures and request draws; the host
owns GL state and frees everything on reload. Uniform names follow
[SHADER_API.md](https://github.com/gloaming-dusk/shady/blob/main/docs/SHADER_API.md): `u_tex`, `u_time`, `u_resolution`,
`u_params`, plus shell-specific `u_widget_size` and `u_hover`.

### Backdrop effects belong to the compositor

A client cannot see what is behind its surface, so glass refraction,
backdrop blur and sky reflections cannot be done in the shell. The
compositor will expose the same per-window shader machinery for layer
surfaces (render hook + `u_scene` sampling + 3D placement). This works for
any layer-shell client, so a bar made with another toolkit also becomes
part of the 3D scene.

Shared look without backdrop access comes from IPC: plugins publish values
(for example afterglow's hour and sky palette) and shell shaders receive
them as uniforms.

## Lua model

Implemented in phase 3; the reference is [SHELL_LUA_API.md](SHELL_LUA_API.md).

```lua
shell.bar {
  name = "top", edge = "top", size = 36,
  view = function(ctx)
    return shell.row { gap = 8, padding = { 0, 10 },
      workspaces(ctx),            -- plain Lua functions returning widgets
      shell.spacer(),
      shell.text(shell.poll("wpctl get-volume @DEFAULT_AUDIO_SINK@", 2000)),
      shell.text(shell.date("%H:%M")),
    }
  end,
}
```

Each surface has a view function that returns a fresh widget tree every
time the surface repaints. This replaced the signals planned earlier: a
view simply reads the current state (`shell.windows()`, `shell.poll(...)`,
its own Lua variables), so there is nothing to bind or unbind, and repaints
are already coalesced by the core, so rebuilding a bar's few dozen widgets
costs nothing noticeable. Anything that changes what a view would return
(compositor state, a polled value, the clock, hover, `shell.redraw()`)
marks the surfaces dirty.

C owns layout (a small flexbox), drawing, hit-testing and hover; Lua owns
structure, style and behaviour. Widgets are `row`, `column`, `stack`,
`text`, `icon`, `pip`, `image`, `spacer` and `canvas`; anything richer (tabs
on the bar, menu rows, cards) is a Lua function, as `default.lua` shows. A
`canvas` holds vector shapes as data, not as a drawing callback: views stay
pure, the tree can still be hashed and diffed, and an idle canvas costs
nothing. Popups are declared
with `shell.popup{}` and opened with `shell.open(name, args)`.

## Phases

1. **Compositor IPC** — done. Unix socket with JSON lines: queries,
   commands and event subscriptions, plus the `shadyctl` CLI. Published
   values (`publish_value`, `shady.publish`, `value.changed`) carry rice state
   such as the current hour to the shell (`shell.compositor_value`). Useful on its
   own to scripts and other bars. See [IPC_API.md](https://github.com/gloaming-dusk/shady/blob/main/docs/IPC_API.md).
2. **Shell core and render** — done. One bar per output that follows
   hotplug and scale changes, integer HiDPI scaling, a poll loop with
   timers and fd watches, repaints coalesced on frame callbacks, and two
   renderers: GLES2 composition through EGL (default) and a `wl_shm`
   fallback. The UI was split out of the old single `main.c` without
   changing its behaviour; see "Code layout" below.
3. **UI and Lua** — done. Widget trees from Lua view functions, flexbox
   layout, hover and clicks, `shell.poll`/`shell.listen`/`shell.date`, popups
   that size themselves, and hot reload that keeps the running UI when a
   new config fails. The bar, launcher, task menu and Quick Settings now live
   in `default.lua`; the existing `headless-shell-*` tests pass
   unchanged.
4. **Shader effects** — done. Surface and widget fragment shaders with the
   cairo drawing as `u_tex`, host-supplied uniforms and Lua uniforms;
   shaders using `u_time` are re-composited every frame without running
   Lua, so the default (static) UI still costs nothing when idle. Example
   shaders ship in `shell/shaders/`.
5. **Shell C plugin ABI** — done. `include/shady/shell_plugin.h`: plugins
   publish values, register actions and cairo-drawn widget types, and run
   timers and fd watches in the shell loop, without touching Lua. They live
   for the shell process and survive config reloads; the shell releases
   what they registered. `sysinfo` (CPU, memory, load, a history graph)
   ships as the example. Audio, tray and notification plugins can now be
   written against it.
6. **Layer-surface effects** — backdrop effects done. `shady.layer_effect(namespace, ...)`
   in the compositor's Lua captures the scene behind any layer-shell
   surface with that namespace and draws it through frosted glass (blur,
   saturation, tint) or a custom shader, masked by the surface's alpha. It
   works for any layer client, `shady-shell` or not, in spatial mode.
   `shell/examples/glass.lua` makes the default UI translucent for it.
   Fixed on the way: spatial mode now draws layer surfaces in layer order.
   3D placement is done too: `shady.layer_transform(namespace, ...)` tilts,
   turns and recedes layer surfaces through a screen-attached perspective,
   and maps pointer input back through the same plane. Backdrop effects
   follow transformed surfaces (the effect is drawn over the projected quad),
   and pointer input is resolved across all layer surfaces in stacking order.
7. **Standard protocols** — done. `wlr-foreign-toplevel-management-unstable-v1`,
   `ext-foreign-toplevel-list-v1` and `ext-workspace-v1` mirror the
   compositor's windows and workspaces (`compositor/src/standard_protocols.c`), so
   waybar's taskbar and workspace modules, Quickshell and other toolkits
   work on Shady. Window title changes now emit `window.title_changed`, which
   also keeps shady-shell's and IPC's task titles current.

## Open questions

- Whether the shell embeds the same Lua version and sandbox as the
  compositor, or a separate `shell.lua` loaded from
  `~/.config/shady/shell.lua`.
- Font and icon theme discovery (fontconfig is already a dependency; icon
  themes are not).

## Code layout

```
src/
  core.c/.h        Wayland globals, outputs, seat input routing, layer
                   surfaces, timers, fd watches, the poll loop
  render.h         renderer interface: begin() gives a cairo image, end() commits
  render_gl.c      EGL + GLES2: upload the image, draw it with a shader, swap
  render_shm.c     double-buffered wl_shm fallback
  theme.c/.h       palette (SHADY_SHELL_* colours) and drawing primitives
  shell.h          the compositor model shared by the files below
  main.c           shady-shell-v1 model, startup
  script.c/.h      Lua runtime: the shell API, bars and popups, poll/listen,
                   config loading and hot reload
  ui.c/.h          widget trees from Lua tables: layout, drawing, hit-testing
  anim.c/.h        transitions: match nodes across trees, spring their look
  notify.c/.h      the notification server (org.freedesktop.Notifications)
  effects.h        shader effects handed from Lua to the GL renderer
  plugins.c/.h     native shell plugins: loading, values, actions, widgets
  apps.c           .desktop index for the launcher
default.lua        the default UI, Meridian
meridian/          how its parts look: the vocabulary (kit), the machine sheet,
                   the calendar and almanac, the lock screen
machine.lua, lockscreen.lua, toasts.lua, commands.lua, focus_timer.lua,
almanac.lua, statefile.lua
                   what a desktop's parts do, without a look; Meridian and
                   Tide are built on them
fonts/             the typefaces it is set in (Manrope, Instrument Serif; OFL)
```

## The default UI

`default.lua` is called Meridian, and it has a subject: the day. The bar
stands on a hairline that runs from midnight to midnight with a tick for
each hour, and a sun crosses it. The colour of that sun is the colour of
the hour (blue at night, rose at dawn, the theme's accent through the day,
amber and violet at dusk), and it is the only accent the UI has: the
focused window's tab, the selected row and the top edge of every card are
lit by it, and nothing else is coloured. There are no boxes around things;
what is active is lit from the line it stands on. Type carries the rest:
Instrument Serif for what is read as a figure (the time, the launcher's
query), Manrope for everything else, small capitals for labels.

It is also the proof of what a config can do with nothing but the Lua API:
the day line, the sun and the clock sheet's day wave are `shell.canvas`
shapes, cards stand on blurred `shadow`s, and nothing animates or repaints
while idle. `shell.options.light = false` keeps the theme's accent at all
hours; `hour = 6.5` fixes the hour, for a screenshot of dawn.

Everything else it has keeps to that idea, and lives in `meridian/`:

- **The day sheet** (the clock) holds the day as a wave, the month (today
  rises in the light; scroll or ‹ › to turn it) and today's notifications,
  each also pinned on the wave at the hour it came.
- **The instruments** on the bar (Wi-Fi, Bluetooth, sound, and the charge
  as a dial with its figure) open **the machine sheet**: the charge set
  large, the processor, memory and disk as dials, sound and screen light as
  lines of light to drag or scroll, the radios, do-not-disturb (only
  critical notifications come up), the music that is playing, a focus
  span, and the session. Log out, Restart and Power off ask once
  ("Sure?") before they run.
- **Now playing** sits on the bar while a player has something: three bars
  that stand up while it plays, and the title. A click plays or pauses.
- **Focus** marks a span of the day line from now to its end (15, 25 or 50
  minutes); the sun walks along it, and the shell says when it is over.
- **The lock screen** runs the day line across the screen as a horizon,
  the sun standing on it, the time large above it; the password is typed
  onto a line as points of light. A fingerprint reader listens too when
  the `shady-lock-fingerprint` PAM service exists.
- **The almanac** stands on the desktop's lower left corner: the date, the
  week, the moon as it is tonight, and the year as a line lit up to today.
  `shell.options.desk = false` leaves it out.

None of this is Meridian's own machinery: reading the machine, the lock's
PAM check, do-not-disturb, the focus timer, the calendar's arithmetic and
the words from the compositor are shady-shell's modules without a look
([SHELL_LUA_API.md](SHELL_LUA_API.md#modules-without-a-look)), which Tide
uses too; `meridian/` only draws. A desktop built on the shell should not
have to copy another one's code to get these. With no compositor side of its own,
Meridian takes keys as the published value `meridian.do` (`lock`,
`controls`, `day`, `launcher`, `dnd`, `focus [minutes]`); `default.lua`
shows the binding. `SHADY_SHELL_OFFLINE=1` (the headless tests) reads and
runs nothing of the machine.

A surface is a `shell_surface` with a handler table. `shell_surface_redraw()`
only marks it dirty; the loop paints dirty surfaces once per iteration and
not faster than the compositor's frame callbacks, so a burst of protocol
events costs one repaint. `draw()` receives a cairo context already scaled
to the surface's buffer scale, so all UI code works in logical pixels.

Repaints are kept to what changed. Before a repaint for a change, the view
runs and its widget tree is hashed: a tree the surface already shows (most
surfaces, when one value changes) is not painted or committed at all. With
the GL renderer, which keeps its buffer, a repaint then clears and draws
only the damage: the widgets that differ from the tree on screen, and on
frames that only move springs, where animated widgets were and are drawn
(a pass of `ui_draw` that paints nothing records it). Only those rows are
uploaded. Hover changes, scaled or rotated widgets, plugin-drawn widgets
and surface shaders still repaint the whole surface. Text shares one Pango
context per scale, so fonts are not looked up again on every paint.
`SHADY_SHELL_PAINT_STATS=1` logs, every two seconds, how often each surface
painted, how many paints were skipped and how much of the surface they
covered; `SHADY_SHELL_NO_DAMAGE=1` paints whole surfaces, to compare.

The compositor side gained one fix here: layer surfaces are re-configured
whenever the output layout changes, so any layer-shell bar (not only this
one) follows mode and scale changes.
