#!/usr/bin/env bash
# shell.popup{close_on_blur = true}: the popup closes when a window takes the
# keyboard from it, and a popup without it stays open.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_DIR="${SHADY_DAILY_BUILD_DIR:-build}"
for bin in shady shady-shell shadyctl headless-automation-probe ime-probe; do
    [[ -x "$BUILD_DIR/$bin" ]] || { echo "shell-blur: missing $BUILD_DIR/$bin" >&2; exit 2; }
done

tmp="$(mktemp -d)"
mkdir -m 700 "$tmp/runtime"
log="$tmp/log"
config="$tmp/shell.lua"
cat >"$config" <<LUA
local go = "$tmp/go"
LUA
cat >>"$config" <<'LUA'
local seen, started = {}, false
local function watch()
    -- Opened once the test has a keyboard: without one there is no focus.
    if not started and io.open(go) then started = true; shell.open("blur") end
    for _, name in ipairs({ "blur", "keep" }) do
        local state = shell.is_open(name) and "open" or "closed"
        if seen[name] ~= state then
            -- The next step, once blur has closed: a popup that ignores
            -- losing the keyboard.
            if name == "blur" and seen.blur == "open" then shell.open("keep") end
            seen[name] = state
            shell.log(name .. "=" .. state)
        end
    end
    shell.after(30, watch)
end
shell.bar { name = "test-bar", size = 30, view = function() return shell.text("bar") end }
for _, name in ipairs({ "blur", "keep" }) do
    shell.popup {
        name = name, anchor = { "top", "left" }, margin = { top = 40, left = 10 },
        width = 120, height = 60, keyboard = "on_demand", close_on_blur = name == "blur",
        view = function() return shell.text(name) end,
    }
end
watch()
LUA

(
    export XDG_RUNTIME_DIR="$tmp/runtime"
    unset WAYLAND_DISPLAY WAYLAND_SOCKET SHADY_SOCKET
    export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman
    export SHADY_LUA_INIT="$ROOT/tests/headless-shell-blur-init.lua"
    export SHADY_SHELL_BIN="$ROOT/$BUILD_DIR/shady-shell"
    export SHADY_SHELL_CONFIG="$config"
    export ASAN_OPTIONS="${ASAN_OPTIONS:-abort_on_error=1:halt_on_error=1:detect_leaks=0}"
    export UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}"
    exec "$BUILD_DIR/shady" --safe -c "$ROOT/tests/headless-automation-config.lua"
) >"$log" 2>&1 &
comp=$!
probes=()
cleanup() {
    kill "$comp" "${probes[@]}" 2>/dev/null || true
    wait "$comp" 2>/dev/null || true
    rm -rf "$tmp"
}
trap cleanup EXIT
fail() { echo "shell-blur: $1" >&2; cat "$log" >&2; exit 1; }
wait_for() { # wait_for <count> <pattern>
    for _ in $(seq 1 300); do
        (( $(grep -c -- "$2" "$log" || true) >= $1 )) && return 0
        kill -0 "$comp" 2>/dev/null || fail "compositor exited waiting for '$2'"
        sleep 0.02
    done
    fail "timed out waiting for $1x '$2'"
}
probe() { # probe <app id>: a window, which takes the keyboard when it maps
    XDG_RUNTIME_DIR="$tmp/runtime" WAYLAND_DISPLAY=wayland-0 SHADY_AUTOMATION_PROBE_APP_ID="$1" \
        "$BUILD_DIR/headless-automation-probe" >>"$tmp/probe.log" 2>&1 &
    probes+=($!)
}

wait_for 1 "shady-shell: test-bar on HEADLESS-1"
# Headless outputs come without a keyboard; this probe brings a virtual one.
XDG_RUNTIME_DIR="$tmp/runtime" WAYLAND_DISPLAY=wayland-0 IME_PROBE_KEYBOARD=1 \
    "$BUILD_DIR/ime-probe" >"$tmp/ime.log" 2>&1 &
probes+=($!)
for _ in $(seq 1 100); do grep -q "ime: keyboard" "$tmp/ime.log" && break; sleep 0.02; done
grep -q "ime: keyboard" "$tmp/ime.log" || fail "no virtual keyboard: $(cat "$tmp/ime.log")"
sleep 0.2
: >"$tmp/go"
wait_for 1 "lua: blur=open"
sleep 0.2
(( $(grep -c "lua: blur=closed" "$log") == 1 )) || fail "the popup closed before anything took the keyboard"

probe shell-blur-a
wait_for 1 "shell-blur: mapped shell-blur-a"
wait_for 1 "lua: blur=closed"
wait_for 1 "lua: keep=open"

sleep 0.2
probe shell-blur-b
wait_for 1 "shell-blur: mapped shell-blur-b"
sleep 0.3
(( $(grep -c "lua: keep=closed" "$log") == 1 )) ||
    fail "a popup without close_on_blur closed when it lost the keyboard"

XDG_RUNTIME_DIR="$tmp/runtime" "$BUILD_DIR/shadyctl" -s "$tmp/runtime/shady-wayland-0.sock" quit >/dev/null
wait "$comp" || fail "compositor exited with an error"
grep -q "shell-blur: timed out" "$log" && fail "timed out"
grep -Eq 'AddressSanitizer|runtime error:|UndefinedBehaviorSanitizer' "$log" && fail "sanitizer error"
echo "shell-blur: PASS"
