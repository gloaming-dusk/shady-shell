{
  lib,
  stdenv,
  meson,
  ninja,
  pkg-config,
  wayland-scanner,
  wayland,
  wayland-protocols,
  wlr-protocols,
  libxkbcommon,
  libGL,
  lua5_4,
  cairo,
  pango,
  fontconfig,
  systemd,
  linux-pam,
}:

stdenv.mkDerivation {
  pname = "shady-shell";
  version = "0.2.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../meson.build
      ../meson_options.txt
      ../default.lua
      ../shortcut_overlay.lua
      ../bin
      ../examples
      ../include
      ../plugins
      ../protocol
      ../shaders
      ../src
      ../tests
    ];
  };

  strictDeps = true;
  depsBuildBuild = [ pkg-config ];
  nativeBuildInputs = [ meson ninja pkg-config wayland-scanner ];
  buildInputs = [
    wayland wayland-protocols wlr-protocols libxkbcommon libGL lua5_4
    cairo pango fontconfig systemd linux-pam
  ];

  mesonBuildType = "release";
  mesonFlags = [
    (lib.mesonBool "installed_data" true)
    (lib.mesonEnable "pam" true)
  ];

  doCheck = true;

  meta = {
    description = "Lua-scripted layer-shell desktop shell for the Shady compositor";
    homepage = "https://github.com/gloaming-dusk/shady-shell";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "shady-shell";
  };
}
