#!/usr/bin/env bash

# Save the current wallpaper into "SAVED (NO OVERRIDES)" so it never gets
# overwritten by the "Random: Konachan" / "Random: Pixiv" buttons.
#
# Usage:  save_current_wallpaper.sh [NAME]
#   NAME  optional desired file name. An extension is optional (the source
#         file's extension is appended if missing); spaces and '?' are fine.
#         If omitted, the current wallpaper's own name is used.
#
# Never overwrites: if NAME is taken, NAME-1, NAME-2, ... are used instead.
# Target dir: ~/Pictures/Wallpapers/SAVED (NO OVERRIDES)/
# Override the dir with the WALLPAPER_SAVE_DIR env var.

get_pictures_dir() {
    if command -v xdg-user-dir &> /dev/null; then
        xdg-user-dir PICTURES
        return
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    if [ -f "$config_file" ]; then
        local pictures_path
        pictures_path=$(source "$config_file" >/dev/null 2>&1; echo "$XDG_PICTURES_DIR")
        echo "${pictures_path/#\$HOME/$HOME}"
        return
    fi

    echo "$HOME/Pictures"
}

QUICKSHELL_CONFIG_NAME="akari"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PICTURES_DIR=$(get_pictures_dir)
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

illogicalImpulseConfigPath="$HOME/.config/akari/config.json"
SAVE_DIR="${WALLPAPER_SAVE_DIR:-$PICTURES_DIR/Wallpapers/SAVED (NO OVERRIDES)}"

# --- Where is the current wallpaper? ---
sourcePath=$(jq -r '.background.wallpaperPath' "$illogicalImpulseConfigPath" 2>/dev/null)
if [ -z "$sourcePath" ] || [ ! -f "$sourcePath" ]; then
    echo "error: current wallpaper file not found ($sourcePath)"
    exit 1
fi

sourceName=$(basename "$sourcePath")
sourceExt="${sourceName##*.}"

# --- Figure out the desired name ---
name="$1"
if [ -z "$name" ]; then
    name="$sourceName"
else
    # Strip path separators and leading dots/spaces, keep spaces, '?', etc.
    name=$(echo "$name" | sed -e 's#[/\\]##g' -e 's/^\.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ -z "$name" ]; then
        name="$sourceName"
    elif [ "${name##*.}" = "$name" ]; then
        # No extension given -> reuse the source file's extension
        name="$name.$sourceExt"
    fi
fi

mkdir -p "$SAVE_DIR"

# --- Copy without ever overwriting ---
target="$SAVE_DIR/$name"
n=1
while [ -e "$target" ]; do
    target="$SAVE_DIR/${name%.*}-$n.${name##*.}"
    n=$((n + 1))
done

cp "$sourcePath" "$target"
echo "Saved: $target"