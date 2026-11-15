#!/usr/bin/env bash
# The clipboard without wl-copy: what the shell copies, wl-paste reads (text
# and a PNG); what wl-copy copies, the shell sees (text and a PNG, the
# picture kept in the cache) and keeps in its history; a copy marked as a
# password manager's secret is not read. Also shell.image_crop, and a
# statefile that another process rewrites (statefile.watch).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_DIR="${SHADY_DAILY_BUILD_DIR:-build}"
for bin in shady shady-shell shadyctl; do
    [[ -x "$BUILD_DIR/$bin" ]] || { echo "shell-clipboard: missing $BUILD_DIR/$bin" >&2; exit 2; }
done
for tool in wl-copy wl-paste; do
    command -v "$tool" >/dev/null || { echo "shell-clipboard: needs $tool" >&2; exit 2; }
done

tmp="$(mktemp -d)"
mkdir -m 700 "$tmp/runtime"
log="$tmp/log"
# A 16x12 PNG to copy and crop.
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAIAAADkharWAAAAFUlEQVR4nGM4UaFBEmIY1TCqATsCAKB2DhCmYTq1AAAAAElFTkSuQmCC' \
    | base64 -d > "$tmp/pic.png"
(
    export XDG_RUNTIME_DIR="$tmp/runtime" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"
    unset WAYLAND_DISPLAY WAYLAND_SOCKET SHADY_SOCKET
    export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman
    export SHADY_LUA_INIT="$ROOT/tests/headless-shell-lua-init.lua"
    export SHADY_SHELL_BIN="$ROOT/$BUILD_DIR/shady-shell"
    export SHADY_SHELL_CONFIG="$ROOT/tests/shell-clipboard/shell.lua"
    export CLIP_TEST_PNG="$tmp/pic.png"
    export ASAN_OPTIONS="${ASAN_OPTIONS:-abort_on_error=1:halt_on_error=1:detect_leaks=0}"
    exec "$BUILD_DIR/shady" --safe -c "$ROOT/tests/headless-automation-config.lua"
) >"$log" 2>&1 &
comp=$!
fail() {
    echo "shell-clipboard: $1" >&2
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
wl() { XDG_RUNTIME_DIR="$tmp/runtime" WAYLAND_DISPLAY=wayland-0 "$@"; }
ctl() { XDG_RUNTIME_DIR="$tmp/runtime" "$BUILD_DIR/shadyctl" -s "$tmp/runtime/shady-wayland-0.sock" "$@"; }
n=0
send() { n=$((n + 1)); ctl lua "shady.publish('test', '$n $1')" >/dev/null; }

wait_for 1 "shady-shell: clipboard-bar on HEADLESS-1"
sleep 2.2 # past the values replayed on connect

# The shell copies; another client pastes.
send copy-text
wait_for 1 "SET true"
got="$(wl timeout 3 wl-paste -n)"
[[ "$got" == "from the shell 한글" ]] || fail "wl-paste read '$got'"

# Another client copies; the shell sees it.
printf 'copied elsewhere' | wl timeout 3 wl-copy
wait_for 1 "CLIP text copied elsewhere"
wl timeout 3 wl-copy --type image/png < "$tmp/pic.png"
wait_for 1 "CLIP image 16x12"
ls "$tmp/cache/shady/clipboard/"*.png >/dev/null 2>&1 || fail "the picture was not kept in the cache"
printf 'hunter2' | wl timeout 3 wl-copy --type x-kde-passwordManagerHint
sleep 0.5
grep -q "hunter2" "$log" && fail "a secret was read"
send history
wait_for 1 "HISTORY 3 image"
grep -q 'copied elsewhere' "$tmp/state/shady/clipboard.lua" || fail "the history was not saved"

# The shell copies a picture; another client pastes it.
send copy-image
wait_for 1 "SETIMG true"
wl timeout 3 wl-paste --type image/png > "$tmp/pasted.png"
cmp -s "$tmp/pic.png" "$tmp/pasted.png" || fail "the pasted picture differs"

# A part of a picture.
send crop
wait_for 1 "CROP true 10x7"

# Another process rewrites a statefile; the shell notices.
mkdir -p "$tmp/state/shady"
printf 'pins=Foot\tGVim\n' > "$tmp/state/shady/dock.new"
mv "$tmp/state/shady/dock.new" "$tmp/state/shady/dock"
wait_for 1 "PINS Foot	GVim"

ctl quit >/dev/null
wait "$comp" || fail "compositor exited with an error"
grep -Eq 'AddressSanitizer|runtime error:|UndefinedBehaviorSanitizer' "$log" && fail "sanitizer error"
rm -rf "$tmp"
echo "shell-clipboard: PASS"
