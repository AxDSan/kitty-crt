#!/usr/bin/env bash
# Install kitty-crt: shaders and config into your kitty config dir, commands into ~/.local/bin,
# a launcher entry into ~/.local/share/applications.
#
#   ./install.sh                copy the files (re-run after `git pull` to update)
#   ./install.sh --dev          symlink instead of copying, so edits in this repo take effect at once
#   ./install.sh --uninstall    remove what this script installed (files you modified are left alone)
#
# Options: --prefix DIR (commands go to DIR/bin, default ~/.local)   --config-dir DIR (default
# $KITTY_CONFIG_DIRECTORY or ~/.config/kitty)   --apps-dir DIR   --kitty PATH (default
# ~/.local/kitty.app/bin/kitty)   --install-kitty (fetch kitty with its official installer if missing)
# --no-prewarm (skip the one-off shader build that makes the first launch fast)
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
prefix=$HOME/.local
config_dir=${KITTY_CONFIG_DIRECTORY:-$HOME/.config/kitty}
apps_dir=${XDG_DATA_HOME:-$HOME/.local/share}/applications
kitty=${KITTY_CRT_BIN:-$HOME/.local/kitty.app/bin/kitty}
mode="copy" action="install" prewarm=1 install_kitty=0

usage() { sed -n '2,/^set -e/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }

while (($#)); do
    case $1 in
    --dev) mode="link" ;;
    --uninstall) action=uninstall ;;
    --prefix) prefix=${2:?--prefix needs a directory}; shift ;;
    --config-dir) config_dir=${2:?--config-dir needs a directory}; shift ;;
    --apps-dir) apps_dir=${2:?--apps-dir needs a directory}; shift ;;
    --kitty) kitty=${2:?--kitty needs a path}; shift ;;
    --install-kitty) install_kitty=1 ;;
    --no-prewarm) prewarm=0 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "install.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

bin_dir=$prefix/bin
icon=$(dirname "$(dirname "$kitty")")/share/icons/hicolor/256x256/apps/kitty.png
[[ -f $icon ]] || icon=kitty
stamp=$(date +%Y%m%d-%H%M%S)
say() { printf '%s\n' "$*"; }

# what a template turns into on this machine
rendered() { sed -e "s|@BIN@|$bin_dir|g" -e "s|@ICON@|$icon|g" "$1"; }

backup() { cp -p "$1" "$1.bak.$stamp" && say "  kept your $1 as $1.bak.$stamp"; }

# place SRC DEST: symlink (--dev) or copy, backing up a different file that is in the way
place() {
    local src=$1 dest=$2
    if [[ $mode == link ]]; then
        [[ -L $dest && $(readlink -f "$dest") == "$(readlink -f "$src")" ]] && return
    else
        [[ ! -L $dest ]] && cmp -s "$src" "$dest" 2>/dev/null && return
    fi
    if [[ -e $dest && ! -L $dest ]] && ! cmp -s "$src" "$dest"; then backup "$dest"; fi
    rm -f "$dest"
    if [[ $mode == link ]]; then ln -s "$src" "$dest"; else install -m "$(stat -c %a "$src")" "$src" "$dest"; fi
}

# render TEMPLATE DEST: always a real file, because it holds paths for this machine
render() {
    local tmp
    tmp=$(mktemp)
    rendered "$1" >"$tmp"
    if [[ -f $2 ]] && cmp -s "$tmp" "$2"; then rm -f "$tmp"; return; fi
    if [[ -e $2 && ! -L $2 ]]; then backup "$2"; fi
    rm -f "$2"
    install -m 644 "$tmp" "$2"
    rm -f "$tmp"
}

# remove DEST if it is what we would have installed (a link into this repo, an identical copy, or the render)
remove_ours() {
    local dest=$1 src=$2 kind=${3:-file}
    [[ -e $dest || -L $dest ]] || return 0
    if [[ -L $dest && $(readlink -f "$dest") == "$(readlink -f "$src")" ]] ||
        { [[ $kind == file ]] && cmp -s "$src" "$dest"; } ||
        { [[ $kind == template ]] && rendered "$src" | cmp -s - "$dest"; }; then
        rm -f "$dest" && say "  removed $dest"
    else
        say "  left $dest alone (it has been modified)"
    fi
}

check_kitty() {
    if [[ ! -x $kitty ]]; then
        if ((install_kitty)); then
            say "kitty not found: running kitty's official installer (into ~/.local/kitty.app)"
            curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
        else
            echo "install.sh: kitty >= 0.49 not found at $kitty" >&2
            echo "  install it with: curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n" >&2
            echo "  or re-run with --install-kitty, or point --kitty at your kitty >= 0.49" >&2
            exit 1
        fi
    fi
    local version
    version=$("$kitty" --version | awk '{print $2}')
    if [[ $(printf '%s\n0.49.0\n' "$version" | sort -V | head -n1) != 0.49.0 ]]; then
        echo "install.sh: $kitty is kitty $version; custom shaders need >= 0.49.0" >&2
        exit 1
    fi
    say "kitty $version at $kitty"
}

do_install() {
    check_kitty
    mkdir -p "$config_dir/shaders" "$bin_dir" "$apps_dir"
    say "installing ($mode) into $config_dir and $bin_dir"
    for f in "$repo"/shaders/*; do [[ -f $f ]] && place "$f" "$config_dir/shaders/$(basename "$f")"; done
    for f in "$repo"/bin/*; do [[ -f $f ]] && place "$f" "$bin_dir/$(basename "$f")"; done
    render "$repo/config/crt.conf.in" "$config_dir/crt.conf"
    [[ -e $config_dir/crt-monitor.conf ]] || install -m 644 "$repo/config/crt-monitor.conf" "$config_dir/crt-monitor.conf"
    render "$repo/share/applications/kitty-crt.desktop.in" "$apps_dir/kitty-crt.desktop"
    case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) say "note: $bin_dir is not on your PATH (kitty-crt and omp-crt still work with their full path)" ;;
    esac
    if ((prewarm)); then
        say "building the shader once so the first launch is instant (about 8 s)"
        KITTY_CONFIG_DIRECTORY=$config_dir CRT_MODE=warm CRT_BUILD=$repo/tools/shader-build.py \
            "$kitty" +runpy "exec(open(__import__('os').environ['CRT_BUILD']).read(), {})" 2>&1 | grep -v 'Ignoring unknown' || true
    fi
    cat <<EOF

done. Try it:
  $bin_dir/kitty-crt            a CRT terminal
  $bin_dir/omp-crt              omp inside it
  ctrl+alt+m                    monitor picker (inside a kitty-crt window)
EOF
}

do_uninstall() {
    say "removing kitty-crt from $config_dir and $bin_dir"
    for f in "$repo"/shaders/*; do [[ -f $f ]] && remove_ours "$config_dir/shaders/$(basename "$f")" "$f"; done
    for f in "$repo"/bin/*; do [[ -f $f ]] && remove_ours "$bin_dir/$(basename "$f")" "$f"; done
    remove_ours "$config_dir/crt.conf" "$repo/config/crt.conf.in" template
    remove_ours "$config_dir/crt-monitor.conf" "$repo/config/crt-monitor.conf"
    remove_ours "$apps_dir/kitty-crt.desktop" "$repo/share/applications/kitty-crt.desktop.in" template
}

"do_$action"
