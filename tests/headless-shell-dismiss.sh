#!/usr/bin/env bash
# close_on_blur without the keyboard: a popup closes when the desktop (a
# background layer surface) is clicked and when another window takes the
# focus, and stays open when a bar is clicked.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_DIR="${SHADY_DAILY_BUILD_DIR:-build}"
SHADY_BIN_DIR="${SHADY_BIN_DIR:-$BUILD_DIR}"
for bin in shady shady-shell shadyctl; do
    [[ -x "$BUILD_DIR/$bin" ]] || { echo "shell-dismiss: missing $BUILD_DIR/$bin" >&2; exit 2; }
done
probe="$SHADY_BIN_DIR/headless-automation-probe"
[[ -x "$probe" ]] || probe="$BUILD_DIR/headless-automation-probe"
[[ -x "$probe" ]] || { echo "shell-dismiss: no headless-automation-probe" >&2; exit 2; }

tmp="$(mktemp -d)"
mkdir -m 700 "$tmp/runtime"
log="$tmp/log"
(
    export XDG_RUNTIME_DIR="$tmp/runtime" XDG_STATE_HOME="$tmp/state"
    unset WAYLAND_DISPLAY WAYLAND_SOCKET SHADY_SOCKET
    export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman
    export SHADY_LUA_INIT="$ROOT/tests/shell-dismiss/init.lua"
    export SHADY_SHELL_BIN="$ROOT/$BUILD_DIR/shady-shell"
    export SHADY_SHELL_CONFIG="$ROOT/tests/shell-dismiss/shell.lua"
    export SHADY_AUTOMATION_PROBE="$(readlink -f "$probe")"
    export ASAN_OPTIONS="${ASAN_OPTIONS:-abort_on_error=1:halt_on_error=1:detect_leaks=0}"
    exec "$BUILD_DIR/shady" --safe -c "$ROOT/tests/headless-automation-config.lua"
) >"$log" 2>&1 &
comp=$!
fail() {
    echo "shell-dismiss: $1" >&2
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
n=0
send() { n=$((n + 1)); ctl lua "shady.publish('test', '$n $1')"; }
click() { ctl lua "shady.automation.move_pointer($1, $2)"; sleep 0.15; ctl lua 'shady.automation.click("left")'; sleep 0.3; }

wait_for 1 "shady-shell: dismiss-bar on HEADLESS-1"
sleep 2.4 # the windows mapped, and past the values replayed on connect

# A click on a bar leaves it open.
send open
sleep 0.3
click 20 15
send check
wait_for 1 "PANEL open"

# The desktop: the wallpaper where no window is (the windows tile in the
# middle; the bottom left corner is desktop).
click 5 700
send check
wait_for 1 "PANEL closed"

# Another window taking the focus.
send open
sleep 0.3
send check
wait_for 2 "PANEL open"
send "focus dismiss-a"
sleep 0.3
send "focus dismiss-b"
sleep 0.4
send check
wait_for 2 "PANEL closed"

ctl quit
wait "$comp" || fail "compositor exited with an error"
grep -Eq 'AddressSanitizer|runtime error:|UndefinedBehaviorSanitizer' "$log" && fail "sanitizer error"
rm -rf "$tmp"
echo "shell-dismiss: PASS"
