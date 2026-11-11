project('shady-shell', 'c', version: '0.2.0',
  meson_version: '>=1.1',
  default_options: ['buildtype=debugoptimized', 'c_std=c11', 'warning_level=2'])

# shady-shell is a Wayland client: it builds without the compositor. Its
# private protocol (protocol/shady-shell-v1.xml) is owned here; Shady keeps
# a copy of it for the server side.

cc = meson.get_compiler('c')
wayland_scanner = find_program('wayland-scanner', native: true)
wayland_client = dependency('wayland-client')
wayland_protocols = dependency('wayland-protocols')
wlr_protocols = dependency('wlr-protocols')
cairo = dependency('cairo')
pangocairo = dependency('pangocairo')
xkbcommon = dependency('xkbcommon')
# App fonts for shell.fonts(): fontconfig, and pango's fontconfig font map.
fontconfig = dependency('fontconfig')
pangoft2 = dependency('pangoft2')
lua = dependency('lua5.4', 'lua-5.4', 'lua54', 'lua', required: false)
if not lua.found()
  lua = cc.find_library('lua')
endif
dl = cc.find_library('dl', required: false)
m = cc.find_library('m')
# The notification server (org.freedesktop.Notifications) talks D-Bus through sd-bus.
sd_bus = dependency('libsystemd', required: false)
# GL composition; without these the shell renders with wl_shm only.
egl = dependency('egl', required: false)
glesv2 = dependency('glesv2', required: false)
wayland_egl = dependency('wayland-egl', required: false)
gl_found = egl.found() and glesv2.found() and wayland_egl.found()
gl_deps = gl_found ? [egl, glesv2, wayland_egl] : []

wayland_protocols_dir = wayland_protocols.get_variable(pkgconfig: 'pkgdatadir')
wlr_protocols_dir = wlr_protocols.get_variable(pkgconfig: 'pkgdatadir')

# Client bindings: name => [xml, also emit code?]
protocols = {
  'xdg-shell': join_paths(wayland_protocols_dir, 'stable/xdg-shell/xdg-shell.xml'),
  'ext-session-lock-v1': join_paths(wayland_protocols_dir, 'staging/ext-session-lock/ext-session-lock-v1.xml'),
  'text-input-unstable-v3': join_paths(wayland_protocols_dir, 'unstable/text-input/text-input-unstable-v3.xml'),
  'wlr-layer-shell-unstable-v1': join_paths(wlr_protocols_dir, 'unstable/wlr-layer-shell-unstable-v1.xml'),
  'shady-shell-v1': files('protocol/shady-shell-v1.xml'),
}
protocol_sources = {}
foreach name, xml : protocols
  # The shell has always included layer-shell's header without -client-.
  header = name == 'wlr-layer-shell-unstable-v1' ? name + '-protocol.h' : name + '-client-protocol.h'
  protocol_sources += { name: [
    custom_target(header, input: xml, output: header,
      command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@']),
    custom_target(name + '-protocol.c', input: xml, output: name + '-protocol.c',
      command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@']),
  ] }
endforeach
all_protocol_sources = []
foreach name, sources : protocol_sources
  all_protocol_sources += sources
endforeach

shell_data_install_dir = join_paths(get_option('datadir'), 'shady', 'shell')
shell_plugin_install_dir = join_paths(get_option('libdir'), 'shady', 'shell-plugins')
if get_option('installed_data')
  shell_data_dir = join_paths(get_option('prefix'), shell_data_install_dir)
else
  shell_data_dir = meson.project_source_root()
endif

executable('shady-shell',
  all_protocol_sources + [
    'src/main.c',
    'src/core.c',
    'src/render_gl.c',
    'src/render_shm.c',
    'src/theme.c',
    'src/apps.c',
    'src/ui.c',
    'src/anim.c',
    'src/notify.c',
    'src/script.c',
    'src/plugins.c',
    'src/compositor.c',
    'src/auth.c',
    'src/ipc/json.c',
  ],
  include_directories: include_directories('include', 'src'),
  c_args: [
    '-D_POSIX_C_SOURCE=200809L',
    '-DSHELL_HAS_GL=@0@'.format(gl_found ? 1 : 0),
    '-DHAVE_SD_BUS=@0@'.format(sd_bus.found() ? 1 : 0),
    '-DSHADY_SHELL_DATA_DIR="@0@"'.format(shell_data_dir),
    '-DSHADY_SHELL_PLUGIN_INSTALL_DIR="@0@"'.format(join_paths(get_option('prefix'), shell_plugin_install_dir)),
  # An installed shell must not load code from where it happened to be built.
  ] + (get_option('installed_data') ? [] : [
    '-DSHADY_SHELL_PLUGIN_DIR="@0@"'.format(meson.current_build_dir()),
  ]),
  dependencies: [wayland_client, cairo, pangocairo, pangoft2, fontconfig, xkbcommon, sd_bus, lua, dl, m] + gl_deps,
  install: true)

# Checks passwords for the lock screen (shell.authenticate) with PAM, out of
# the shell's process.
pam = cc.find_library('pam', required: get_option('pam'))
if pam.found()
  executable('shady-auth', 'src/auth_helper.c',
    c_args: ['-D_POSIX_C_SOURCE=200809L'],
    dependencies: [pam],
    install: true)
  # Next to shady-auth, where auth.c looks for the helper.
  shell_auth_test = executable('shell-auth-test',
    ['tests/shell-auth-test.c', 'src/auth.c',
     protocol_sources['ext-session-lock-v1'][0],
     protocol_sources['text-input-unstable-v3'][0],
     protocol_sources['wlr-layer-shell-unstable-v1'][0]],
    include_directories: include_directories('src'),
    c_args: ['-D_POSIX_C_SOURCE=200809L'],
    dependencies: [wayland_client, cairo, xkbcommon],
    install: false)
  test('shell-auth', shell_auth_test)
endif

# Native shell plugins (include/shady/shell_plugin.h).
shared_module('shady-shell-plugin-sysinfo',
  'plugins/sysinfo.c',
  include_directories: include_directories('include'),
  dependencies: [cairo],
  install: true,
  install_dir: shell_plugin_install_dir)

shared_module('shady-shell-plugin-probe',
  'tests/shell-plugin-probe.c',
  include_directories: include_directories('include'),
  dependencies: [cairo],
  install: false)

# Wayland clients the headless tests drive the compositor with.
test_protocols = {
  'input-method-unstable-v2': files('tests/protocols/input-method-unstable-v2.xml'),
  'virtual-keyboard-unstable-v1': files('tests/protocols/virtual-keyboard-unstable-v1.xml'),
}
test_protocol_sources = []
foreach name, xml : test_protocols
  test_protocol_sources += custom_target(name + '-client-protocol.h', input: xml,
    output: name + '-client-protocol.h',
    command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'])
  test_protocol_sources += custom_target(name + '-protocol.c', input: xml,
    output: name + '-protocol.c',
    command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'])
endforeach
executable('headless-automation-probe',
  protocol_sources['xdg-shell'] + ['tests/headless-automation-probe.c'],
  c_args: ['-D_POSIX_C_SOURCE=200809L'],
  dependencies: [wayland_client],
  build_by_default: false,
  install: false)
# A scripted input method for tests/headless-shell-ime.sh.
executable('ime-probe',
  test_protocol_sources + [protocol_sources['text-input-unstable-v3'][0], 'tests/ime-probe.c'],
  c_args: ['-D_POSIX_C_SOURCE=200809L'],
  dependencies: [wayland_client],
  build_by_default: false,
  install: false)

# The Lua UI and its data; the C sources stay behind.
install_data('default.lua', 'shortcut_overlay.lua', install_dir: shell_data_install_dir)
foreach dir : ['examples', 'fonts', 'shaders']
  install_subdir(dir, install_dir: shell_data_install_dir)
endforeach
install_data('bin/shady-brightness', install_dir: join_paths(shell_data_install_dir, 'bin'),
  install_mode: 'rwxr-xr-x')

# For shell plugins built elsewhere (the greeter's greetd plugin, rices'):
# the plugin ABI header, the protocol, and where plugins are installed.
install_headers('include/shady/shell_plugin.h', subdir: 'shady')
install_data('protocol/shady-shell-v1.xml',
  install_dir: join_paths(get_option('datadir'), 'shady', 'protocols'))
import('pkgconfig').generate(
  name: 'shady-shell',
  description: 'Shady shell plugin API and protocol',
  filebase: 'shady-shell',
  subdirs: [],
  variables: [
    'pluginsdir=${libdir}/shady/shell-plugins',
    'protocoldir=${datadir}/shady/protocols',
  ])
