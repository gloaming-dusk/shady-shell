#!/usr/bin/env bash
# Canvas widgets, radial gradients and soft shadows: shapes are drawn where
# they are put, in their own colours or the widget's, a view box scales, a
# blurred shadow falls off around its box, and a bad shape is an error the
# shell survives. Both renderers draw them alike.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_DIR="${SHADY_DAILY_BUILD_DIR:-build}"
for bin in shady shady-shell shadyctl; do
    [[ -x "$BUILD_DIR/$bin" ]] || { echo "shell-canvas: missing $BUILD_DIR/$bin" >&2; exit 2; }
done
command -v grim >/dev/null || { echo "shell-canvas: needs grim" >&2; exit 2; }

run() {
    local renderer="$1"
    local tmp
    tmp="$(mktemp -d)"
    mkdir -m 700 "$tmp/runtime"
    cp -r tests/shell-canvas "$tmp/config"
    local log="$tmp/log"
    (
        export XDG_RUNTIME_DIR="$tmp/runtime"
        unset WAYLAND_DISPLAY WAYLAND_SOCKET SHADY_SOCKET
        export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman
        export SHADY_LUA_INIT="$ROOT/tests/headless-shell-lua-init.lua"
        export SHADY_SHELL_BIN="$ROOT/$BUILD_DIR/shady-shell"
        export SHADY_SHELL_CONFIG="$tmp/config/shell.lua"
        export SHADY_SHELL_RENDERER="$renderer"
        export ASAN_OPTIONS="${ASAN_OPTIONS:-abort_on_error=1:halt_on_error=1:detect_leaks=0}"
        export UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}"
        exec "$BUILD_DIR/shady" --safe -c "$ROOT/tests/headless-automation-config.lua"
    ) >"$log" 2>&1 &
    local comp=$!
    fail() {
        echo "shell-canvas[$renderer]: $1" >&2
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
    pixel() { # pixel <x> <y> -> "r g b"
        XDG_RUNTIME_DIR="$tmp/runtime" WAYLAND_DISPLAY=wayland-0 \
            grim -g "$1,$2 1x1" -t ppm - | tail -c 3 | od -An -tu1 | xargs
    }
    expect_pixel() { # expect_pixel <x> <y> <r g b> <what>
        local got
        got="$(pixel "$1" "$2")"
        [[ "$got" == "$3" ]] || fail "$4: pixel ($1,$2) is '$got', expected '$3'"
    }
    red() { pixel "$1" "$2" | cut -d' ' -f1; }

    wait_for 1 "shady-shell: renderer $renderer"
    wait_for 1 "shady-shell: canvas-bar on HEADLESS-1"
    sleep 0.5

    expect_pixel 13 13 "255 0 0" "rect"
    expect_pixel 30 30 "0 0 255" "circle over the rect"
    expect_pixel 95 45 "0 255 0" "path in the widget's colour, scaled by the view"
    expect_pixel 65 15 "32 32 32" "outside the path"
    expect_pixel 260 30 "255 255 0" "line from a spliced list"
    expect_pixel 275 30 "255 0 255" "arc at 3 o'clock, over the line"
    expect_pixel 245 30 "255 255 0" "no arc at 9 o'clock"
    expect_pixel 260 45 "255 0 255" "arc at 6 o'clock"

    # Radial: bright in the middle, dark at the edge.
    local centre edge
    centre="$(red 130 30)"; edge="$(red 112 30)"
    (( centre > 230 && edge < 40 )) || fail "radial gradient: centre $centre, edge $edge"

    # Soft shadow: light next to the box, less further out, none past its reach.
    expect_pixel 210 30 "0 0 0" "shadowed box"
    local near far
    near="$(red 233 30)"; far="$(red 238 30)"
    (( near > far && far > 32 && near < 255 )) || fail "soft shadow falloff: $near then $far"
    expect_pixel 250 5 "32 32 32" "past the shadow"
    near="$(red 233 52)"
    (( near > 32 )) || fail "soft shadow corner: $near"

    # A shape the canvas does not know is the view's error; putting it right
    # brings the bar back.
    sed -i 's/{ "circle", 20, 20, 8, fill = "#0000ff" }/{ "blob", 1 }/' "$tmp/config/shell.lua"
    wait_for 1 "unknown canvas shape 'blob'"
    sed -i 's/{ "blob", 1 }/{ "circle", 20, 20, 8, fill = "#00ffff" }/' "$tmp/config/shell.lua"
    wait_for 2 "shady-shell: reloaded"
    sleep 0.5
    expect_pixel 30 30 "0 255 255" "the canvas after the error"

    XDG_RUNTIME_DIR="$tmp/runtime" "$BUILD_DIR/shadyctl" -s "$tmp/runtime/shady-wayland-0.sock" quit >/dev/null
    wait "$comp" || fail "compositor exited with an error"
    grep -Eq 'AddressSanitizer|runtime error:|UndefinedBehaviorSanitizer' "$log" && fail "sanitizer error"
    rm -rf "$tmp"
    echo "shell-canvas[$renderer]: PASS"
}

run gl
run shm
