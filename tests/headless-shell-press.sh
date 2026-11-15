#!/usr/bin/env bash
# What springy, sticker-like UIs are built from: a widget's `press` style
# shows while the left button holds it down and goes when it is let go;
# text takes an `outline` and a glyph-shaped `text_shadow`; and shell.apps
# gives the PNG an application's Icon= names from the hicolor theme. A
# drag released outside the surface ends there: the release goes elsewhere,
# and the drag must not follow the pointer when it comes back.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_DIR="${SHADY_DAILY_BUILD_DIR:-build}"
for bin in shady shady-shell shadyctl; do
    [[ -x "$BUILD_DIR/$bin" ]] || { echo "shell-press: missing $BUILD_DIR/$bin" >&2; exit 2; }
done
command -v grim >/dev/null || { echo "shell-press: needs grim" >&2; exit 2; }

tmp="$(mktemp -d)"
mkdir -m 700 "$tmp/runtime"
cp -r tests/shell-press "$tmp/config"
# An application with an icon in the hicolor theme of its own data dir.
data="$tmp/data"
mkdir -p "$data/applications" "$data/icons/hicolor/64x64/apps"
printf '[Desktop Entry]\nType=Application\nName=Press Probe\nExec=true\nIcon=press-probe\n' \
    >"$data/applications/press-probe.desktop"
# A 1x1 PNG.
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x03\x01\x01\x00\xc9\xfe\x92\xef\x00\x00\x00\x00IEND\xaeB`\x82' \
    >"$data/icons/hicolor/64x64/apps/press-probe.png"
log="$tmp/log"
(
    export XDG_RUNTIME_DIR="$tmp/runtime"
    unset WAYLAND_DISPLAY WAYLAND_SOCKET SHADY_SOCKET
    export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman
    export XDG_DATA_HOME="$data" XDG_DATA_DIRS="$tmp/none"
    export SHADY_LUA_INIT="$ROOT/tests/headless-shell-lua-init.lua"
    export SHADY_SHELL_BIN="$ROOT/$BUILD_DIR/shady-shell"
    export SHADY_SHELL_CONFIG="$tmp/config/shell.lua"
    export ASAN_OPTIONS="${ASAN_OPTIONS:-abort_on_error=1:halt_on_error=1:detect_leaks=0}"
    export UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}"
    exec "$BUILD_DIR/shady" --safe -c "$ROOT/tests/headless-automation-config.lua"
) >"$log" 2>&1 &
comp=$!
fail() {
    echo "shell-press: $1" >&2
    cat "$log" >&2
    kill "$comp" 2>/dev/null || true
    rm -rf "$tmp"
    exit 1
}
wait_for() { # wait_for <count> <pattern>
    for _ in $(seq 1 300); do
        (( $(grep -c -- "$2" "$log" || true) >= $1 )) && return 0
        kill -0 "$comp" 2>/dev/null || fail "compositor exited waiting for '$2'"
        sleep 0.02
    done
    fail "timed out waiting for $1x '$2'"
}
ctl() { XDG_RUNTIME_DIR="$tmp/runtime" "$BUILD_DIR/shadyctl" -s "$tmp/runtime/shady-wayland-0.sock" "$@" >/dev/null; }
pixel() { # pixel <x> <y> -> "r g b"
    XDG_RUNTIME_DIR="$tmp/runtime" WAYLAND_DISPLAY=wayland-0 \
        grim -g "$1,$2 1x1" -t ppm - | tail -c 3 | od -An -tu1 | xargs
}
expect_pixel() { # expect_pixel <x> <y> <r g b> <what>
    local got
    got="$(pixel "$1" "$2")"
    [[ "$got" == "$3" ]] || fail "$4: pixel ($1,$2) is '$got', expected '$3'"
}
count() { # count <r g b> in the strip x0..x1 at row y
    local n=0 x
    for x in $(seq "$1" "$2"); do [[ "$(pixel "$x" "$3")" == "$4" ]] && n=$((n + 1)); done
    echo "$n"
}

wait_for 1 "shady-shell: press-bar on HEADLESS-1"
wait_for 1 "icon=$data/icons/hicolor/64x64/apps/press-probe.png"
sleep 0.5

expect_pixel 30 30 "255 0 0" "the key before it is pressed"
ctl lua 'shady.automation.move_pointer(30, 30) shady.automation.button_down("left")'
sleep 0.4
expect_pixel 30 30 "0 255 0" "the key while it is held"
ctl lua 'shady.automation.button_up("left")'
sleep 0.4
expect_pixel 30 30 "255 0 0" "the key once it is let go"

# The letter: blue outline and yellow shadow somewhere across its row.
blue="$(count 205 260 30 "0 0 255")"
yellow="$(count 205 260 46 "255 255 0")"
(( blue > 0 )) || fail "no outline around the letter"
(( yellow > 0 )) || fail "no shadow under the letter"

# The slider (the box after the key) is dragged off the bar and let go
# there; moving back over it must not drag it any more.
ctl lua 'shady.automation.drag(130, 30, 130, 400)'
wait_for 1 "drag=[0-9]* done"
sleep 0.3
before="$(grep -c 'drag=' "$log")"
ctl lua 'shady.automation.move_pointer(120, 30)'
sleep 0.2
ctl lua 'shady.automation.move_pointer(160, 32)'
sleep 0.3
after="$(grep -c 'drag=' "$log")"
(( after == before )) || fail "the drag followed the pointer after it was let go outside ($before -> $after)"

ctl quit
wait "$comp" || fail "compositor exited with an error"
grep -Eq 'AddressSanitizer|runtime error:|UndefinedBehaviorSanitizer' "$log" && fail "sanitizer error"
rm -rf "$tmp"
echo "shell-press: PASS"
