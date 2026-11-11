#!/usr/bin/env bash
# The wallpaper manager (wallpaper.lua): a rice's default is drawn until a
# picture is dropped in ~/.config/shady; shady-wallpaper's choice beats both,
# survives a restart of the config, and a folder is a slideshow that `next`
# moves on. PNG, JPEG and WebP all decode; `fit = "contain"` letterboxes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_DIR="${SHADY_DAILY_BUILD_DIR:-build}"
for bin in shady shady-shell shadyctl; do
    [[ -x "$BUILD_DIR/$bin" ]] || { echo "shell-wallpaper: missing $BUILD_DIR/$bin" >&2; exit 2; }
done
for tool in grim cjpeg cwebp; do
    command -v "$tool" >/dev/null || { echo "shell-wallpaper: needs $tool" >&2; exit 2; }
done

# A solid w x h picture: ppm <w> <h> <r> <g> <b>
ppm() {
    LC_ALL=C awk -v w="$1" -v h="$2" -v r="$3" -v g="$4" -v b="$5" \
        'BEGIN { printf "P6\n%d %d\n255\n", w, h; for (i = 0; i < w * h; i++) printf "%c%c%c", r, g, b }'
}

run() {
    local renderer="$1"
    local tmp
    tmp="$(mktemp -d)"
    mkdir -m 700 "$tmp/runtime"
    cp -r tests/shell-wallpaper "$tmp/config"
    mkdir -p "$tmp/xdg/shady" "$tmp/pictures/folder"
    # The pictures; a PNG is taken from the screen with grim further on.
    ppm 64 64 255 0 0 > "$tmp/red.ppm"
    ppm 64 64 0 255 0 > "$tmp/green.ppm"
    ppm 64 64 0 0 255 > "$tmp/blue.ppm"
    ppm 64 64 255 255 0 > "$tmp/yellow.ppm"
    ppm 200 100 255 0 255 > "$tmp/wide.ppm"
    cjpeg -quality 100 "$tmp/red.ppm" > "$tmp/pictures/red.jpg"
    cwebp -quiet -lossless "$tmp/green.ppm" -o "$tmp/pictures/green.webp"
    cwebp -quiet -lossless "$tmp/blue.ppm" -o "$tmp/pictures/folder/1-blue.webp"
    cjpeg -quality 100 "$tmp/yellow.ppm" > "$tmp/pictures/folder/2-yellow.jpg"
    cwebp -quiet -lossless "$tmp/wide.ppm" -o "$tmp/pictures/wide.webp"
    echo "not a picture" > "$tmp/pictures/folder/3-broken.jpg"
    local log="$tmp/log"
    (
        export XDG_RUNTIME_DIR="$tmp/runtime"
        export XDG_CONFIG_HOME="$tmp/xdg" XDG_STATE_HOME="$tmp/state"
        unset WAYLAND_DISPLAY WAYLAND_SOCKET SHADY_SOCKET
        export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman
        export SHADY_LUA_INIT="$ROOT/tests/headless-shell-wallpaper-init.lua"
        export SHADY_SHELL_BIN="$ROOT/$BUILD_DIR/shady-shell"
        export SHADY_SHELL_CONFIG="$tmp/config/shell.lua"
        export SHADY_SHELL_DATA_DIR="$ROOT"
        export SHADY_SHELL_RENDERER="$renderer"
        export ASAN_OPTIONS="${ASAN_OPTIONS:-abort_on_error=1:halt_on_error=1:detect_leaks=0}"
        export UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}"
        exec "$BUILD_DIR/shady" --safe -c "$ROOT/tests/headless-automation-config.lua"
    ) >"$log" 2>&1 &
    local comp=$!
    fail() {
        echo "shell-wallpaper[$renderer]: $1" >&2
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
    # Close to a colour (JPEG is not exact): near <x> <y> <r g b> <what>,
    # retried while the shell catches up with the change.
    near() {
        local got want=($3)
        for _ in $(seq 1 100); do
            got=($(pixel "$1" "$2"))
            local ok=1
            for i in 0 1 2; do
                (( got[i] - want[i] <= 6 && want[i] - got[i] <= 6 )) || ok=0
            done
            (( ok )) && return 0
            sleep 0.05
        done
        fail "$4: pixel ($1,$2) is '${got[*]}', expected about '$3'"
    }
    cli() { XDG_STATE_HOME="$tmp/state" bin/shady-wallpaper "$@"; }

    wait_for 1 "shady-shell: renderer $renderer"
    wait_for 1 "shady-shell: test-wallpaper on HEADLESS-1"

    near 300 300 "16 32 48" "the rice's default"

    # A picture dropped in the config directory replaces it, and taking it
    # away brings the rice's back.
    cp "$tmp/pictures/red.jpg" "$tmp/xdg/shady/wallpaper.jpg"
    near 300 300 "255 0 0" "a dropped JPEG"
    near 5 5 "255 0 0" "a dropped JPEG, covering the output"
    XDG_RUNTIME_DIR="$tmp/runtime" WAYLAND_DISPLAY=wayland-0 grim -g "0,0 64x64" "$tmp/pictures/red.png"

    # shady-wallpaper beats the dropped file and is kept in the state file.
    cli set "$tmp/pictures/green.webp"
    near 300 300 "0 255 0" "a WebP set with shady-wallpaper"
    grep -q "^\* $tmp/pictures/green.webp\$" "$tmp/state/shady/wallpaper" || fail "state file: $(cat "$tmp/state/shady/wallpaper")"

    # A folder is a slideshow: the first picture by name, then `next`. The
    # broken file is skipped on the way round.
    cli set "$tmp/pictures/folder"
    near 300 300 "0 0 255" "the folder's first picture"
    cli next
    near 300 300 "255 255 0" "the folder's next picture"
    cli next
    near 300 300 "0 0 255" "round the folder, past the broken file"
    wait_for 1 "3-broken.jpg: not a picture this shell can read"

    # A choice survives the config being loaded again.
    cli set "$tmp/pictures/green.webp"
    near 300 300 "0 255 0" "set again"
    echo "-- reload" >> "$tmp/config/shell.lua"
    wait_for 1 "shady-shell: reloaded"
    near 300 300 "0 255 0" "the choice after a reload"

    # Clearing goes back to the dropped file, removing that to the rice's.
    cli clear
    near 300 300 "255 0 0" "cleared: the dropped file again"
    rm "$tmp/xdg/shady/wallpaper.jpg"
    near 300 300 "16 32 48" "no file: the rice's default"

    # A config's own source beats a dropped file; contain letterboxes a 2:1
    # picture on the colour.
    cp "$tmp/pictures/red.png" "$tmp/xdg/shady/wallpaper.png"
    near 300 300 "255 0 0" "a dropped PNG"
    sed -i "s|^-- SOURCE.*|wallpaper.install { source = { path = '$tmp/pictures/wide.webp', fit = 'contain' }, color = '#000000' }|" \
        "$tmp/config/shell.lua"
    wait_for 2 "shady-shell: reloaded"
    local size
    size="$(grep -oE 'test-wallpaper size [0-9]+x[0-9]+' "$log" | tail -n1 | grep -oE '[0-9]+x[0-9]+')"
    local width="${size%x*}" height="${size#*x}"
    near $(( width / 2 )) $(( height / 2 )) "255 0 255" "contain: the picture in the middle"
    if (( width * 100 / height < 200 )); then
        near $(( width / 2 )) 2 "0 0 0" "contain: the bar above it"
    else
        near 2 $(( height / 2 )) "0 0 0" "contain: the bar beside it"
    fi

    # What rices draw themselves: a view, and a shader (its colour under it
    # is what the shm renderer shows).
    rm "$tmp/xdg/shady/wallpaper.png"
    sed -i "s|^wallpaper.install { source = .*|wallpaper.install { source = false, color = false, default = function(ctx) return shell.box { width = ctx.width, height = ctx.height, background = '#00ffff' } end }|" \
        "$tmp/config/shell.lua"
    wait_for 3 "shady-shell: reloaded"
    near 300 300 "0 255 255" "a view as the rice's wallpaper"
    sed -i "s|default = function.*|default = { shader = shell.shader('tint.frag'), uniforms = { color = '#ff8000' }, color = '#4000ff' } }|" \
        "$tmp/config/shell.lua"
    wait_for 4 "shady-shell: reloaded"
    if [[ "$renderer" == gl ]]; then
        near 300 300 "255 128 0" "a shader as the rice's wallpaper"
    else
        near 300 300 "64 0 255" "a shader's colour, without GL"
    fi

    XDG_RUNTIME_DIR="$tmp/runtime" "$BUILD_DIR/shadyctl" -s "$tmp/runtime/shady-wayland-0.sock" quit >/dev/null
    wait "$comp" || fail "compositor exited with an error"
    grep -Eq 'AddressSanitizer|runtime error:|UndefinedBehaviorSanitizer' "$log" && fail "sanitizer error"
    rm -rf "$tmp"
    echo "shell-wallpaper[$renderer]: PASS"
}

run gl
run shm
