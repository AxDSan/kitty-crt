#!/usr/bin/env bash
# Regenerate the README images with the real shader.
#
#   tools/shots.sh [monitors|afterglow|picker|hero|compare|all]
#
# It opens short-lived kitty-crt windows on your desktop (a few seconds each, about two minutes for
# `all`), captures the post-shader pixels with `kitten @ screenshot`, and composes the images into
# assets/. It only ever closes the windows it opened. Needs kitty-crt installed (./install.sh),
# python3 with Pillow, and for `hero` omp.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(dirname "$here")
kitty=${KITTY_CRT_BIN:-$HOME/.local/kitty.app/bin/kitty}
kitten=$(dirname "$kitty")/kitten
assets=$repo/assets
work=$(mktemp -d)
pid=
sock=
cd "$repo"

stop_window() {
    if [[ -n $pid ]]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        pid=
    fi
}
trap 'stop_window; rm -rf "$work"' EXIT

# adopt_window: wait for the kitty we just started (in $pid) to listen, then size it and let it settle
adopt_window() {
    for _ in $(seq 1 200); do
        [[ -S $work/sock-$pid ]] && break
        sleep 0.3
    done
    [[ -S $work/sock-$pid ]] || { echo "shots.sh: the window did not start" >&2; exit 1; }
    sock=unix:$work/sock-$pid
    "$kitten" @ --to "$sock" resize-os-window --width 1600 --height 1000 --unit pixels >/dev/null 2>&1 || true
    sleep "${SETTLE:-3}"
}

# open_window NAME COMMAND...: a kitty-crt window with remote control on a private socket
open_window() {
    stop_window
    local name=$1
    shift
    "$repo/bin/kitty-crt" -o allow_remote_control=socket -o "listen_on=unix:$work/sock" --title "crt-shots-$name" "$@" >/dev/null 2>&1 &
    pid=$!
    adopt_window
}

shoot() { "$kitten" @ --to "$sock" screenshot "$work/$1.png" >/dev/null; }
monitor() { "$kitten" @ --to "$sock" set-colors --all --configured "background=$("$repo/bin/crt" code "$1")"; }

do_monitors() {
    open_window ui python3 "$here/patterns/ui.py"
    local name
    for name in amber green white ice color; do
        monitor "$name"
        sleep 0.8
        shoot "$name"
    done
    python3 "$here/compose.py" monitors "$assets/monitors.png" "$work"/{amber,green,white,ice,color}.png
}

do_afterglow() {
    open_window sweep python3 "$here/patterns/sweep.py"
    shoot afterglow
    python3 "$here/compose.py" crop-box "$assets/afterglow.png" "$work/afterglow.png" 0 0 1300 560
}

do_picker() {
    open_window ui python3 "$here/patterns/ui.py"
    "$kitten" @ --to "$sock" launch --type=overlay --title pick env -u KITTY_LISTEN_ON "$repo/bin/crt" pick >/dev/null
    sleep 2
    "$kitten" @ --to "$sock" send-text --match title:pick j
    sleep 0.8
    shoot picker
    python3 "$here/compose.py" crop-box "$assets/picker.png" "$work/picker.png" 0 0 1060 560
}

do_hero() {
    command -v omp >/dev/null || { echo "shots.sh: omp is not installed, skipping the hero image"; return 0; }
    # shellcheck disable=SC2016 # the inner shell expands $SHELL, not this script
    SETTLE=${HERO_SETTLE:-16} open_window omp "${SHELL:-/bin/sh}" -ic 'omp; exec "$SHELL"'
    shoot hero
    # the top of the screen: omp's welcome box. Below it omp prints notices that depend on your setup.
    python3 "$here/compose.py" crop-box "$assets/hero.png" "$work/hero.png" 0 0 1300 600
}

do_compare() {
    open_window ui python3 "$here/patterns/ui.py"
    shoot crt
    stop_window
    UI_DELAY=8 "$kitty" --config NONE -o background_opacity=1 -o window_padding_width=14 -o remember_window_size=no \
        -o allow_remote_control=socket -o "listen_on=unix:$work/sock" --title crt-shots-plain \
        python3 "$here/patterns/ui.py" >/dev/null 2>&1 &
    pid=$!
    SETTLE=9 adopt_window
    shoot plain
    python3 "$here/compose.py" compare "$assets/compare.png" "$work/plain.png" "$work/crt.png"
}

what=${1:-all}
mkdir -p "$assets"
case $what in
monitors | afterglow | picker | hero | compare) "do_$what" ;;
all) do_monitors && do_afterglow && do_picker && do_hero && do_compare ;;
*) echo "usage: tools/shots.sh [monitors|afterglow|picker|hero|compare|all]" >&2; exit 2 ;;
esac
echo "images written to $assets"
