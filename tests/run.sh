#!/usr/bin/env bash
# Runs the headless shell tests against a Shady compositor. shady-shell is
# built here; shady and shadyctl come from $SHADY_BIN_DIR, or PATH (the dev
# shell has Shady on it). Each test is run with a build directory that holds
# both, as the tests expect.
#
#   tests/run.sh                 every test
#   tests/run.sh shell-notify    the ones named (tests/headless-<name>.sh)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Run from inside a session, these name its compositor: a test's shadyctl or
# client would reach it (and `shadyctl quit` would end the session).
unset SHADY_SOCKET WAYLAND_DISPLAY WAYLAND_SOCKET
BUILD_DIR="${SHADY_SHELL_BUILD_DIR:-build}"
[[ -d "$BUILD_DIR" ]] || meson setup "$BUILD_DIR" >/dev/null
ninja -C "$BUILD_DIR" >/dev/null
ninja -C "$BUILD_DIR" ime-probe headless-automation-probe >/dev/null
for bin in shady shadyctl; do
    if [[ -n "${SHADY_BIN_DIR:-}" ]]; then
        path="$SHADY_BIN_DIR/$bin"
    else
        path="$(command -v "$bin" || true)"
    fi
    [[ -x "$path" ]] || { echo "run: no $bin (set SHADY_BIN_DIR, or put Shady on PATH)" >&2; exit 2; }
    ln -sf "$(readlink -f "$path")" "$BUILD_DIR/$bin"
done

if [[ $# -gt 0 ]]; then
    tests=()
    for name in "$@"; do tests+=("tests/headless-$name.sh"); done
else
    tests=(tests/headless-shell-*.sh)
fi
failed=()
for test in "${tests[@]}"; do
    printf '%-40s ' "$(basename "$test" .sh)"
    if out="$(SHADY_DAILY_BUILD_DIR="$BUILD_DIR" SHADY_SPATIAL_TEST_BUILD_DIR="$BUILD_DIR" \
            bash "$test" 2>&1)"; then
        echo ok
    else
        echo FAIL
        printf '%s\n' "$out" | tail -20 | sed 's/^/    /'
        failed+=("$test")
    fi
done
[[ ${#failed[@]} -eq 0 ]] || { echo "${#failed[@]} failed: ${failed[*]}" >&2; exit 1; }
